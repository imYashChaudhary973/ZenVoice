import Foundation

public enum InstantRefineMode: String, Codable, CaseIterable, Sendable {
    case off
    case clean
    case agentPrompt
    case localModel

    public var displayName: String {
        switch self {
        case .off:
            "Off"
        case .clean:
            "Clean"
        case .agentPrompt:
            "Agent Prompt"
        case .localModel:
            "Local Model"
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
        case .localModel:
            "Use the selected verified local model with automatic safe fallback."
        }
    }

    /// The modes a user can actually choose.
    ///
    /// `localModel` is withheld. Measured against the deterministic modes it
    /// improved accuracy by 0.0 points on every configuration tried, while
    /// asking for a 1.1 GB download and adding time to each dictation — the
    /// model is too small to tell a filler word from a meaningful one, which
    /// no amount of plumbing fixes. Offering it would be charging the user a
    /// gigabyte and a wait for text identical to what Clean produces instantly.
    ///
    /// The runtime, guard and harness stage are all still here, because the
    /// architecture is sound and model-independent. What is missing is a model
    /// good enough to use it. A candidate earns this back by clearing the bar
    /// in `ZenVoiceAccuracyChecks` under `ZENVOICE_REFINE_STRICT=1`: beat Clean
    /// by at least half a point on disfluent speech, leave clean speech
    /// untouched, and never alter a negation or a quantity. That is a command
    /// to run, not a judgement to make.
    ///
    /// See docs/REFINEMENT_RD.md section 8.6.
    public static var userSelectable: [InstantRefineMode] {
        allCases.filter { $0 != .localModel }
    }
}

public enum InstantRefinePreferences {
    public static let preferenceKey = "ZenVoice.instantRefine.mode"

    public static func load(
        defaults: UserDefaults = .standard
    ) -> InstantRefineMode {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let mode = InstantRefineMode(rawValue: rawValue) else {
            return .clean
        }
        // Someone who chose the local model before it was withheld should not
        // be left on a mode the app no longer offers, silently paying its cost
        // for no measured benefit. Clean is what it was falling back to
        // anyway, so this changes their results not at all — only their
        // latency, downward.
        guard InstantRefineMode.userSelectable.contains(mode) else {
            return .clean
        }
        return mode
    }

    public static func save(
        _ mode: InstantRefineMode,
        defaults: UserDefaults = .standard
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
                #"(?i)\b(a|an|the)\s+([\p{L}\p{N}_'-]+(?:\s+[\p{L}\p{N}_'-]+){0,3})\s*(?:,|—|-)\s*(?:no\s*,?\s*wait|wait|sorry|i mean|rather)\s*[,—-]?\s*(?:a|an|the)\s+"#,
            template: "$1 "
        )
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?i)\b([\p{L}\p{N}_'-]+)\s*(?:,|—|-)\s*(?:no\s*,?\s*wait|sorry|i mean|rather)\s*[,—-]?\s*([\p{L}\p{N}_'-]+)\b"#,
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
                #"(?i)(?<![\p{L}\p{N}_])(?:um+|uh+|erm+|ah+|hm+|mhm+)(?:\s*,\s*|\s+|$)"#,
            template: ""
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
                #"(?i)\b((?:[\p{L}\p{N}_'-]+[ \t]+){2,4})(?:\1)+"#,
            template: "$1"
        )
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?i)\b([\p{L}\p{N}_'-]{2,})\b(?:[\s,]+\1\b)+"#,
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
