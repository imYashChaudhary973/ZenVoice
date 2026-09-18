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
/// Parakeet TDT v3 while Hinglish uses Whisper. The key is the profile identifier,
/// so selecting a language also restores its last engine choice.
public enum SelectedEnginePreferences {
    public static let preferenceKey = "ZenVoice.selectedEngineIDs"

    /// Read-modify-write of the per-profile dictionary must not interleave
    /// across threads, or a concurrent save for another profile is lost.
    private static let lock = NSLock()

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
        lock.lock()
        defer { lock.unlock() }
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
        lock.lock()
        defer { lock.unlock() }
        guard var dictionary = defaults.dictionary(forKey: preferenceKey)
                as? [String: String] else {
            return
        }
        dictionary.removeValue(forKey: profile.id)
        defaults.set(dictionary, forKey: preferenceKey)
    }

    /// Migrates installs that selected a Whisper model before ZenVoice stored
    /// an engine preference, and the pre-unification `whisper` engine ID.
    @discardableResult
    public static func migrateLegacyWhisperSelectionIfNeeded(
        for profile: LanguageProfile,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        if let existing = load(for: profile, defaults: defaults) {
            if existing == EngineIdentifiers.hinglishApex {
                save(
                    EngineIdentifiers.whisperLargeV3Turbo,
                    for: profile,
                    defaults: defaults
                )
                return true
            }
            let canonical = EngineIdentifiers.canonical(existing)
            if canonical != existing {
                save(canonical, for: profile, defaults: defaults)
                return true
            }
            return false
        }
        guard let model = ModelSelectionPreferences.load(defaults: defaults)
        else {
            return false
        }
        save(
            EngineIdentifiers.canonical(model.id),
            for: profile,
            defaults: defaults
        )
        return true
    }
}
