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

enum HotKeyPreferences {
    private static let preferenceKey = "ZenVoice.dictationHotKey"
    private static let pasteLastPreferenceKey = "ZenVoice.pasteLastHotKey"
    private static let privateModePreferenceKey = "ZenVoice.privateModeHotKey"
    private static let holdEnabledPreferenceKey = "ZenVoice.holdToDictate.enabled"
    private static let holdKeyPreferenceKey = "ZenVoice.holdToDictate.key"

    /// Shortcuts that had to be replaced while loading, as "before → after"
    /// descriptions, so the app can say what changed instead of leaving the
    /// user to discover it by pressing a key that no longer answers.
    nonisolated(unsafe) private(set) static var replacedShortcuts: [String] = []

    static func load(defaults: UserDefaults = .standard) -> HotKeyConfiguration {
        load(
            key: preferenceKey,
            fallback: .dictationDefault,
            defaults: defaults
        )
    }

    static func save(
        _ configuration: HotKeyConfiguration,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        defaults.set(data, forKey: preferenceKey)
    }

    static func loadPasteLast(
        defaults: UserDefaults = .standard
    ) -> HotKeyConfiguration {
        load(
            key: pasteLastPreferenceKey,
            fallback: .pasteLastDefault,
            defaults: defaults
        )
    }

    static func savePasteLast(
        _ configuration: HotKeyConfiguration,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        defaults.set(data, forKey: pasteLastPreferenceKey)
    }

    static func loadPrivateMode(
        defaults: UserDefaults = .standard
    ) -> HotKeyConfiguration {
        load(
            key: privateModePreferenceKey,
            fallback: .privateModeDefault,
            defaults: defaults
        )
    }

    static func savePrivateMode(
        _ configuration: HotKeyConfiguration,
        defaults: UserDefaults = .standard
    ) {
        save(configuration, key: privateModePreferenceKey, defaults: defaults)
    }

    static func isHoldToDictateEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: holdEnabledPreferenceKey)
    }

    static func saveHoldToDictateEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: holdEnabledPreferenceKey)
    }

    static func loadHoldKey(
        defaults: UserDefaults = .standard
    ) -> HoldKeyChoice {
        guard let rawValue = defaults.string(forKey: holdKeyPreferenceKey),
              let choice = HoldKeyChoice(rawValue: rawValue) else {
            return .default
        }
        return choice
    }

    static func saveHoldKey(
        _ choice: HoldKeyChoice,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(choice.rawValue, forKey: holdKeyPreferenceKey)
    }

    private static func load(
        key: String,
        fallback: HotKeyConfiguration,
        defaults: UserDefaults
    ) -> HotKeyConfiguration {
        guard let data = defaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(
                HotKeyConfiguration.self,
                from: data
              ) else {
            return fallback
        }

        if configuration.isValid {
            return configuration
        }

        // Returning the fallback without writing it back leaves the stored
        // preference — and so the settings screen — showing a shortcut the app
        // is not listening for. That is how a working shortcut turns into a
        // dead key with nothing on screen to explain it. Persist the
        // substitution and record it so the app can say what changed.
        save(fallback, key: key, defaults: defaults)
        replacedShortcuts.append(
            "\(configuration.displayName) → \(fallback.displayName)"
        )
        return fallback
    }

    private static func save(
        _ configuration: HotKeyConfiguration,
        key: String,
        defaults: UserDefaults
    ) {
        guard configuration.isValid,
              let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
