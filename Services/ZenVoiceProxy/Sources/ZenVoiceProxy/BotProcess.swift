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

import Foundation

struct BotJob {
    var id: String
    var url: String
    var process: Process
}

enum BotProcess {
    static func scriptURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment[
            "ZENVOICE_BOT_SCRIPT"
        ], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let here = URL(fileURLWithPath: #filePath)
        let candidate = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("bot/join.mjs")
        return FileManager.default.fileExists(atPath: candidate.path)
            ? candidate : nil
    }

    static func nodeURL() -> URL? {
        ["/Users/yashchaudhary/.local/bin/node", "/usr/local/bin/node", "/opt/homebrew/bin/node"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            ?? URL(fileURLWithPath: "/usr/bin/env")
    }

    static func join(url: String, name: String = "ZenVoice Notetaker") throws -> Process {
        guard let script = scriptURL() else {
            throw NSError(
                domain: "ZenVoiceProxy",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "join.mjs not found. Set ZENVOICE_BOT_SCRIPT."
                ]
            )
        }
        let process = Process()
        let node = nodeURL()!
        if node.lastPathComponent == "env" {
            process.executableURL = node
            process.arguments = ["node", script.path, url, name]
        } else {
            process.executableURL = node
            process.arguments = [script.path, url, name]
        }
        process.currentDirectoryURL = script.deletingLastPathComponent()
        process.terminationHandler = { _ in }
        try process.run()
        return process
    }

    static func leave(_ process: Process) {
        process.terminate()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }
        _ = group.wait(timeout: .now() + 3)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
