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
import ZenVoiceCore

enum MeetingBotClient {
    struct Job {
        var id: String
        var url: String
        var localProcess: Process?
    }
    enum BotError: LocalizedError {
        case invalidURL
        case proxy(String)
        case missingWorker
        case signInRequired
        case invalidMeeting
        case notJoined(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "That is not a Zoom, Meet, or Teams link."
            case .proxy(let message):
                return message
            case .missingWorker:
                return "Install the bot worker: cd Services/ZenVoiceProxy/bot && npm install && npx playwright install chromium"
            case .signInRequired:
                return "Sign into Google/Zoom in the bot window once (profile at ~/Library/Application Support/ZenVoice/BotProfile), then Join as bot again."
            case .invalidMeeting:
                return "That meeting link is invalid."
            case .notJoined(let status):
                return "Bot did not join (\(status))."
            }
        }
    }

    static func join(_ raw: String, name: String = "ZenVoice Notetaker") async throws -> Job {
        guard let joinURL = MeetingDetection.webJoinURL(from: raw),
              MeetingDetection.kind(of: raw) != .unknown else {
            throw BotError.invalidURL
        }
        if let job = try await joinViaProxy(joinURL.absoluteString) {
            return job
        }
        return try await joinLocally(url: joinURL.absoluteString, name: name)
    }

    static func leave(_ job: Job) async {
        if job.localProcess != nil {
            job.localProcess?.terminate()
            return
        }
        guard let token = ProcessInfo.processInfo.environment[
            "ZENVOICE_PROXY_TOKEN"
        ], !token.isEmpty else { return }
        var request = URLRequest(url: proxyURL.appendingPathComponent("bot/leave"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["id": job.id]
        )
        _ = try? await URLSession.shared.data(for: request)
    }

    private static var proxyURL: URL {
        URL(
            string: ProcessInfo.processInfo.environment["ZENVOICE_PROXY_URL"]
                ?? "http://127.0.0.1:8787"
        )!
    }

    private static func joinViaProxy(_ url: String) async throws -> Job? {
        guard let token = ProcessInfo.processInfo.environment[
            "ZENVOICE_PROXY_TOKEN"
        ], !token.isEmpty else {
            return nil
        }
        var request = URLRequest(url: proxyURL.appendingPathComponent("bot/join"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["url": url]
        )
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 202,
               let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
               let id = object["id"] as? String {
                return Job(id: id, url: url, localProcess: nil)
            }
            if http.statusCode >= 400 {
                let message = (try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any])?["error"] as? String
                throw BotError.proxy(message ?? "Proxy join failed.")
            }
            return nil
        } catch let error as BotError {
            throw error
        } catch {
            return nil
        }
    }

    private static func joinLocally(url: String, name: String) async throws -> Job {
        let script = scriptURL()
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw BotError.missingWorker
        }
        let process = Process()
        let pipe = Pipe()
        let node = [
            "/Users/yashchaudhary/.local/bin/node",
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node"
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/usr/bin/env"
        if (node as NSString).lastPathComponent == "env" {
            process.executableURL = URL(fileURLWithPath: node)
            process.arguments = ["node", script.path, url, name]
        } else {
            process.executableURL = URL(fileURLWithPath: node)
            process.arguments = [script.path, url, name]
        }
        process.currentDirectoryURL = script.deletingLastPathComponent()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw BotError.missingWorker
        }
        let handle = pipe.fileHandleForReading
        var buffer = Data()
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if !process.isRunning && buffer.isEmpty {
                throw BotError.notJoined("exited")
            }
            let chunk = handle.availableData
            buffer.append(chunk)
            if let text = String(data: buffer, encoding: .utf8),
               let start = text.firstIndex(of: "{"),
               let jsonData = String(text[start...])
                .data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: jsonData)
                as? [String: Any],
               let status = object["status"] as? String {
                if status == "joined" {
                    return Job(
                        id: "local-\(process.processIdentifier)",
                        url: url,
                        localProcess: process
                    )
                }
                process.terminate()
                if status == "sign_in_required" { throw BotError.signInRequired }
                if status == "invalid_meeting" { throw BotError.invalidMeeting }
                throw BotError.notJoined(status)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        process.terminate()
        throw BotError.notJoined("timed out")
    }

    private static func scriptURL() -> URL {
        if let override = ProcessInfo.processInfo.environment[
            "ZENVOICE_BOT_SCRIPT"
        ], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let cwd = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath
        )
        let relative = cwd.appendingPathComponent(
            "Services/ZenVoiceProxy/bot/join.mjs"
        )
        if FileManager.default.fileExists(atPath: relative.path) {
            return relative
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Services/ZenVoiceProxy/bot/join.mjs")
    }
}
