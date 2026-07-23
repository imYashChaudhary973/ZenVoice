import Foundation

public enum LiveDictationPreferences {
    public static let previewKey = "ZenVoice.livePreviewEnabled"
    public static let commitOnPauseKey = "ZenVoice.commitOnPauseEnabled"

    public static func isPreviewEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: previewKey) == nil
            ? true
            : defaults.bool(forKey: previewKey)
    }

    public static func isCommitOnPauseEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: commitOnPauseKey)
    }

    public static func setPreviewEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: previewKey)
        if !enabled {
            defaults.set(false, forKey: commitOnPauseKey)
        }
    }

    public static func setCommitOnPauseEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: commitOnPauseKey)
        if enabled {
            defaults.set(true, forKey: previewKey)
        }
    }
}

public enum StableTranscriptComposer {
    public static func appending(
        _ phrase: String,
        to transcript: String
    ) -> String {
        let phrase = phrase.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !phrase.isEmpty else {
            return transcript
        }
        let transcript = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !transcript.isEmpty else {
            return phrase
        }
        return transcript + " " + phrase
    }
}

public enum StablePauseDetector {
    public static func isStable(
        segmentStart: Int,
        totalSamples: Int,
        lastSpeechSample: Int,
        sampleRate: Double = 16_000,
        minimumSpeechDuration: TimeInterval = 0.45,
        requiredSilenceDuration: TimeInterval = 0.70
    ) -> Bool {
        let start = max(0, min(segmentStart, totalSamples))
        let minimumSpeechSamples =
            Int(sampleRate * minimumSpeechDuration)
        let requiredSilenceSamples =
            Int(sampleRate * requiredSilenceDuration)
        return lastSpeechSample > start
            && lastSpeechSample - start >= minimumSpeechSamples
            && totalSamples - lastSpeechSample
                >= requiredSilenceSamples
    }
}
