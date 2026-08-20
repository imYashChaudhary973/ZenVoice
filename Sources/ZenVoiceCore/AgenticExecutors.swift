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
        handle.readabilityHandler = { readable in
            let data = readable.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8),
                  !text.isEmpty
            else {
                return
            }
            Task {
                await output(ExecutorOutput(channel: channel, text: text))
            }
        }
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
        return [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": environment["TMPDIR"] ?? NSTemporaryDirectory(),
            "LANG": environment["LANG"] ?? "en_US.UTF-8",
        ]
    }
}
