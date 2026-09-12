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
import Network

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else { return nil }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return nil }
        let pathPart = parts[1]
        let path = pathPart.split(separator: "?", maxSplits: 1).first.map(String.init) ?? String(pathPart)
        return HTTPRequest(
            method: String(parts[0]),
            path: path,
            headers: headers,
            body: Data(body.prefix(length))
        )
    }
}

final class ProxyServer {
    private let token: String
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "zenvoice.proxy")
    private var listener: NWListener?
    // ponytail: in-memory map; persist if bots must survive restart
    private var jobs: [String: String] = [:]

    init(token: String, port: UInt16) {
        self.token = token
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                fputs("listener failed: \(error)\n", stderr)
                exit(1)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        fputs("ZenVoiceProxy listening on 127.0.0.1:\(port.rawValue)\n", stderr)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.count > 65_536 {
                self.reply(connection, status: 413, reason: "Payload Too Large", type: "text/plain", body: "too large")
                return
            }
            if let request = HTTPRequest.parse(buffer) {
                self.handle(request, on: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.read(connection, buffer: buffer)
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            reply(connection, status: 200, reason: "OK", type: "text/plain", body: "ok")
        case ("POST", "/bot/join"):
            guard authorized(request) else {
                unauthorized(connection)
                return
            }
            guard let url = jsonString(request.body, key: "url"), !url.isEmpty else {
                json(connection, status: 400, reason: "Bad Request", object: ["error": "url required"])
                return
            }
            let id = UUID().uuidString
            jobs[id] = url
            // ponytail: queued stub only; real Zoom/Meet/Teams join when the bot worker exists
            json(
                connection,
                status: 202,
                reason: "Accepted",
                object: ["id": id, "status": "queued", "url": url]
            )
        case ("POST", "/bot/leave"):
            guard authorized(request) else {
                unauthorized(connection)
                return
            }
            guard let id = jsonString(request.body, key: "id"), !id.isEmpty else {
                json(connection, status: 400, reason: "Bad Request", object: ["error": "id required"])
                return
            }
            jobs.removeValue(forKey: id)
            json(connection, status: 200, reason: "OK", object: ["id": id, "status": "left"])
        default:
            json(connection, status: 404, reason: "Not Found", object: ["error": "not found"])
        }
    }

    private func authorized(_ request: HTTPRequest) -> Bool {
        request.headers["authorization"] == "Bearer \(token)"
    }

    private func unauthorized(_ connection: NWConnection) {
        json(connection, status: 401, reason: "Unauthorized", object: ["error": "unauthorized"])
    }

    private func jsonString(_ data: Data, key: String) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?[key] as? String
    }

    private func json(
        _ connection: NWConnection,
        status: Int,
        reason: String,
        object: [String: String]
    ) {
        let payload = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        reply(
            connection,
            status: status,
            reason: reason,
            type: "application/json",
            body: String(data: payload, encoding: .utf8) ?? "{}"
        )
    }

    private func reply(
        _ connection: NWConnection,
        status: Int,
        reason: String,
        type: String,
        body: String
    ) {
        let payload = Data(body.utf8)
        var message = "HTTP/1.1 \(status) \(reason)\r\n"
        message += "Content-Type: \(type)\r\n"
        message += "Content-Length: \(payload.count)\r\n"
        message += "Connection: close\r\n\r\n"
        var data = Data(message.utf8)
        data.append(payload)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
