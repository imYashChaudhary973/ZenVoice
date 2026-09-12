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
        let lower = text.lowercased()
        if lower.contains("zoom.us/j") {
            return .zoom
        }
        if lower.contains("meet.google.com") {
            return .meet
        }
        if lower.contains("teams.microsoft.com")
            || lower.contains("teams.live.com")
        {
            return .teams
        }
        return .unknown
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
        return raw.isEmpty ? nil : raw
    }

    private static let urlExpression = try! NSRegularExpression(
        pattern: #"(?i)(?:https?://)?(?:(?:[\w-]+\.)*zoom\.us/j|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com)[^\s<>"']*"#
    )
}
