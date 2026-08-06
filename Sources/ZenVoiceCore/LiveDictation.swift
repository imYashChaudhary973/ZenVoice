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

import Foundation

public enum LiveDictationPreferences {
    public static let previewKey = "ZenVoice.livePreviewEnabled"
    public static let commitOnPauseKey = "ZenVoice.commitOnPauseEnabled"

    /// Off unless the user asks for it.
    ///
    /// Preview decodes every pause-delimited fragment with the selected model,
    /// and the finished recording is then decoded again in one pass — the two
    /// share a serial queue, so the accurate decode cannot even begin until the
    /// last preview drains. That is twice the compute and twice the battery,
    /// spent on fragments that are measurably *less* accurate than the whole
    /// utterance: words either side of a cut lose their context, which is the
    /// gap ``DictationCompletionStrategy`` exists to describe and
    /// ZenVoiceAccuracyChecks exists to keep visible.
    ///
    /// Nothing depends on it being on. Crash recovery is served by the recovery
    /// audio, which the recorder writes before it ever consults this preference.
    public static func isPreviewEnabled(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        defaults.object(forKey: previewKey) == nil
            ? false
            : defaults.bool(forKey: previewKey)
    }

    public static func isCommitOnPauseEnabled(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        defaults.bool(forKey: commitOnPauseKey)
    }

    public static func setPreviewEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(enabled, forKey: previewKey)
        if !enabled {
            defaults.set(false, forKey: commitOnPauseKey)
        }
    }

    public static func setCommitOnPauseEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(enabled, forKey: commitOnPauseKey)
        if enabled {
            defaults.set(true, forKey: previewKey)
        }
    }
}

/// How a finished dictation turns into the text handed to the target app.
public enum DictationCompletionStrategy: Equatable, Sendable {
    /// Decode the complete recording in a single pass.
    ///
    /// Whisper is markedly more accurate when it hears a whole utterance than
    /// when it is fed the fragments the pause detector cut, because words on
    /// either side of a cut lose their context. This is the accurate path and
    /// the default.
    case wholeRecording

    /// Concatenate the preview fragments and append whatever followed the last
    /// one.
    ///
    /// Only correct when preview text has already been inserted into the target
    /// app: at that point the inserted text is a fact on screen, and replacing
    /// it wholesale is a separate problem from transcribing accurately.
    case segments

    public static func resolve(
        usesLivePreview: Bool,
        hasInsertedPreviewText: Bool
    ) -> DictationCompletionStrategy {
        usesLivePreview && hasInsertedPreviewText ? .segments : .wholeRecording
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
