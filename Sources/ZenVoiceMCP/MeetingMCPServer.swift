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
import ZenVoiceStorage

public struct MeetingMCPSummary: Codable, Sendable {
    public var id: String
    public var title: String
    public var startedAt: String
    public var endedAt: String?
    public var status: String
    public var sourceName: String
}

public struct MeetingMCPNote: Codable, Sendable {
    public var kind: String
    public var text: String
    public var owner: String?
    public var due: String?
}

public struct MeetingMCPDetail: Codable, Sendable {
    public var summary: MeetingMCPSummary
    public var transcript: String
    public var notes: [MeetingMCPNote]
    public var followUpDraft: String?
}

public protocol MeetingMCPDataSource: Sendable {
    func listReady() throws -> [MeetingMCPSummary]
    func search(query: String) throws -> [MeetingMCPSummary]
    func get(id: String) throws -> MeetingMCPDetail
    func notes(meetingID: String?) throws -> [MeetingMCPNote]
}

public struct EmptyMeetingMCPStore: MeetingMCPDataSource {
    public init() {}
    public func listReady() throws -> [MeetingMCPSummary] { [] }
    public func search(query: String) throws -> [MeetingMCPSummary] { [] }
    public func get(id: String) throws -> MeetingMCPDetail { throw MeetingError.missingMeeting }
    public func notes(meetingID: String?) throws -> [MeetingMCPNote] { [] }
}

public struct MeetingVaultStore: MeetingMCPDataSource {
    private let vault: MeetingVault

    public init(vault: MeetingVault) { self.vault = vault }

    public func listReady() throws -> [MeetingMCPSummary] {
        try ready().map(Self.summary)
    }

    public func search(query: String) throws -> [MeetingMCPSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return try listReady() }
        return try ready().filter { Self.matches($0, query: q) }.map(Self.summary)
    }

    public func get(id: String) throws -> MeetingMCPDetail {
        let meeting = try ready(id)
        return MeetingMCPDetail(
            summary: Self.summary(meeting),
            transcript: meeting.transcript,
            notes: Self.notes(from: meeting),
            followUpDraft: meeting.notes?.followUpDraft
        )
    }

    public func notes(meetingID: String?) throws -> [MeetingMCPNote] {
        if let meetingID { return Self.notes(from: try ready(meetingID)) }
        return try ready().flatMap(Self.notes(from:))
    }

    private func ready() throws -> [Meeting] {
        try vault.all().filter { $0.status == .ready }
    }

    private func ready(_ id: String) throws -> Meeting {
        guard let uuid = UUID(uuidString: id) else { throw MeetingError.missingMeeting }
        let meeting = try vault.load(uuid)
        guard meeting.status == .ready else { throw MeetingError.missingMeeting }
        return meeting
    }

    private static func summary(_ meeting: Meeting) -> MeetingMCPSummary {
        MeetingMCPSummary(
            id: meeting.id.uuidString,
            title: meeting.title,
            startedAt: meeting.startedAt.ISO8601Format(),
            endedAt: meeting.endedAt?.ISO8601Format(),
            status: meeting.status.rawValue,
            sourceName: meeting.sourceName
        )
    }

    private static func notes(from meeting: Meeting) -> [MeetingMCPNote] {
        (meeting.notes?.claims ?? []).map {
            MeetingMCPNote(kind: $0.kind, text: $0.text, owner: $0.owner, due: $0.due)
        }
    }

    // ponytail: linear scan of ready meetings; index if vaults get large
    private static func matches(_ meeting: Meeting, query: String) -> Bool {
        if meeting.title.localizedCaseInsensitiveContains(query) { return true }
        if meeting.transcript.localizedCaseInsensitiveContains(query) { return true }
        if meeting.notes?.followUpDraft.localizedCaseInsensitiveContains(query) == true { return true }
        return meeting.notes?.claims.contains { $0.text.localizedCaseInsensitiveContains(query) } == true
    }
}

public enum MeetingMCPPreferences {
    public static let enabledKey = "ZenVoice.mcp.connectorsEnabled"

    public static func origin() -> URL? {
        let raw = ProcessInfo.processInfo.environment["ZENVOICE_MCP_ORIGIN"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "ZenVoiceMCPOrigin") as? String)
            ?? "https://mcp.builderhelm.com"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host,
              url.scheme == "https" || host == "127.0.0.1" || host == "localhost"
        else { return nil }
        return url
    }
}

public enum MeetingMCPServer {
    public static func handle(jsonrpc request: Data, store: MeetingMCPDataSource) throws -> Data {
        guard let obj = try JSONSerialization.jsonObject(with: request) as? [String: Any],
              let method = obj["method"] as? String
        else {
            return try rpcError(id: NSNull(), code: -32700, message: "Parse error")
        }
        if method == "notifications/initialized" { return Data() }
        let id = obj["id"] ?? NSNull()
        let params = obj["params"] as? [String: Any] ?? [:]
        do {
            switch method {
            case "initialize":
                return try rpcResult(id: id, [
                    "protocolVersion": "2024-11-05",
                    "capabilities": ["tools": [:] as [String: Any]],
                    "serverInfo": ["name": "ZenVoice", "version": "1.0"],
                ])
            case "tools/list":
                return try rpcResult(id: id, ["tools": tools])
            case "tools/call":
                return try call(id: id, params: params, store: store)
            default:
                return try rpcError(id: id, code: -32601, message: "Method not found")
            }
        } catch MeetingError.missingMeeting {
            return try rpcError(id: id, code: -32602, message: MeetingError.missingMeeting.localizedDescription)
        } catch let error as CallError {
            return try rpcError(id: id, code: error.code, message: error.message)
        } catch {
            return try rpcError(id: id, code: -32603, message: error.localizedDescription)
        }
    }

    /// LSP Content-Length framing for stdio MCP.
    public static func stdioFrame(_ json: Data) -> Data {
        Data("Content-Length: \(json.count)\r\n\r\n".utf8) + json
    }

    private struct CallError: Error {
        var code: Int
        var message: String
    }

    private static let tools: [[String: Any]] = [
        tool("list_meetings", "List ready notetaker meetings.", [:], required: []),
        tool("search_meetings", "Search ready meetings by title, transcript, and notes.", ["query": ["type": "string"]], required: ["query"]),
        tool("get_meeting", "Get one ready meeting, including transcript and notes.", ["id": ["type": "string"]], required: ["id"]),
        tool("list_meeting_notes", "List notes from ready meetings.", ["id": ["type": "string"]], required: []),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String]) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema]
    }

    private static func call(id: Any, params: [String: Any], store: MeetingMCPDataSource) throws -> Data {
        guard let name = params["name"] as? String else {
            throw CallError(code: -32602, message: "Missing tool name")
        }
        let args = params["arguments"] as? [String: Any] ?? [:]
        switch name {
        case "list_meetings":
            return try toolResult(id: id, store.listReady())
        case "search_meetings":
            guard let query = args["query"] as? String else {
                throw CallError(code: -32602, message: "Missing query")
            }
            return try toolResult(id: id, store.search(query: query))
        case "get_meeting":
            guard let meetingID = args["id"] as? String, !meetingID.isEmpty else {
                throw CallError(code: -32602, message: "Missing id")
            }
            return try toolResult(id: id, store.get(id: meetingID))
        case "list_meeting_notes":
            let meetingID = (args["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return try toolResult(id: id, store.notes(meetingID: meetingID))
        default:
            throw CallError(code: -32601, message: "Unknown tool")
        }
    }

    private static func toolResult(id: Any, _ value: some Encodable) throws -> Data {
        let text = String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "null"
        return try rpcResult(id: id, ["content": [["type": "text", "text": text]]])
    }

    private static func rpcResult(id: Any, _ result: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func rpcError(id: Any, code: Int, message: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": message],
        ])
    }
}
