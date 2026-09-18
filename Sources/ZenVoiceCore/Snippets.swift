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

/// A named spoken shortcut: saying the trigger while dictating inserts the
/// expansion instead. Content may span multiple lines.
public struct VoiceSnippet: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var trigger: String
    public var content: String
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        trigger: String,
        content: String,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.content = content
        self.enabled = enabled
    }
}

/// Defaults-backed persistence. Snippets are settings-grade data, so they
/// ride the same store as the voice command and tone preferences.
public enum SnippetPreferences {
    public static let preferenceKey = "ZenVoice.voiceSnippets"
    public static let limit = 50

    public static func load(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> [VoiceSnippet] {
        guard let data = defaults.data(forKey: preferenceKey),
              let snippets = try? JSONDecoder().decode(
                  [VoiceSnippet].self,
                  from: data
              )
        else {
            return []
        }
        return snippets
    }

    public static func save(
        _ snippets: [VoiceSnippet],
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        guard let data = try? JSONEncoder().encode(snippets) else {
            return
        }
        defaults.set(data, forKey: preferenceKey)
    }
}

/// A resolved snippet hit: the snippet that fired and the text it produced.
public struct SnippetMatch: Equatable, Sendable {
    public let snippet: VoiceSnippet
    /// The expansion delivered into the transcript.
    public let expansion: String
}

/// Applies voice snippets to a transcript. Matching is deliberately
/// conservative: whole-phrase, whole-word, in-order — but each trigger token
/// tolerates a one-character transcription slip ("sheduling" still fires).
/// Multi-line content is inserted as-is.
public struct SnippetEngine: Sendable {
    public init() {}

    /// Finds the first enabled snippet whose trigger fires in `phrase`
    /// and returns its expansion. Pure — powers the TRY IT simulator.
    public func match(
        _ phrase: String,
        snippets: [VoiceSnippet]
    ) -> SnippetMatch? {
        for snippet in snippets where snippet.enabled {
            if firstSpan(of: snippet, in: phrase) != nil {
                return SnippetMatch(
                    snippet: snippet,
                    expansion: snippet.content
                )
            }
        }
        return nil
    }

    /// Replaces every enabled trigger occurrence with its expansion.
    public func apply(
        to transcript: String,
        snippets: [VoiceSnippet],
        isEnabled: Bool
    ) -> InstantRefineResult {
        guard isEnabled, !transcript.isEmpty, !snippets.isEmpty else {
            return InstantRefineResult(
                text: transcript,
                correctionCount: 0
            )
        }

        var candidate = transcript
        var correctionCount = 0
        for snippet in snippets where snippet.enabled {
            // Bound the loop: the expansion itself may contain the trigger,
            // so cap rewrites per snippet.
            var attempts = 0
            while attempts < 5, let span = firstSpan(of: snippet, in: candidate) {
                candidate.replaceSubrange(span, with: snippet.content)
                correctionCount += 1
                attempts += 1
            }
        }

        return InstantRefineResult(
            text: candidate,
            correctionCount: correctionCount
        )
    }

    /// Range of the trigger's token span inside `text`, or nil.
    private func firstSpan(
        of snippet: VoiceSnippet,
        in text: String
    ) -> Range<String.Index>? {
        let triggerTokens = Self.tokens(snippet.trigger).map(\.normalized)
        guard !triggerTokens.isEmpty else { return nil }
        let tokens = Self.tokens(text)
        guard tokens.count >= triggerTokens.count else { return nil }

        for start in tokens.indices
        where start + triggerTokens.count <= tokens.count {
            let window = tokens[start..<start + triggerTokens.count]
            let tolerant = zip(window, triggerTokens).allSatisfy {
                Self.tokensMatch($0.normalized, $1)
            }
            if tolerant {
                let lower = tokens[start].sourceRange.lowerBound
                let upper = tokens[start + triggerTokens.count - 1]
                    .sourceRange.upperBound
                return lower..<upper
            }
        }
        return nil
    }

    /// Token with the surrounding punctuation stripped for comparison; the
    /// `sourceRange` points back into the original text.
    struct Token {
        let sourceRange: Range<String.Index>
        let normalized: String
    }

    static func tokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else {
                index = text.index(after: index)
                continue
            }
            var end = text.index(after: index)
            while end < text.endIndex,
                  text[end].isLetter || text[end].isNumber
            {
                end = text.index(after: end)
            }
            let raw = String(text[index..<end])
            tokens.append(
                Token(
                    sourceRange: index..<end,
                    normalized: raw.lowercased()
                )
            )
            index = end
        }
        return tokens
    }

    /// Case-insensitive equality tolerating one substitution, insertion, or
    /// deletion — small transcription differences, nothing semantic.
    static func tokensMatch(_ a: String, _ b: String) -> Bool {
        a == b || distance(a, b) <= 1
    }

    /// Classic dynamic-programming edit distance (substitution, insertion,
    /// deletion all cost 1).
    static func distance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs.unicodeScalars)
        let right = Array(rhs.unicodeScalars)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        for (row, leftScalar) in left.enumerated() {
            current[0] = row + 1
            for (column, rightScalar) in right.enumerated() {
                let substitution = previous[column]
                    + (leftScalar == rightScalar ? 0 : 1)
                current[column + 1] = min(
                    current[column] + 1,
                    previous[column + 1] + 1,
                    substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
