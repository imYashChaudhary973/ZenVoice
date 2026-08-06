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

/// Persistent preferences for the optional full-audio history archive.
///
/// Audio History is strictly opt-in and independent from transcript history.
/// The default settings cap total storage and age so the feature cannot grow
/// without bound.
public final class AudioHistoryPreferences {
    private enum Key {
        static let madeChoice = "ZenVoice.audioHistory.madeChoice"
        static let enabled = "ZenVoice.audioHistory.enabled"
        static let maxSizeBytes = "ZenVoice.audioHistory.maxSizeBytes"
        static let maxAgeDays = "ZenVoice.audioHistory.maxAgeDays"
    }

    /// Default total archive cap: 2 GB.
    public static let defaultMaxSizeBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    /// Default age cap: 30 days.
    public static let defaultMaxAgeDays = 30
    /// Minimum sensible cap: 100 MB.
    public static let minimumMaxSizeBytes: Int64 = 100 * 1_024 * 1_024

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = RuntimeIdentity.userDefaults()) {
        self.defaults = defaults
    }

    /// Whether the user has made an explicit choice about audio history.
    public var hasMadeChoice: Bool {
        get { defaults.object(forKey: Key.madeChoice) != nil }
        set { defaults.set(newValue, forKey: Key.madeChoice) }
    }

    /// Whether full-audio archival is enabled.
    public var isEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.enabled) != nil else {
                return false
            }
            return defaults.bool(forKey: Key.enabled)
        }
        set {
            defaults.set(newValue, forKey: Key.enabled)
            hasMadeChoice = true
        }
    }

    /// Maximum total archive size in bytes. Clamped to at least the minimum.
    public var maxSizeBytes: Int64 {
        get {
            let stored = defaults.object(forKey: Key.maxSizeBytes) as? Int
                ?? Int(Self.defaultMaxSizeBytes)
            return max(Self.minimumMaxSizeBytes, Int64(stored))
        }
        set {
            defaults.set(
                max(Self.minimumMaxSizeBytes, newValue),
                forKey: Key.maxSizeBytes
            )
        }
    }

    /// Maximum age of an archived recording in days. Clamped to at least 1.
    public var maxAgeDays: Int {
        get {
            let stored = defaults.integer(forKey: Key.maxAgeDays)
            return stored > 0 ? stored : Self.defaultMaxAgeDays
        }
        set { defaults.set(max(1, newValue), forKey: Key.maxAgeDays) }
    }

    /// A readable description of the current size cap.
    public var maxSizeDisplayString: String {
        ByteCountFormatter.string(
            fromByteCount: maxSizeBytes,
            countStyle: .binary
        )
    }
}
