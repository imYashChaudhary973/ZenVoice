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
import ZenVoiceCore

public final class LocalLearningPreferences {
    private enum Key {
        static let appliesCorrectionRules =
            "ZenVoice.learning.appliesCorrectionRules"
        static let analyzesHistory =
            "ZenVoice.learning.analyzesHistory"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = RuntimeIdentity.userDefaults()) {
        self.defaults = defaults
    }

    public var appliesCorrectionRules: Bool {
        get {
            guard defaults.object(
                forKey: Key.appliesCorrectionRules
            ) != nil else {
                return true
            }
            return defaults.bool(
                forKey: Key.appliesCorrectionRules
            )
        }
        set {
            defaults.set(
                newValue,
                forKey: Key.appliesCorrectionRules
            )
        }
    }

    public var analyzesHistory: Bool {
        get {
            guard defaults.object(
                forKey: Key.analyzesHistory
            ) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.analyzesHistory)
        }
        set {
            defaults.set(newValue, forKey: Key.analyzesHistory)
        }
    }
}

public enum CorrectionLanguageScope:
    String, CaseIterable, Identifiable, Sendable
{
    case all
    case hinglish

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:
            return "All languages"
        case .hinglish:
            return "Hinglish only"
        }
    }

    public func applies(to activeScope: CorrectionLanguageScope) -> Bool {
        self == .all || self == activeScope
    }
}

public struct CorrectionRule: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let source: String
    public let replacement: String
    public let languageScope: CorrectionLanguageScope
    public let usageCount: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        source: String,
        replacement: String,
        languageScope: CorrectionLanguageScope = .all,
        usageCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.replacement = replacement
        self.languageScope = languageScope
        self.usageCount = usageCount
        self.createdAt = createdAt
    }
}

public struct CorrectionSuggestion: Identifiable, Equatable, Sendable {
    public var id: String {
        "\(ruleID.uuidString)|\(source.lowercased())"
    }

    public let ruleID: UUID
    public let source: String
    public let replacement: String
    public let languageScope: CorrectionLanguageScope

    public init(
        ruleID: UUID,
        source: String,
        replacement: String,
        languageScope: CorrectionLanguageScope
    ) {
        self.ruleID = ruleID
        self.source = source
        self.replacement = replacement
        self.languageScope = languageScope
    }
}

public struct CorrectionUsage: Equatable, Sendable {
    public let ruleID: UUID
    public let count: Int

    public init(ruleID: UUID, count: Int) {
        self.ruleID = ruleID
        self.count = count
    }
}

public struct CorrectionApplication: Equatable, Sendable {
    public let text: String
    public let usages: [CorrectionUsage]

    public var correctionCount: Int {
        usages.reduce(0) { $0 + $1.count }
    }
}

public enum TranscriptCorrectionEngine {
    public static func apply(
        _ text: String,
        rules: [CorrectionRule],
        activeScope: CorrectionLanguageScope = .all
    ) -> CorrectionApplication {
        let applicableRules = rules
            .filter { $0.languageScope.applies(to: activeScope) }
            .sorted {
                $0.languageScope == activeScope
                    && $1.languageScope != activeScope
            }
        let normalizedRules = Dictionary(
            applicableRules.map { ($0.source.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let alternatives = normalizedRules.keys
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
        guard !alternatives.isEmpty,
              let expression = try? NSRegularExpression(
                pattern:
                    #"(?i)(?<![\p{L}\p{N}_])("#
                    + alternatives.joined(separator: "|")
                    + #")(?![\p{L}\p{N}_])"#
              ) else {
            return applyFuzzyMatches(
                to: text,
                rules: applicableRules,
                existingCounts: [:]
            )
        }

        let source = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        var corrected = text
        var counts: [UUID: Int] = [:]
        for match in matches.reversed() {
            let matchedText = source.substring(with: match.range)
            guard let rule = normalizedRules[matchedText.lowercased()],
                  let range = Range(match.range, in: corrected) else {
                continue
            }
            corrected.replaceSubrange(range, with: rule.replacement)
            counts[rule.id, default: 0] += 1
        }
        return applyFuzzyMatches(
            to: corrected,
            rules: applicableRules,
            existingCounts: counts
        )
    }

    public static func suggestions(
        in text: String,
        rules: [CorrectionRule],
        activeScope: CorrectionLanguageScope = .all
    ) -> [CorrectionSuggestion] {
        let applicableRules = Array(
            rules.filter {
                $0.languageScope.applies(to: activeScope)
                    && isSingleLatinWord($0.source)
                    && isSingleLatinWord($0.replacement)
                    && $0.source.count >= 5
                    && $0.replacement.count >= 5
            }
            .prefix(100)
        )
        let protectedTerms = Set(
            applicableRules.flatMap {
                [$0.source.lowercased(), $0.replacement.lowercased()]
            }
        )
        return latinWordMatches(in: text).compactMap { match in
            let token = match.text
            let normalized = token.lowercased()
            guard !protectedTerms.contains(normalized) else {
                return nil
            }
            let ranked = applicableRules.compactMap { rule
                -> (CorrectionRule, Int)? in
                let sourceDistance = editDistance(
                    normalized,
                    rule.source.lowercased()
                )
                let replacementDistance = editDistance(
                    normalized,
                    rule.replacement.lowercased()
                )
                let score = min(sourceDistance, replacementDistance)
                let limit = max(
                    normalized.count,
                    rule.replacement.count
                ) >= 8 ? 3 : 2
                return score <= limit ? (rule, score) : nil
            }
            .sorted { $0.1 < $1.1 }
            guard let best = ranked.first,
                  ranked.dropFirst().first?.1 != best.1 else {
                return nil
            }
            return CorrectionSuggestion(
                ruleID: best.0.id,
                source: token,
                replacement: best.0.replacement,
                languageScope: best.0.languageScope
            )
        }
        .uniqued { $0.source.lowercased() }
        .prefix(8)
        .map(\.self)
    }

    private static func applyFuzzyMatches(
        to text: String,
        rules: [CorrectionRule],
        existingCounts: [UUID: Int]
    ) -> CorrectionApplication {
        let eligibleRules = Array(
            rules.filter {
                isSingleLatinWord($0.source)
                    && isSingleLatinWord($0.replacement)
                    && $0.source.count >= 5
                    && $0.replacement.count >= 5
                    && !fuzzyBlockedTerms.contains(
                        $0.source.lowercased()
                    )
                    && !fuzzyBlockedTerms.contains(
                        $0.replacement.lowercased()
                    )
                    && editDistance(
                        $0.source.lowercased(),
                        $0.replacement.lowercased()
                    ) <= 2
            }
            .prefix(100)
        )
        guard !eligibleRules.isEmpty else {
            return application(text: text, counts: existingCounts)
        }
        let protectedTerms = Set(
            eligibleRules.map { $0.replacement.lowercased() }
        )
        var corrected = text
        var counts = existingCounts
        for match in latinWordMatches(in: text).reversed() {
            let normalized = match.text.lowercased()
            guard !protectedTerms.contains(normalized) else {
                continue
            }
            let candidates = eligibleRules.filter {
                editDistance(normalized, $0.source.lowercased()) <= 1
                    && editDistance(
                        normalized,
                        $0.replacement.lowercased()
                    ) <= 1
            }
            guard candidates.count == 1,
                  let rule = candidates.first,
                  let range = Range(match.range, in: corrected) else {
                continue
            }
            corrected.replaceSubrange(range, with: rule.replacement)
            counts[rule.id, default: 0] += 1
        }
        return application(text: corrected, counts: counts)
    }

    private static func application(
        text: String,
        counts: [UUID: Int]
    ) -> CorrectionApplication {
        CorrectionApplication(
            text: text,
            usages: counts.map {
                CorrectionUsage(ruleID: $0.key, count: $0.value)
            }
            .sorted { $0.ruleID.uuidString < $1.ruleID.uuidString }
        )
    }

    private static func latinWordMatches(
        in text: String
    ) -> [(text: String, range: NSRange)] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?<![A-Za-z])[A-Za-z]{5,64}(?![A-Za-z])"#
        ) else {
            return []
        }
        let source = text as NSString
        return expression.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        ).prefix(500).map {
            (source.substring(with: $0.range), $0.range)
        }
    }

    private static func isSingleLatinWord(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            $0.isASCII && CharacterSet.letters.contains($0)
        }
    }

    // Common terms stay exact-only even after the user approves a rule.
    // This prevents a nearby valid word from being rewritten silently.
    private static let fuzzyBlockedTerms: Set<String> = [
        "about", "after", "again", "before", "could", "every", "first",
        "other", "should", "their", "there", "these", "thing", "think",
        "those", "where", "which", "while", "would",
        "humko", "karna", "karo", "kyunki", "lekin", "mera", "meri",
        "mujhe", "muje", "nahi", "nahin", "phir", "tera", "tere",
        "tumhe", "tumko", "wala", "wali"
    ]

    private static func editDistance(
        _ lhs: String,
        _ rhs: String
    ) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(
                    min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex]
                            + (leftCharacter == rightCharacter ? 0 : 1)
                    )
                )
            }
            previous = current
        }
        return previous[right.count]
    }
}

private extension Array {
    func uniqued<Key: Hashable>(
        by key: (Element) -> Key
    ) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}

public struct ProfileTextCount: Identifiable, Sendable {
    public var id: String { text }
    public let text: String
    public let count: Int
}

public struct VoiceProfileSnapshot: Sendable {
    public let analyzedDictationCount: Int
    public let topWords: [ProfileTextCount]
    public let catchPhrases: [ProfileTextCount]
    public let correctionRules: [CorrectionRule]
    public let mostActiveHour: Int?

    public static let empty = VoiceProfileSnapshot(
        analyzedDictationCount: 0,
        topWords: [],
        catchPhrases: [],
        correctionRules: [],
        mostActiveHour: nil
    )

    public init(
        analyzedDictationCount: Int,
        topWords: [ProfileTextCount],
        catchPhrases: [ProfileTextCount],
        correctionRules: [CorrectionRule],
        mostActiveHour: Int?
    ) {
        self.analyzedDictationCount = analyzedDictationCount
        self.topWords = topWords
        self.catchPhrases = catchPhrases
        self.correctionRules = correctionRules
        self.mostActiveHour = mostActiveHour
    }

    public static func calculate(
        records: [DictationRecord],
        correctionRules: [CorrectionRule],
        calendar: Calendar = .current
    ) -> VoiceProfileSnapshot {
        let transcripts = records.compactMap(\.finalTranscript)
        var wordCounts: [String: Int] = [:]
        var phraseCounts: [String: Int] = [:]

        for transcript in transcripts {
            let tokens = tokens(in: transcript)
            for token in tokens where !stopWords.contains(token) {
                wordCounts[token, default: 0] += 1
            }
            for length in 2...3 where tokens.count >= length {
                for start in 0...(tokens.count - length) {
                    let phraseTokens = Array(tokens[start..<(start + length)])
                    guard phraseTokens.filter({
                        !stopWords.contains($0)
                    }).count >= 2 else {
                        continue
                    }
                    phraseCounts[
                        phraseTokens.joined(separator: " "),
                        default: 0
                    ] += 1
                }
            }
        }

        let topWords = ranked(wordCounts, minimumCount: 1, limit: 8)
        let phrases = ranked(phraseCounts, minimumCount: 2, limit: 6)
        let hours = Dictionary(
            grouping: records,
            by: { calendar.component(.hour, from: $0.startedAt) }
        )
        let activeHour = hours.max {
            if $0.value.count == $1.value.count {
                return $0.key > $1.key
            }
            return $0.value.count < $1.value.count
        }?.key

        return VoiceProfileSnapshot(
            analyzedDictationCount: transcripts.count,
            topWords: topWords,
            catchPhrases: phrases,
            correctionRules: correctionRules.sorted {
                if $0.usageCount == $1.usageCount {
                    return $0.createdAt < $1.createdAt
                }
                return $0.usageCount > $1.usageCount
            },
            mostActiveHour: activeHour
        )
    }

    private static func tokens(in text: String) -> [String] {
        text.lowercased()
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { $0.count >= 2 }
    }

    private static func ranked(
        _ counts: [String: Int],
        minimumCount: Int,
        limit: Int
    ) -> [ProfileTextCount] {
        counts.compactMap { text, count in
            count >= minimumCount
                ? ProfileTextCount(text: text, count: count)
                : nil
        }
        .sorted {
            if $0.count == $1.count {
                return $0.text < $1.text
            }
            return $0.count > $1.count
        }
        .prefix(limit)
        .map { $0 }
    }

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by",
        "can", "do", "for", "from", "had", "has", "have", "he", "her",
        "his", "i", "if", "in", "is", "it", "its", "me", "my", "not",
        "of", "on", "or", "our", "so", "that", "the", "their", "them",
        "there", "they", "this", "to", "was", "we", "were", "what", "when",
        "where", "which", "who", "will", "with", "you", "your"
    ]
}
