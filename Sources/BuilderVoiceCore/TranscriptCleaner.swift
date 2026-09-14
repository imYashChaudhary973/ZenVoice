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

    private static let bracketsRegex = try? NSRegularExpression(pattern: #"\s*\[[^\]]+\]\s*"#)
    private static let spacesRegex = try? NSRegularExpression(pattern: #"\s+"#)
    private static let fillerRegex = try? NSRegularExpression(
        pattern: #"(?i)(^|(?<=[.!?]\s))(?:(?:um+|uh+|erm+)[,.\s]+)+"#
    )
    private static let annotationRegex = try? NSRegularExpression(pattern: #"\([^)]*\)"#)

    public func clean(_ transcript: String) -> String {
        var result = transcript
        let range = NSRange(result.startIndex..., in: result)

        if let bracketsRegex = Self.bracketsRegex {
            result = bracketsRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: " "
            )
        }
        if let spacesRegex = Self.spacesRegex {
            let currentRange = NSRange(result.startIndex..., in: result)
            result = spacesRegex.stringByReplacingMatches(
                in: result,
                range: currentRange,
                withTemplate: " "
            )
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if let fillerRegex = Self.fillerRegex {
            let currentRange = NSRange(result.startIndex..., in: result)
            result = fillerRegex.stringByReplacingMatches(
                in: result,
                range: currentRange,
                withTemplate: "$1"
            )
        }

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
        let withoutAnnotations: String
        if let annotationRegex = Self.annotationRegex {
            let range = NSRange(transcript.startIndex..., in: transcript)
            withoutAnnotations = annotationRegex.stringByReplacingMatches(
                in: transcript,
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            withoutAnnotations = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
