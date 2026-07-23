import Foundation

public struct CorrectionRule: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let source: String
    public let replacement: String
    public let usageCount: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        source: String,
        replacement: String,
        usageCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.replacement = replacement
        self.usageCount = usageCount
        self.createdAt = createdAt
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
        rules: [CorrectionRule]
    ) -> CorrectionApplication {
        let normalizedRules = Dictionary(
            rules.map { ($0.source.lowercased(), $0) },
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
            return CorrectionApplication(text: text, usages: [])
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
        return CorrectionApplication(
            text: corrected,
            usages: counts.map {
                CorrectionUsage(ruleID: $0.key, count: $0.value)
            }
            .sorted { $0.ruleID.uuidString < $1.ruleID.uuidString }
        )
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
