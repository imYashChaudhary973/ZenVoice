import Foundation

public enum OnboardingPreferences {
    public static let completionKey =
        "ZenVoice.onboarding.completed.v1"

    public static func shouldPresent(
        defaults: UserDefaults = .standard
    ) -> Bool {
        if defaults.object(forKey: completionKey) != nil {
            return !defaults.bool(forKey: completionKey)
        }

        let existingInstallKeys = [
            ModelSelectionPreferences.preferenceKey,
            LanguagePreferences.preferenceKey,
            InstantRefinePreferences.preferenceKey,
            "ZenVoice.history.hasEverEnabled",
            "ZenVoice.dictationHotKey"
        ]
        let isExistingInstall = existingInstallKeys.contains {
            defaults.object(forKey: $0) != nil
        }
        if isExistingInstall {
            defaults.set(true, forKey: completionKey)
            return false
        }
        return true
    }

    public static func complete(
        defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: completionKey)
    }

    public static func reset(
        defaults: UserDefaults = .standard
    ) {
        defaults.set(false, forKey: completionKey)
    }
}
