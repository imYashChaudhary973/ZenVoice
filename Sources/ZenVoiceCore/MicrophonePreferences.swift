import Foundation

public enum MicrophonePreferences {
    public static let preferenceKey = "ZenVoice.selectedMicrophoneUID"

    public static func selectedDeviceUID(
        defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: preferenceKey)
    }

    public static func save(
        deviceUID: String?,
        defaults: UserDefaults = .standard
    ) {
        if let deviceUID {
            defaults.set(deviceUID, forKey: preferenceKey)
        } else {
            defaults.removeObject(forKey: preferenceKey)
        }
    }
}
