import Combine
import Foundation
import ZenVoiceCore

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

    @Published var phase: Phase = .idle
    @Published var audioSamples = Array(repeating: 0.0, count: 13)
    @Published var isZenBarVisible = true
    @Published var showsStatusMessage: Bool
    @Published var lastTranscript = ""
    @Published var languageProfile: LanguageProfile
    @Published var liveTranscriptPreview = ""

    init(defaults: UserDefaults = .standard) {
        languageProfile = LanguagePreferences.load(defaults: defaults)
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
        audioSamples = Array(repeating: 0, count: audioSamples.count)
    }

    func appendAudioLevel(_ level: Double) {
        var samples = audioSamples
        samples.removeFirst()
        samples.append(max(0, min(1, level)))
        audioSamples = samples
    }

    func toggleStatusMessage(defaults: UserDefaults = .standard) {
        showsStatusMessage.toggle()
        defaults.set(
            showsStatusMessage,
            forKey: Self.statusMessagePreferenceKey
        )
    }
}
