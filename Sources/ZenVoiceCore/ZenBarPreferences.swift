import Foundation

public enum ZenBarPreferences {
    public static let showsAtAllTimesKey =
        "ZenVoice.zenBar.showsAtAllTimes"

    public static func showsAtAllTimes(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: showsAtAllTimesKey) == nil
            ? true
            : defaults.bool(forKey: showsAtAllTimesKey)
    }

    public static func setShowsAtAllTimes(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: showsAtAllTimesKey)
    }
}
