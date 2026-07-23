import Foundation

public final class HistoryPreferences {
    private enum Key {
        static let madeHistoryChoice = "ZenVoice.history.madeChoice"
        static let historyEnabled = "ZenVoice.history.enabled"
        static let hasEverEnabled = "ZenVoice.history.hasEverEnabled"
        static let retainsFailedAudio = "ZenVoice.history.retainsFailedAudio"
        static let retentionDays = "ZenVoice.history.retentionDays"
        static let privateMode = "ZenVoice.history.privateMode"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
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
}
