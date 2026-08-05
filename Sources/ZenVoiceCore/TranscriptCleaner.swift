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

public struct TranscriptCleaner {
    public init() {}

    /// Whole-transcript outputs Whisper produces from silence or room noise
    /// rather than speech.
    ///
    /// Deliberately short. "Thank you." is a *plausible* thing to dictate on
    /// its own, so it is not here — dropping a real one-word dictation is worse
    /// than letting a rare artifact through. Everything listed is implausible
    /// as a complete dictation.
    private static let nonSpeechFragments: Set<String> = [
        "you",
        "thanks for watching",
        "thank you for watching",
        "thanks for watching!",
        "subtitles by the amara.org community"
    ]

    public func clean(_ transcript: String) -> String {
        var result = transcript
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fillerPattern = #"(?i)(^|(?<=[.!?]\s))(?:(?:um+|uh+|erm+)[,.\s]+)+"#
        result = result.replacingOccurrences(
            of: fillerPattern,
            with: "$1",
            options: .regularExpression
        )

        guard !isNonSpeech(result) else {
            return ""
        }

        guard !result.isEmpty else {
            return ""
        }

        let first = result.prefix(1).uppercased()
        return first + result.dropFirst()
    }

    /// Whether the transcript is a non-speech annotation rather than words the
    /// user said.
    private func isNonSpeech(_ transcript: String) -> Bool {
        // Parenthesised sound descriptions — "(static)", "(wind blowing)" —
        // are only treated as non-speech when nothing else survives removing
        // them. Stripping them inline would silently eat dictated asides like
        // "the total (before tax) is fifty", and a user's own words matter more
        // than a rare stray annotation.
        let withoutAnnotations = transcript
            .replacingOccurrences(
                of: #"\([^)]*\)"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if withoutAnnotations.isEmpty, !transcript.isEmpty {
            return true
        }

        let normalized = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        if Self.nonSpeechFragments.contains(normalized) {
            return true
        }
        // Also match with trailing punctuation removed, so "You." and "you"
        // are treated alike.
        let stripped = normalized.trimmingCharacters(
            in: CharacterSet(charactersIn: ".!?,")
        )
        return Self.nonSpeechFragments.contains(stripped)
    }
}
