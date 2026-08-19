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
        /// The cloud review panel is open and waiting for an answer.
        ///
        /// Distinct from `.transcribing` because the app is not working — it
        /// is waiting on the user, behind a panel that deliberately does not
        /// take focus. Sharing `.transcribing` meant the ZenBar claimed to be
        /// decoding while nothing was happening, and `isBusy` locked the
        /// dictation shortcut with no visible cause.
        case awaitingCloudReview
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
            case .awaitingCloudReview:
                return "Waiting for your cloud review"
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
    @Published var mode: ZenBarMode = .dictation
    @Published var agenticGoalTitle: String?
    @Published var agenticStatusEvent: GoalStatusEvent?
    @Published var isAgenticGoalActive = false

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
