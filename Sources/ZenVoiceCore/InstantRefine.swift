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
        defaults: UserDefaults = .standard
    ) -> InstantRefineMode {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let mode = InstantRefineMode(rawValue: rawValue) else {
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
        correctionCount += replace(
            in: &candidate,
            pattern:
                #"(?i)(?<![\p{L}\p{N}_])(?:um+|uh+|erm+)(?:\s*,\s*|\s+|$)"#,
            template: ""
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
