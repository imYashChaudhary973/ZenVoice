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

/// Persists the user's chosen speech engine per language profile.
///
/// A profile can have a different engine from another profile: English may use
/// Apple Speech while Hinglish uses Whisper. The key is the profile identifier,
/// so selecting a language also restores its last engine choice.
public enum SelectedEnginePreferences {
    public static let preferenceKey = "ZenVoice.selectedEngineIDs"

    public static func load(
        for profile: LanguageProfile,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> String? {
        guard let dictionary = defaults.dictionary(forKey: preferenceKey)
                as? [String: String] else {
            return nil
        }
        return dictionary[profile.id]
    }

    public static func save(
        _ engineID: String,
        for profile: LanguageProfile,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        var dictionary =
            (defaults.dictionary(forKey: preferenceKey) as? [String: String])
            ?? [:]
        dictionary[profile.id] = engineID
        defaults.set(dictionary, forKey: preferenceKey)
    }

    public static func clear(
        for profile: LanguageProfile,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        guard var dictionary = defaults.dictionary(forKey: preferenceKey)
                as? [String: String] else {
            return
        }
        dictionary.removeValue(forKey: profile.id)
        defaults.set(dictionary, forKey: preferenceKey)
    }

    /// Migrates installs that selected a Whisper model before ZenVoice stored
    /// an engine preference. Without this, the new recommendation order can
    /// silently route an explicitly chosen Whisper model through Parakeet.
    @discardableResult
    public static func migrateLegacyWhisperSelectionIfNeeded(
        for profile: LanguageProfile,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        guard load(for: profile, defaults: defaults) == nil,
              ModelSelectionPreferences.load(defaults: defaults) != nil else {
            return false
        }
        save(EngineIdentifiers.whisper, for: profile, defaults: defaults)
        return true
    }
}
