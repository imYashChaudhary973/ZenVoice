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

/// Rename-once map from channel labels (`You` / `Them`) to display names.
public struct SpeakerNameMap: Equatable, Sendable {
    public var you: String?
    public var them: String?

    public init(you: String? = nil, them: String? = nil) {
        self.you = you
        self.them = them
    }
}

/// Replaces leading `You:` / `Them:` prefixes. One pass so a mapped name
/// is not re-matched as the other channel.
public enum SpeakerLabeling {
    public static func applying(_ map: SpeakerNameMap, to transcript: String) -> String {
        transcript
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { relabel($0, map: map) }
            .joined(separator: "\n")
    }

    private static func relabel(_ line: Substring, map: SpeakerNameMap) -> String {
        if let you = map.you, !you.isEmpty, line.hasPrefix("You:") {
            return you + line.dropFirst(3)
        }
        if let them = map.them, !them.isEmpty, line.hasPrefix("Them:") {
            return them + line.dropFirst(4)
        }
        return String(line)
    }
}
