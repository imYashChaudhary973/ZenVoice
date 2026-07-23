import Foundation
import ZenVoiceCore

enum HotKeyPreferences {
    private static let preferenceKey = "ZenVoice.dictationHotKey"

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
}
