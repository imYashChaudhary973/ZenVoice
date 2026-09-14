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

public enum MeetingURLKind: String, Equatable, Sendable {
    case zoom
    case meet
    case teams
    case unknown
}

/// Bundle IDs and URL parsing for Zoom / Meet / Teams. No EventKit, no AppKit.
public enum MeetingDetection {
    public static let zoomBundleID = "us.zoom.xos"
    public static let teamsBundleID = "com.microsoft.teams"
    public static let teams2BundleID = "com.microsoft.teams2"
    public static let slackBundleID = "com.tinyspeck.slackmacgap"

    public static let meetingAppBundleIDs: Set<String> = [
        zoomBundleID,
        teamsBundleID,
        teams2BundleID,
        slackBundleID,
    ]

    public static func isMeetingApp(bundleID: String) -> Bool {
        meetingAppBundleIDs.contains(bundleID)
    }

    public static func kind(of text: String) -> MeetingURLKind {
        guard let url = httpsURL(from: text) else { return .unknown }
        return kind(of: url)
    }

    /// Browser join URL so the bot is a guest, not the user's Zoom.app.
    public static func webJoinURL(from raw: String) -> URL? {
        guard let url = httpsURL(from: raw) else { return nil }
        switch kind(of: url) {
        case .unknown:
            return nil
        case .meet, .teams:
            return url
        case .zoom:
            let path = url.path.lowercased()
            guard path.hasPrefix("/j/") else { return url }
            let rest = String(url.path.dropFirst(3))
            let id = rest.split(separator: "/").first.map(String.init) ?? rest
            var components = URLComponents(
                string: "https://app.zoom.us/wc/\(id)/join"
            )
            components?.query = url.query
            return components?.url ?? url
        }
    }

    public static func meetingURL(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = urlExpression.firstMatch(
            in: text,
            range: range
        ),
            let swiftRange = Range(match.range, in: text)
        else {
            return nil
        }
        let raw = String(text[swiftRange]).trimmingCharacters(
            in: CharacterSet(charactersIn: ".,;:)]>")
        )
        guard !raw.isEmpty, kind(of: raw) != .unknown else { return nil }
        return raw
    }

    private static func kind(of url: URL) -> MeetingURLKind {
        guard url.user == nil, url.password == nil else { return .unknown }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .unknown
        }
        let path = url.path.lowercased()
        if isZoomHost(host) {
            if path.hasPrefix("/j/") || path.hasPrefix("/wc/") {
                return .zoom
            }
            return .unknown
        }
        if host == "meet.google.com" { return .meet }
        if host == "teams.microsoft.com" || host == "teams.live.com" {
            return .teams
        }
        return .unknown
    }

    private static func isZoomHost(_ host: String) -> Bool {
        host == "zoom.us" || host.hasSuffix(".zoom.us")
    }

    private static func httpsURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if !text.lowercased().hasPrefix("http://"),
           !text.lowercased().hasPrefix("https://")
        {
            text = "https://\(text)"
        }
        guard let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.host != nil
        else {
            return nil
        }
        return components.url
    }

    private static let urlExpression = try! NSRegularExpression(
        pattern: #"(?i)(?:https?://)?(?:(?:[\w-]+\.)*zoom\.us/j|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com)[^\s<>"']*"#
    )
}
