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

protocol SlackConnecting: Sendable {
    func search(_ query: MeetingContextQuery) async throws -> [ConnectorHit]
}

/// Slack `search.messages` with a user token. Does not scrape other users.
struct SlackConnector: SlackConnecting, Sendable {
    private let bearerToken: String
    private let session: URLSession

    init(bearerToken: String, session: URLSession = .shared) {
        self.bearerToken = bearerToken
        self.session = session
    }

    func search(_ query: MeetingContextQuery) async throws -> [ConnectorHit] {
        let object = try ConnectorHTTP.json(
            try await ConnectorHTTP.get(
                try searchURL(for: query),
                bearer: bearerToken,
                session: session
            )
        )
        guard object["ok"] as? Bool == true else {
            throw ConnectorError.api(object["error"] as? String ?? "slack")
        }
        let matches =
            (object["messages"] as? [String: Any])?["matches"] as? [[String: Any]] ?? []
        return matches.map { match in
            let ts = Double(match["ts"] as? String ?? "") ?? 0
            return ConnectorHit(
                source: "slack",
                timestamp: Date(timeIntervalSince1970: ts),
                snippet: match["text"] as? String ?? "",
                url: (match["permalink"] as? String).flatMap(URL.init(string:))
            )
        }
    }

    private func searchURL(for query: MeetingContextQuery) throws -> URL {
        var components = URLComponents(string: "https://slack.com/api/search.messages")!
        components.queryItems = [
            URLQueryItem(name: "query", value: slackQuery(query)),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "sort", value: "timestamp"),
        ]
        guard let url = components.url else { throw ConnectorError.malformedResponse }
        return url
    }

    private func slackQuery(_ query: MeetingContextQuery) -> String {
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        day.timeZone = TimeZone(secondsFromGMT: 0)
        var parts: [String] = []
        let title = query.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            parts.append("\"\(title)\"")
        }
        parts.append(contentsOf: query.attendeeEmails.filter { !$0.isEmpty })
        parts.append("after:\(day.string(from: query.windowStart))")
        parts.append("before:\(day.string(from: query.windowEnd))")
        return parts.joined(separator: " ")
    }
}
