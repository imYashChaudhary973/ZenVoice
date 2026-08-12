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

public final class HistoryPreferences {
    private enum Key {
        static let madeHistoryChoice = "ZenVoice.history.madeChoice"
        static let historyEnabled = "ZenVoice.history.enabled"
        static let hasEverEnabled = "ZenVoice.history.hasEverEnabled"
        static let retainsFailedAudio = "ZenVoice.history.retainsFailedAudio"
        static let retentionDays = "ZenVoice.history.retentionDays"
        static let privateMode = "ZenVoice.history.privateMode"
        static let vaultNeedsVacuum = "ZenVoice.history.vaultNeedsVacuum"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = RuntimeIdentity.userDefaults()) {
        self.defaults = defaults
    }

    public var hasMadeHistoryChoice: Bool {
        get {
            guard defaults.object(forKey: Key.madeHistoryChoice) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.madeHistoryChoice)
        }
        set { defaults.set(newValue, forKey: Key.madeHistoryChoice) }
    }

    public var isHistoryEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.historyEnabled) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.historyEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.historyEnabled)
            if newValue {
                defaults.set(true, forKey: Key.hasEverEnabled)
            }
            hasMadeHistoryChoice = true
        }
    }

    public var hasEverEnabledHistory: Bool {
        defaults.bool(forKey: Key.hasEverEnabled)
    }

    public var retainsFailedAudio: Bool {
        get {
            guard defaults.object(forKey: Key.retainsFailedAudio) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.retainsFailedAudio)
        }
        set { defaults.set(newValue, forKey: Key.retainsFailedAudio) }
    }

    public var retentionDays: Int {
        get {
            let stored = defaults.integer(forKey: Key.retentionDays)
            return stored > 0 ? stored : 30
        }
        set { defaults.set(max(1, newValue), forKey: Key.retentionDays) }
    }

    public var isPrivateModeEnabled: Bool {
        get { defaults.bool(forKey: Key.privateMode) }
        set { defaults.set(newValue, forKey: Key.privateMode) }
    }

    /// Whether the vault database needs a `VACUUM` after a large deletion.
    ///
    /// `VACUUM` can take seconds on a large database, so it is scheduled for
    /// the next idle launch rather than blocking the UI during `deleteAll()`.
    public var vaultNeedsVacuum: Bool {
        get { defaults.bool(forKey: Key.vaultNeedsVacuum) }
        set { defaults.set(newValue, forKey: Key.vaultNeedsVacuum) }
    }
}
