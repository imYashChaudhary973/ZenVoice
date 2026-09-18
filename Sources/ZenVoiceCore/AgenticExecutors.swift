// Copyright 2026 Yash Chaudhary
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if os(macOS)
import Darwin
#endif
import Foundation

/// Runs one approved plan step without invoking an extra shell unless the step
/// itself is explicitly a shell step.
public actor ProcessGoalExecutor: GoalExecutor {
    private let agent: GoalAgent
    private var activeProcess: Process?
    private var timeoutTask: Task<Void, Never>?
    private var cancellationRequested = false
    private var timeoutReached = false

    public init(agent: GoalAgent) {
        self.agent = agent
    }

    public func run(
        step: GoalStep,
        output: @escaping @Sendable (ExecutorOutput) async -> Void
    ) async -> ExecutorOutcome {
        guard step.agent == agent else {
            return ExecutorOutcome(
                exitStatus: 64,
                summary: "Executor mismatch for \(step.agent.displayName)."
            )
        }
        guard let invocation = Self.invocation(for: step) else {
            return ExecutorOutcome(
                exitStatus: 127,
                summary: "\(step.agent.displayName) is not installed."
            )
        }

        cancellationRequested = false
        timeoutReached = false
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = URL(
            fileURLWithPath: step.workingDirectory
                ?? FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        process.environment = Self.minimalEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        installStreamingHandler(
            on: stdout.fileHandleForReading,
            channel: .stdout,
            output: output
        )
        installStreamingHandler(
            on: stderr.fileHandleForReading,
            channel: .stderr,
            output: output
        )
        activeProcess = process

        let status: Int32
        do {
            status = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { terminated in
                        continuation.resume(
                            returning: terminated.terminationStatus
                        )
                    }
                    do {
                        try Task.checkCancellation()
                        try process.run()
                        #if os(macOS)
                        // Foundation's Process offers no pre-exec hook, so
                        // setpgid can only follow run(): there is a window
                        // where the child may spawn a grandchild that escapes
                        // the process group and survives kill(-pid) during
                        // cancellation. Accepted because the window is
                        // microseconds wide, the child agents (codex, claude,
                        // zsh) do not fork that early, and an escaped
                        // grandchild still dies when its parent group is
                        // reaped or it finishes its own work.
                        _ = setpgid(
                            process.processIdentifier,
                            process.processIdentifier
                        )
                        #endif
                        timeoutTask = Task { [weak self] in
                            try? await Task.sleep(
                                for: .seconds(step.timeoutSeconds)
                            )
                            await self?.timeoutActiveProcess()
                        }
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            } onCancel: {
                Task { await self.cancel() }
            }
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            activeProcess = nil
            return ExecutorOutcome(
                exitStatus: 127,
                summary: "Could not launch \(step.agent.displayName): \(error.localizedDescription)"
            )
        }

        timeoutTask?.cancel()
        timeoutTask = nil
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        activeProcess = nil

        if timeoutReached {
            return ExecutorOutcome(
                exitStatus: status,
                summary: "Step timed out after \(Int(step.timeoutSeconds)) seconds.",
                timedOut: true
            )
        }
        if cancellationRequested {
            return ExecutorOutcome(
                exitStatus: status,
                summary: "Step cancelled.",
                cancelled: true
            )
        }
        return ExecutorOutcome(
            exitStatus: status,
            summary: status == 0
                ? "\(step.agent.displayName) completed."
                : "\(step.agent.displayName) exited with status \(status)."
        )
    }

    public func cancel() async {
        cancellationRequested = true
        await terminateActiveProcess()
    }

    private func timeoutActiveProcess() async {
        guard activeProcess?.isRunning == true else { return }
        timeoutReached = true
        await terminateActiveProcess()
    }

    /// Terminates the whole child process group, then escalates. The wait is
    /// polled rather than a flat five-second sleep: a well-behaved child dies
    /// on the first signal, and the HUD should say "cancelled" then, not five
    /// seconds later.
    private func terminateActiveProcess() async {
        guard let process = activeProcess, process.isRunning else { return }
        let pid = process.processIdentifier
        #if os(macOS)
        if kill(-pid, SIGTERM) != 0 {
            process.terminate()
        }
        for _ in 0..<50 {
            guard process.isRunning else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning {
            _ = kill(-pid, SIGKILL)
        }
        #else
        process.terminate()
        #endif
    }

    private func installStreamingHandler(
        on handle: FileHandle,
        channel: ExecutorOutput.Channel,
        output: @escaping @Sendable (ExecutorOutput) async -> Void
    ) {
        // A UTF-8 sequence can split across pipe chunks; decoding each chunk
        // in isolation corrupts it into U+FFFD. Hold the trailing partial
        // sequence back and only emit complete characters. readabilityHandler
        // is invoked serially by FileHandle, so the local buffer is safe.
        nonisolated(unsafe) var pending = Data()
        handle.readabilityHandler = { readable in
            let data = readable.availableData
            if data.isEmpty {
                // End of stream: flush whatever is left, lossily.
                guard !pending.isEmpty else { return }
                let text = String(decoding: pending, as: UTF8.self)
                pending = Data()
                Task {
                    await output(ExecutorOutput(channel: channel, text: text))
                }
                return
            }
            pending.append(data)
            let (complete, remainder) = Self.splitAtCharacterBoundary(pending)
            pending = remainder
            guard !complete.isEmpty else {
                return
            }
            // Lossy by design: complete ends at a character boundary, so
            // valid sequences survive and malformed bytes surface as U+FFFD
            // instead of silently dropping the chunk.
            let text = String(decoding: complete, as: UTF8.self)
            guard !text.isEmpty else {
                return
            }
            Task {
                await output(ExecutorOutput(channel: channel, text: text))
            }
        }
    }

    /// Splits `data` at the last character boundary so a trailing, incomplete
    /// UTF-8 sequence is held for the next chunk instead of decoding to
    /// U+FFFD. Malformed bytes that cannot be a sequence prefix at all pass
    /// through unchanged (the lossy decode will surface them).
    private static func splitAtCharacterBoundary(
        _ data: Data
    ) -> (complete: Data, pending: Data) {
        var lead = data.count - 1
        while lead >= 0, lead >= data.count - 4,
              data[data.startIndex + lead] & 0xC0 == 0x80 {
            lead -= 1
        }
        guard lead >= 0, data[data.startIndex + lead] & 0x80 != 0 else {
            return (data, Data())
        }
        let byte = data[data.startIndex + lead]
        let expectedLength: Int
        if byte & 0xE0 == 0xC0 {
            expectedLength = 2
        } else if byte & 0xF0 == 0xE0 {
            expectedLength = 3
        } else if byte & 0xF8 == 0xF0 {
            expectedLength = 4
        } else {
            // Not a valid sequence lead; nothing to hold back.
            return (data, Data())
        }
        guard data.count - lead < expectedLength else {
            return (data, Data())
        }
        // Small copies are fine: pipe chunks are small, and Data slicing is
        // index-ambiguous enough to cost more than the copy in review time.
        return (Data(data.prefix(lead)), Data(data.dropFirst(lead)))
    }

    private struct Invocation {
        let executable: URL
        let arguments: [String]
    }

    private static func invocation(for step: GoalStep) -> Invocation? {
        switch step.agent {
        case .codex:
            guard let executable = executable(named: "codex") else { return nil }
            return Invocation(
                executable: executable,
                arguments: [
                    "exec", "--json", "--ephemeral",
                    "--sandbox", "workspace-write", "--approve-for-me",
                    "--skip-git-repo-check",
                    "--cd", step.workingDirectory
                        ?? FileManager.default.currentDirectoryPath,
                    step.command,
                ]
            )
        case .claude:
            guard let executable = executable(named: "claude") else { return nil }
            return Invocation(
                executable: executable,
                arguments: [
                    "--print", "--verbose",
                    "--output-format", "stream-json",
                    "--permission-mode", "acceptEdits",
                    "--no-session-persistence", step.command,
                ]
            )
        case .shell:
            return Invocation(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-c", step.command]
            )
        case .shortcut:
            return Invocation(
                executable: URL(fileURLWithPath: "/usr/bin/shortcuts"),
                arguments: ["run", step.command]
            )
        case .notification:
            return nil
        }
    }

    private static func executable(named name: String) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        return candidates.first(where: FileManager.default.isExecutableFile)
            .map { URL(fileURLWithPath: $0) }
    }

    private static func minimalEnvironment() -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        // Tools the user installs outside a package manager (pipx --user,
        // plain `make install`) live here; skip them if the directories do
        // not exist rather than polluting PATH with dead entries.
        for directory in [
            home.appendingPathComponent(".local/bin"),
            home.appendingPathComponent("bin"),
        ] where FileManager.default.fileExists(atPath: directory.path) {
            path += ":" + directory.path
        }
        return [
            "HOME": home.path,
            "PATH": path,
            "TMPDIR": environment["TMPDIR"] ?? NSTemporaryDirectory(),
            "LANG": environment["LANG"] ?? "en_US.UTF-8",
        ]
    }
}
