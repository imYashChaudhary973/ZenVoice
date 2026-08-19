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

/// Decode mode for the single Nemotron 3.5 row.
///
/// Both modes share one GGUF. Streaming is live-preview only. Offline is an
/// advanced whole-file path and is never the default final engine.
public enum NemotronPreferences {
    public static let modeKey = "ZenVoice.nemotron.decodeMode"

    public enum Mode: String, CaseIterable, Sendable {
        case streaming
        case offline

        public var displayName: String {
            switch self {
            case .streaming:
                return "Streaming"
            case .offline:
                return "Offline"
            }
        }
    }

    public static func load(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Mode {
        guard let raw = defaults.string(forKey: modeKey),
              let mode = Mode(rawValue: raw) else {
            return .streaming
        }
        return mode
    }

    public static func save(
        _ mode: Mode,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }
}
