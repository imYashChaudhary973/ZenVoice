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

public enum InstantRefineMode: String, Codable, CaseIterable, Sendable {
    case off
    case clean
    case agentPrompt

    public var displayName: String {
        switch self {
        case .off:
            "Off"
        case .clean:
            "Clean"
        case .agentPrompt:
            "Agent Prompt"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            "Keep the local Whisper transcript unchanged."
        case .clean:
            "Remove fillers, repeated words, and clear spoken restarts."
        case .agentPrompt:
            "Clean the transcript and honor explicit layout commands."
        }
    }

}

public enum InstantRefinePreferences {
    public static let preferenceKey = "ZenVoice.instantRefine.mode"

    public static func load(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> InstantRefineMode {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let mode = InstantRefineMode(rawValue: rawValue) else {
            return .clean
        }
        return mode
    }

    public static func save(
        _ mode: InstantRefineMode,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(mode.rawValue, forKey: preferenceKey)
    }
}

public struct InstantRefineResult: Equatable, Sendable {
    public let text: String
    public let correctionCount: Int
    public let wasRejected: Bool

    public init(
        text: String,
        correctionCount: Int,
        wasRejected: Bool = false
    ) {
        self.text = text
        self.correctionCount = correctionCount
        self.wasRejected = wasRejected
    }
}

public struct InstantRefineEngine: Sendable {
    public init() {}

    public func refine(
        _ transcript: String,
        mode: InstantRefineMode
    ) -> InstantRefineResult {
        guard mode != .off, !transcript.isEmpty else {
            return InstantRefineResult(
                text: transcript,
                correctionCount: 0
            )
        }

        var candidate = transcript
        var correctionCount = 0

        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?i)\b(a|an|the)\s+([\p{L}\p{M}\p{N}_'-]+(?:\s+[\p{L}\p{M}\p{N}_'-]+){0,3})\s*(?:,|—|-)\s*(?:no\s*,?\s*wait|wait|sorry|i mean|rather)\s*[,—-]?\s*(?:a|an|the)\s+"#,
            template: "$1 "
        )
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?i)\b([\p{L}\p{M}\p{N}_'-]+)\s*(?:,|—|-)\s*(?:no\s*,?\s*wait|sorry|i mean|rather)\s*[,—-]?\s*([\p{L}\p{M}\p{N}_'-]+)\b"#,
            template: "$2"
        )
        // Filler stems. "ah" and "hm" were measured escaping in real Whisper
        // output — the harness caught "Do not merge the branch. Ah, until the
        // tests pass."
        //
        // "er" is deliberately absent despite being a filler: it also spells a
        // real verb, and "err on the side of caution" would lose its verb. The
        // remaining stems have no English homograph.
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?i)(?<![\p{L}\p{M}\p{N}_])(?:um+|uh+|erm+|ah+|hm+|mhm+)(?:\s*,\s*|\s+|$)"#,
            template: ""
        )
        // Devanagari hesitation sounds, the counterparts of um and uh:
        // उम्म, अम्म, अअअ, हम्म, and their elongated forms. Measured as the
        // single most-removed tokens in a Hindi disfluency corpus.
        //
        // A word merely beginning with these letters is safe — अमेरिका has a
        // vowel sign where a filler has a doubled म — and the trailing
        // boundary means the filler must stand alone as its own word.
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?<![\p{L}\p{M}\p{N}_])(?:[उअहम]म्?म+|अ{2,}|ऐ{2,})(?:\s*[,।]\s*|\s+|$)"#,
            template: ""
        )
        // "वो क्या कहते हैं" — literally "what's it called" — is the Hindi
        // speaker stalling for a word, exactly like an English "you know".
        // A fixed phrase rather than a single token, so it is matched whole.
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"\s*,?\s*वो(?:ह)?\s+क्या\s+कहते\s+हैं\s*,?\s*"#,
            template: " "
        )
        // मतलब and यानी mean "meaning" / "that is", and like "I mean" they are
        // filler only when the speaker's own pause brackets them.
        correctionCount += replace(
            in: &candidate,
            pattern: #"\s*,\s*(?:मतलब|यानी|यानि)\s*,\s*"#,
            template: " "
        )
        // Discourse markers, but only when the speaker's own pauses bracket
        // them in commas. "like" and "you know" are the two commonest fillers
        // in spoken English and both are ordinary words elsewhere — deleting
        // "like" wherever it appears would eat "I like it" and "like this".
        // The comma bracketing is what distinguishes the filler use, and it is
        // how Whisper actually punctuates them.
        //
        // Runs after the restart patterns above so that "a login page, I mean,
        // a sign-up page" is resolved as a correction first.
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?i)\s*,\s*(?:you know|i guess|sort of|kind of)\s*,\s*"#,
            template: " "
        )
        correctionCount += replace(
            in: &candidate,
            pattern: #"(?i)\s*,\s*like\s*,\s*"#,
            template: " "
        )
        // Phrase-level restarts — "we should we should probably revert".
        //
        // A speaker who loses the thread repeats the run-up, not just the last
        // word, and the single-word rule below cannot see that: in "we should
        // we should" no two *adjacent* words are equal. Whisper only appeared
        // to clean these up on its own; with the decode pinned they survive to
        // here, which is how the gap was found.
        //
        // Bounded at two to four words, and the separator is spaces and tabs
        // rather than \s so a repeat cannot be matched across a line break.
        // Punctuation between the halves also blocks it, which is what keeps
        // deliberate repeats like "New York, New York" and "come on, come on"
        // intact — the comma is the speaker marking it as intentional.
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?i)\b((?:[\p{L}\p{M}\p{N}_'-]+[ \t]+){2,4})(?:\1)+"#,
            template: "$1"
        )
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?i)\b([\p{L}\p{M}\p{N}_'-]{2,})\b(?:[\s,]+\1\b)+"#,
            template: "$1"
        )

        if mode == .agentPrompt {
            correctionCount += replace(
                in: &candidate,
                pattern: #"(?i)\s*\bnew paragraph\b\s*"#,
                template: "\n\n"
            )
            correctionCount += replace(
                in: &candidate,
                pattern: #"(?i)\s*\bnew line\b\s*"#,
                template: "\n"
            )
        }

        correctionCount += replace(
            in: &candidate,
            pattern: #"[ \t]+"#,
            template: " "
        )
        correctionCount += replace(
            in: &candidate,
            pattern: #"\s+([,.!?])"#,
            template: "$1"
        )
        correctionCount += replace(
            in: &candidate,
            pattern: #"\n[ \t]+"#,
            template: "\n"
        )
        correctionCount += replace(
            in: &candidate,
            pattern: #"\n{3,}"#,
            template: "\n\n"
        )

        candidate = candidate.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let firstLetterIndex = candidate.firstIndex(where: \.isLetter) {
            candidate.replaceSubrange(
                firstLetterIndex...firstLetterIndex,
                with: candidate[firstLetterIndex].uppercased()
            )
        }
        // Deleting a filler that opened a sentence leaves the next word
        // lowercased — "… the branch. Ah, until the tests pass." becomes
        // "… the branch. until the tests pass." Fixing the case is part of
        // finishing the edit, not a separate feature.
        //
        // Case never affects the meaning guard, which lowercases before
        // comparing, so this cannot cause a rejection.
        let recased = capitalizingSentenceStarts(candidate)
        if recased != candidate {
            candidate = recased
            correctionCount += 1
        }
        guard meaningIsPreserved(
            original: transcript,
            candidate: candidate
        ) else {
            return InstantRefineResult(
                text: transcript,
                correctionCount: 0,
                wasRejected: true
            )
        }

        return InstantRefineResult(
            text: candidate,
            correctionCount: candidate == transcript ? 0 : correctionCount
        )
    }

    /// Uppercases the first letter of each sentence.
    ///
    /// A digit immediately after the stop cancels it, so "3.5 seconds" and
    /// version numbers are left alone. Abbreviations like "e.g. foo" are still
    /// treated as a sentence break — accepting that over-capitalization is the
    /// cost of not carrying an abbreviation dictionary, and it is a
    /// presentation slip rather than a meaning change.
    private func capitalizingSentenceStarts(_ text: String) -> String {
        var characters = Array(text)
        var awaitingStart = false
        for index in characters.indices {
            let character = characters[index]
            if character == "." || character == "!" || character == "?" {
                awaitingStart = true
            } else if awaitingStart, character.isLetter {
                characters[index] = Character(
                    character.uppercased()
                )
                awaitingStart = false
            } else if !character.isWhitespace,
                      character != "\"",
                      character != "'" {
                awaitingStart = false
            }
        }
        return String(characters)
    }

    private func replace(
        in text: inout String,
        pattern: String,
        template: String
    ) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }
        let range = NSRange(text.startIndex..., in: text)
        let matchCount = expression.numberOfMatches(
            in: text,
            range: range
        )
        guard matchCount > 0 else {
            return 0
        }
        let replaced = expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: template
        )
        guard replaced != text else {
            return 0
        }
        text = replaced
        return matchCount
    }

    private func meaningIsPreserved(
        original: String,
        candidate: String
    ) -> Bool {
        guard !candidate.isEmpty else {
            return false
        }
        let originalTokens = tokens(in: original)
        let candidateTokens = tokens(in: candidate)
        guard originalTokens.isEmpty || !candidateTokens.isEmpty else {
            return false
        }
        guard originalTokens.count < 5
                || candidateTokens.count * 2 >= originalTokens.count else {
            return false
        }

        let originalVocabulary = Set(originalTokens)
        return candidateTokens.allSatisfy(originalVocabulary.contains)
    }

    private func tokens(in text: String) -> [String] {
        text.lowercased()
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { !$0.isEmpty }
    }
}
