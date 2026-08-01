import Combine
import Foundation
import ZenVoiceCore

/// The microphone level, published on its own.
///
/// Combine invalidates every view observing an `ObservableObject` whenever any
/// of its `@Published` properties changes, regardless of which one the view
/// actually read. The level changes about fifteen times a second while
/// recording, so keeping it on ``AppState`` re-evaluated the entire ZenBar —
/// brand mark, keycaps, buttons and all — at that rate to move a few bars.
/// Split out, a level update repaints the waveform and nothing else.
@MainActor
final class AudioLevelModel: ObservableObject {
    @Published private(set) var level: Double = 0

    func update(_ value: Double) {
        level = max(0, min(1, value))
    }

    func reset() {
        level = 0
    }
}

@MainActor
final class AppState: ObservableObject {
    private static let statusMessagePreferenceKey =
        "ZenVoice.showsStatusMessage"

    enum Phase: Equatable {
        case idle
        case listening
        case transcribing
        case inserting
        case success
        case error(String)

        var label: String {
            switch self {
            case .idle:
                return "Ready"
            case .listening:
                return "Listening"
            case .transcribing:
                return "Transcribing locally"
            case .inserting:
                return "Inserting text"
            case .success:
                return "Inserted"
            case .error(let message):
                return message
            }
        }
    }

    struct InsertionSummary: Equatable {
        let wordCount: Int
        let wordsPerMinute: Int
    }

    @Published var phase: Phase = .idle
    /// Deliberately not `@Published` — see ``AudioLevelModel``.
    let audioLevel = AudioLevelModel()
    @Published private(set) var showsZenVoiceAtAllTimes: Bool
    @Published var showsStatusMessage: Bool
    @Published var lastTranscript = ""
    @Published private(set) var lastInsertionSummary: InsertionSummary?
    /// Set alongside ``lastTranscript`` and describing the same text, so a
    /// copy or re-paste of that transcript carries the same caution. Nil
    /// whenever the last decode was trusted.
    @Published private(set) var lastDecodeWarning: String?
    @Published var languageProfile: LanguageProfile
    @Published var liveTranscriptPreview = ""

    init(defaults: UserDefaults = .standard) {
        languageProfile = LanguagePreferences.load(defaults: defaults)
        showsZenVoiceAtAllTimes =
            ZenBarPreferences.showsAtAllTimes(defaults: defaults)
        if defaults.object(forKey: Self.statusMessagePreferenceKey) == nil {
            showsStatusMessage = true
        } else {
            showsStatusMessage = defaults.bool(
                forKey: Self.statusMessagePreferenceKey
            )
        }
    }

    var isBusy: Bool {
        switch phase {
        case .transcribing, .inserting:
            return true
        default:
            return false
        }
    }

    func resetAudioSamples() {
        audioLevel.reset()
    }

    func appendAudioLevel(_ level: Double) {
        audioLevel.update(level)
    }

    func recordSuccessfulDictation(
        transcript: String,
        durationSeconds: TimeInterval,
        runawayWordsCut: Int = 0
    ) {
        lastTranscript = transcript
        lastDecodeWarning =
            runawayWordsCut >= TranscriptRepetition.wordsCutBeforeDistrust
            ? "the decoder looped — check the inserted text"
            : nil
        let wordCount = transcript.split(whereSeparator: \.isWhitespace).count
        guard wordCount > 0, durationSeconds > 0 else {
            lastInsertionSummary = nil
            return
        }
        lastInsertionSummary = InsertionSummary(
            wordCount: wordCount,
            wordsPerMinute: max(
                1,
                Int(
                    (Double(wordCount) * 60 / durationSeconds)
                        .rounded()
                )
            )
        )
    }

    func toggleStatusMessage(defaults: UserDefaults = .standard) {
        showsStatusMessage.toggle()
        defaults.set(
            showsStatusMessage,
            forKey: Self.statusMessagePreferenceKey
        )
    }

    func setShowsZenVoiceAtAllTimes(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        ZenBarPreferences.setShowsAtAllTimes(
            enabled,
            defaults: defaults
        )
        showsZenVoiceAtAllTimes = enabled
    }
}
