import Foundation
import ZenVoiceCore

enum HotKeyPreferences {
    private static let preferenceKey = "ZenVoice.dictationHotKey"
    private static let pasteLastPreferenceKey = "ZenVoice.pasteLastHotKey"
    private static let privateModePreferenceKey = "ZenVoice.privateModeHotKey"
    private static let holdEnabledPreferenceKey = "ZenVoice.holdToDictate.enabled"
    private static let holdKeyPreferenceKey = "ZenVoice.holdToDictate.key"

    static func load(defaults: UserDefaults = .standard) -> HotKeyConfiguration {
        guard let data = defaults.data(forKey: preferenceKey),
              let configuration = try? JSONDecoder().decode(
                HotKeyConfiguration.self,
                from: data
              ),
              configuration.isValid else {
            return .dictationDefault
        }
        return configuration
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
        guard let data = defaults.data(forKey: pasteLastPreferenceKey),
              let configuration = try? JSONDecoder().decode(
                HotKeyConfiguration.self,
                from: data
              ),
              configuration.isValid else {
            return .pasteLastDefault
        }
        return configuration
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
              ),
              configuration.isValid else {
            return fallback
        }
        return configuration
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
