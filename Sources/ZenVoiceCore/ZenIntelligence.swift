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

/// Enhancement modes for ZenIntelligence.
///
/// ZenIntelligence is an opt-in, local-only post-processing layer that runs
/// after Instant Refine. It can improve formatting and capitalization without
/// changing the meaning of the transcript.
public enum ZenIntelligenceMode: String, Codable, CaseIterable, Sendable {
    case off
    case format
    case contextAware

    public var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .format:
            return "Format"
        case .contextAware:
            return "Context Aware"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            return "Use only Instant Refine; no ZenIntelligence enhancement."
        case .format:
            return "Fix capitalization, number formatting, and light punctuation."
        case .contextAware:
            return "Use surrounding context for smarter formatting and sentence joins."
        }
    }
}

/// Persistent preference for the global ZenIntelligence mode.
public enum ZenIntelligencePreferences {
    public static let modeKey = "ZenVoice.zenIntelligence.mode"

    public static func load(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> ZenIntelligenceMode {
        guard let rawValue = defaults.string(forKey: modeKey),
              let mode = ZenIntelligenceMode(rawValue: rawValue) else {
            return .off
        }
        return mode
    }

    public static func save(
        _ mode: ZenIntelligenceMode,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }
}

/// The result of a ZenIntelligence enhancement pass.
public struct ZenIntelligenceResult: Equatable, Sendable {
    public let text: String
    public let wasRejected: Bool
    public let changeDescription: String

    public init(
        text: String,
        wasRejected: Bool = false,
        changeDescription: String = ""
    ) {
        self.text = text
        self.wasRejected = wasRejected
        self.changeDescription = changeDescription
    }
}

/// On-device AI enhancement for transcripts.
///
/// The current implementation is deterministic. It provides a stable API and a
/// meaning guard so a local model can replace the formatter later without
/// changing the contract. All processing stays on the Mac.
public struct ZenIntelligenceEngine: Sendable {
    public init() {}

    /// Enhances a transcript using the requested mode.
    ///
    /// - Parameters:
    ///   - transcript: the already refined transcript.
    ///   - mode: the enhancement mode; `.off` returns the input unchanged.
    ///   - languageCode: BCP-47 language code used for locale-aware formatting.
    ///   - context: optional surrounding text (up to 500 characters) for
    ///     `.contextAware` mode.
    /// - Returns: a `ZenIntelligenceResult` with `wasRejected` set if the
    ///   meaning guard fired.
    public func enhance(
        _ transcript: String,
        mode: ZenIntelligenceMode,
        languageCode: String = "en",
        context: String? = nil
    ) -> ZenIntelligenceResult {
        guard mode != .off, !transcript.isEmpty else {
            return ZenIntelligenceResult(text: transcript)
        }

        var candidate = transcript
        var changes: [String] = []

        var didJoinWithContext = false
        var sanitizedContext = ""

        if mode == .contextAware {
            sanitizedContext = NextDictationContext.sanitized(context ?? "")
            if !sanitizedContext.isEmpty {
                let joinCount = Self.joinBrokenSentences(
                    in: &candidate,
                    context: sanitizedContext,
                    languageCode: languageCode
                )
                if joinCount > 0 {
                    didJoinWithContext = true
                    changes.append(
                        "joined \(joinCount) sentence fragment(s) with context"
                    )
                }
            }
        }

        if mode == .format || mode == .contextAware {
            let sentenceCount = Self.formatSentences(
                in: &candidate,
                languageCode: languageCode
            )
            if sentenceCount > 0 {
                changes.append("capitalized \(sentenceCount) sentence start(s)")
            }

            let numberCount = Self.formatNumbers(in: &candidate)
            if numberCount > 0 {
                changes.append("formatted \(numberCount) number(s)")
            }

            let whitespaceCount = Self.collapseWhitespace(in: &candidate)
            if whitespaceCount > 0 {
                changes.append("collapsed \(whitespaceCount) whitespace run(s)")
            }
        }

        guard Self.meaningGuard(
            original: transcript,
            candidate: candidate,
            context: didJoinWithContext ? sanitizedContext : nil,
            languageCode: languageCode
        ) else {
            return ZenIntelligenceResult(
                text: transcript,
                wasRejected: true,
                changeDescription:
                    "ZenIntelligence rejected the change to preserve meaning."
            )
        }

        return ZenIntelligenceResult(
            text: candidate,
            changeDescription: changes.joined(separator: ", ")
        )
    }

    // MARK: - Formatting

    /// Capitalize the first letter of each sentence.
    private static func formatSentences(
        in text: inout String,
        languageCode: String
    ) -> Int {
        let sentenceEnders: Set<Character> = languageCode == "zh"
            ? [".", "。", "!", "?", "！", "？"]
            : [".", "!", "?"]
        // Only capitalize the opening word when the text actually contains a
        // sentence boundary. This keeps standalone fragments such as profile
        // names or command phrases untouched while still fixing multi-sentence
        // dictation.
        let hasSentenceEnder = text.contains(where: { sentenceEnders.contains($0) })
        var changed = 0
        var result = ""
        var capitalizeNext = hasSentenceEnder
        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(character.uppercased())
                capitalizeNext = false
                if result.count > 1 || text.first == character {
                    changed += 1
                }
            } else {
                result.append(character)
                if sentenceEnders.contains(character) {
                    capitalizeNext = true
                } else if !character.isWhitespace && !capitalizeNext {
                    // Nothing
                }
            }
        }
        if result != text {
            text = result
        }
        return changed
    }

    /// Convert spoken number forms like "one thousand two hundred" into digits
    /// only when the mapping is unambiguous.
    private static func formatNumbers(in text: inout String) -> Int {
        // A conservative, locale-independent mapping for common unambiguous
        // spoken numbers. This avoids misinterpreting "for" as "four".
        let spokenDigits: [String: String] = [
            "zero": "0",
            "one": "1",
            "two": "2",
            "three": "3",
            "four": "4",
            "five": "5",
            "six": "6",
            "seven": "7",
            "eight": "8",
            "nine": "9",
            "ten": "10"
        ]
        let punctuation = CharacterSet.punctuationCharacters
            .union(.symbols)
        var changed = 0
        var result = ""
        for rawWord in text.split(
            whereSeparator: \.isWhitespace
        ) {
            let word = String(rawWord)
            let lowercased = word.lowercased()
            if let digit = spokenDigits[lowercased] {
                result += digit
                changed += 1
            } else if let digit = spokenDigits[
                word.trimmingCharacters(in: punctuation).lowercased()
            ], !word.isEmpty {
                let leading = word.prefix(
                    while: { punctuation.contains($0.unicodeScalars.first!) }
                )
                let trimmed = word.trimmingCharacters(in: punctuation)
                let trailing = word.suffix(
                    word.count - leading.count - trimmed.count
                )
                result += leading + digit + trailing
                changed += 1
            } else {
                result += word
            }
            result += " "
        }
        result = result.trimmingCharacters(in: .whitespaces)
        if result != text {
            text = result
        }
        return changed
    }

    /// Collapse multiple spaces and fix spacing around punctuation.
    private static func collapseWhitespace(in text: inout String) -> Int {
        let original = text
        text = text
            .replacingOccurrences(
                of: #"[ \t]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s*([,.!?。，？！،؟])\s*"#,
                with: "$1 ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove trailing space before sentence enders.
        text = text.replacingOccurrences(
            of: #"\s+([.!?。，？！،؟])"#,
            with: "$1",
            options: .regularExpression
        )
        return original == text ? 0 : 1
    }

    /// If the transcript starts with a lowercase fragment and the context ends
    /// mid-sentence, join them. This is intentionally conservative: it only
    /// joins when the context strongly suggests continuation.
    private static func joinBrokenSentences(
        in text: inout String,
        context: String,
        languageCode: String
    ) -> Int {
        let trimmedContext = context.trimmingCharacters(in: .whitespaces)
        guard !trimmedContext.isEmpty,
              let first = text.first,
              first.isLowercase else {
            return 0
        }
        let lastContextCharacter = trimmedContext.last
        let sentenceEnders: Set<Character> = languageCode == "zh"
            ? [".", "。", "!", "?", "！", "？"]
            : [".", "!", "?"]
        guard let last = lastContextCharacter,
              !sentenceEnders.contains(last) else {
            return 0
        }
        text = trimmedContext + " " + text
        return 1
    }

    // MARK: - Meaning guard

    /// Rejects candidate changes that add, remove, or alter facts.
    ///
    /// The guard is intentionally simple: it compares token sets and checks for
    /// new numeric or named entities. A future local model will still be bound by
    /// this guard.
    private static func meaningGuard(
        original: String,
        candidate: String,
        context: String? = nil,
        languageCode: String
    ) -> Bool {
        var originalTokens = tokenSet(original, languageCode: languageCode)
        if let context = context, !context.isEmpty {
            originalTokens.formUnion(
                tokenSet(context, languageCode: languageCode)
            )
        }
        let candidateTokens = tokenSet(candidate, languageCode: languageCode)

        // Reject if the candidate invents content: more than a small number of
        // new word tokens that are not formatting-only.
        let newTokens = candidateTokens.subtracting(originalTokens)
        let formattingOnlyTokens: Set<String> = [
            ".", ",", "!", "?", ":", ";", "\n", "\n\n"
        ]
        let significantNewTokens = newTokens.filter {
            !formattingOnlyTokens.contains($0)
                && !isNumberOrPunctuation($0)
        }
        // Allow digits introduced by spoken-digit conversion (already in original
        // as words) and common capitalization changes.
        let unexpectedNewTokens = significantNewTokens.filter { token in
            // A digit is fine if its spoken form was already present.
            let spokenForms = [
                "zero", "one", "two", "three", "four", "five",
                "six", "seven", "eight", "nine", "ten"
            ]
            if let _ = Int(token),
               spokenForms.contains(where: { originalTokens.contains($0) }) {
                return false
            }
            return true
        }
        guard unexpectedNewTokens.count <= 2 else {
            return false
        }

        // Reject if numeric values changed (e.g., "twelve" became "eleven").
        var originalNumbers = numbers(in: original)
        if let context = context, !context.isEmpty {
            originalNumbers.formUnion(numbers(in: context))
        }
        let candidateNumbers = numbers(in: candidate)
        guard originalNumbers == candidateNumbers else {
            return false
        }

        return true
    }

    private static func tokenSet(
        _ text: String,
        languageCode: String
    ) -> Set<String> {
        let lowercased = text.lowercased()
        let separators: CharacterSet = .whitespacesAndNewlines
            .union(.punctuationCharacters)
        let tokens = lowercased.components(separatedBy: separators)
            .filter { !$0.isEmpty }
        return Set(tokens)
    }

    private static func isNumberOrPunctuation(_ token: String) -> Bool {
        token.allSatisfy { $0.isNumber || $0.isPunctuation }
    }

    private static let spokenDigitsByValue: [String: Int] = [
        "zero": 0,
        "one": 1,
        "two": 2,
        "three": 3,
        "four": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8,
        "nine": 9,
        "ten": 10
    ]

    private static func numbers(in text: String) -> Set<Int> {
        var result = Set<Int>()
        let pattern = #"\b\d+\b"#
        if let expression = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = expression.matches(in: text, options: [], range: range)
            for match in matches {
                guard let swiftRange = Range(match.range, in: text),
                      let value = Int(text[swiftRange]) else {
                    continue
                }
                result.insert(value)
            }
        }
        let punctuation = CharacterSet.punctuationCharacters
            .union(.symbols)
        for rawWord in text.split(whereSeparator: \.isWhitespace) {
            let word = String(rawWord)
                .trimmingCharacters(in: punctuation)
                .lowercased()
            if let value = spokenDigitsByValue[word] {
                result.insert(value)
            }
        }
        return result
    }
}
