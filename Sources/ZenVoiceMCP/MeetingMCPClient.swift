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

public actor MeetingMCPClient {
    private let origin: URL
    private let source: MeetingMCPDataSource
    private let devices: MeetingMCPDeviceStoring
    private let session: URLSession

    public init(
        origin: URL,
        source: MeetingMCPDataSource,
        devices: MeetingMCPDeviceStoring,
        session: URLSession = .shared
    ) {
        self.origin = origin
        self.source = source
        self.devices = devices
        self.session = session
    }

    public func register() async throws -> MeetingMCPDeviceRecord {
        var body: [String: String] = [:]
        if let existing = try devices.load() {
            body = ["id": existing.id, "secret": existing.secret]
        }
        let payload = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(
            path: ["device", "register"],
            body: payload
        )
        let status = httpStatus(response)
        guard status == 200 || status == 201 else {
            throw MeetingMCPDeviceError.http(status)
        }
        guard let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let id = object["id"] as? String,
            let pairing = object["pairing"] as? String
        else {
            throw MeetingMCPDeviceError.api("Invalid device register response")
        }
        let secret: String
        if let issued = object["secret"] as? String, !issued.isEmpty {
            secret = issued
        } else if let existing = try devices.load() {
            secret = existing.secret
        } else {
            throw MeetingMCPDeviceError.api("Device secret missing")
        }
        let record = MeetingMCPDeviceRecord(
            id: id,
            secret: secret,
            pairing: pairing
        )
        try devices.save(record)
        return record
    }

    public func pullOnce() async throws {
        let record = try await register()
        var request = URLRequest(url: url("d", record.id, "pull"))
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(record.secret)",
            forHTTPHeaderField: "Authorization"
        )
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let status = httpStatus(response)
        if status == 204 { return }
        guard status == 200 else { throw MeetingMCPDeviceError.http(status) }
        guard let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let requestId = object["requestId"] as? String,
            let rpc = object["jsonrpc"]
        else {
            throw MeetingMCPDeviceError.api("Invalid pull payload")
        }
        let rpcData = try JSONSerialization.data(withJSONObject: rpc)
        let reply = try MeetingMCPServer.handle(jsonrpc: rpcData, store: source)
        let responseBody: Any
        if reply.isEmpty {
            responseBody = ["jsonrpc": "2.0", "id": NSNull(), "result": [:]]
        } else {
            responseBody = try JSONSerialization.jsonObject(with: reply)
        }
        let push = try JSONSerialization.data(withJSONObject: [
            "requestId": requestId,
            "response": responseBody,
        ])
        _ = try await send(
            path: ["d", record.id, "push"],
            body: push,
            bearer: record.secret
        )
    }

    public func revoke() async {
        guard let record = try? devices.load() else { return }
        var request = URLRequest(url: url("d", record.id, "revoke"))
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(record.secret)",
            forHTTPHeaderField: "Authorization"
        )
        _ = try? await session.data(for: request)
    }

    private func send(
        path: [String],
        body: Data,
        bearer: String? = nil
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30
        if let bearer {
            request.setValue(
                "Bearer \(bearer)",
                forHTTPHeaderField: "Authorization"
            )
        }
        return try await session.data(for: request)
    }

    private func url(_ parts: String...) -> URL { url(Array(parts)) }

    private func url(_ parts: [String]) -> URL {
        parts.reduce(origin) { $0.appendingPathComponent($1) }
    }

    private func httpStatus(_ response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}
