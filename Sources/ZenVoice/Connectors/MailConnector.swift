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

struct MeetingContextQuery: Equatable, Sendable {
    var attendeeEmails: [String]
    var windowStart: Date
    var windowEnd: Date
    var title: String
}

struct ConnectorHit: Equatable, Sendable {
    var source: String
    var timestamp: Date
    var snippet: String
    var url: URL?
}

enum ConnectorError: Error, Equatable {
    case missingToken
    case http(Int)
    case api(String)
    case malformedResponse
}

enum ConnectorHTTP {
    static func get(
        _ url: URL,
        bearer: String,
        session: URLSession
    ) async throws -> Data {
        guard !bearer.isEmpty else { throw ConnectorError.missingToken }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ConnectorError.http(http.statusCode)
        }
        return data
    }

    static func json(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ConnectorError.malformedResponse
        }
        return object
    }
}

protocol MailConnecting: Sendable {
    func search(_ query: MeetingContextQuery) async throws -> [ConnectorHit]
}

/// Gmail `users.messages.list` + `users.messages.get` for the signed-in user.
struct MailConnector: MailConnecting, Sendable {
    private let bearerToken: String
    private let session: URLSession

    init(bearerToken: String, session: URLSession = .shared) {
        self.bearerToken = bearerToken
        self.session = session
    }

    func search(_ query: MeetingContextQuery) async throws -> [ConnectorHit] {
        let data = try await ConnectorHTTP.get(
            try listURL(for: query),
            bearer: bearerToken,
            session: session
        )
        let ids = (try ConnectorHTTP.json(data)["messages"] as? [[String: Any]] ?? [])
            .compactMap { $0["id"] as? String }
        var hits: [ConnectorHit] = []
        hits.reserveCapacity(ids.count)
        for id in ids {
            hits.append(try await message(id))
        }
        return hits
    }

    private func listURL(for query: MeetingContextQuery) throws -> URL {
        var components = URLComponents(
            string: "https://gmail.googleapis.com/gmail/v1/users/me/messages"
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: gmailQuery(query)),
            URLQueryItem(name: "maxResults", value: "10"),
        ]
        guard let url = components.url else { throw ConnectorError.malformedResponse }
        return url
    }

    private func message(_ id: String) async throws -> ConnectorHit {
        var components = URLComponents(
            string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)"
        )!
        components.queryItems = [URLQueryItem(name: "format", value: "metadata")]
        guard let url = components.url else { throw ConnectorError.malformedResponse }
        let object = try ConnectorHTTP.json(
            try await ConnectorHTTP.get(url, bearer: bearerToken, session: session)
        )
        let ms = Double(object["internalDate"] as? String ?? "") ?? 0
        let thread = object["threadId"] as? String ?? id
        return ConnectorHit(
            source: "gmail",
            timestamp: Date(timeIntervalSince1970: ms / 1000),
            snippet: object["snippet"] as? String ?? "",
            url: URL(string: "https://mail.google.com/mail/#all/\(thread)")
        )
    }

    private func gmailQuery(_ query: MeetingContextQuery) -> String {
        var parts = [
            "after:\(Int(query.windowStart.timeIntervalSince1970))",
            "before:\(Int(query.windowEnd.timeIntervalSince1970))",
        ]
        let people = query.attendeeEmails.filter { !$0.isEmpty }
        if !people.isEmpty {
            parts.append(
                "(\(people.map { "from:\($0) OR to:\($0)" }.joined(separator: " OR ")))"
            )
        }
        let title = query.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            parts.append("\"\(title)\"")
        }
        return parts.joined(separator: " ")
    }
}
