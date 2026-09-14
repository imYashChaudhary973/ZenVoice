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

/// Rejects fluent-looking refinement that changes a quantity or negation.
///
/// Protected terms are compared as multisets. This catches both deletion and
/// invention, including a repeated "one one" being collapsed to "one". The
/// single structural exception is a punctuation-delimited "no wait" restart
/// cue, where removing "no" is the user's explicit correction command.
public enum TranscriptSemanticGuard {
    public static func preservesProtectedTerms(
        original: String,
        candidate: String
    ) -> Bool {
        protectedCounts(in: original) == protectedCounts(in: candidate)
    }

    /// Returns true only when formatting changed punctuation, whitespace, or
    /// letter case. Word and number tokens must remain in the same order with
    /// the same multiplicity.
    ///
    /// Smart formatting applies this stricter gate to untrusted model output.
    /// It deliberately forbids paraphrasing: formatting may clarify what the
    /// user said, but it may not rewrite what they said.
    public static func preservesLexicalContent(
        original: String,
        candidate: String
    ) -> Bool {
        lexicalTokens(in: original) == lexicalTokens(in: candidate)
    }


    private static let negations: Set<String> = [
        "no", "not", "never", "none", "nothing", "nobody", "nowhere",
        "cannot", "cant", "dont", "doesnt", "didnt", "wont", "wouldnt",
        "shouldnt", "couldnt", "isnt", "arent", "wasnt", "werent",
        "hasnt", "havent", "hadnt", "without", "nor", "neither"
    ]

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
        "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion",
        "first", "second", "third", "half", "quarter", "double", "twice"
    ]

    private static let tokenExpression = try! NSRegularExpression(
        pattern: #"[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*"#
    )
    private static let correctionCueExpression = try! NSRegularExpression(
        pattern: #"(?i)[,—-]\s*no\s*,?\s*wait\b\s*[,—-]?"#
    )

    private static func lexicalTokens(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return tokenExpression.matches(in: text, range: range).compactMap {
            guard let range = Range($0.range, in: text) else { return nil }
            return text[range]
                .lowercased()
                .replacingOccurrences(of: "’", with: "'")
        }
    }

    private static func protectedCounts(in text: String) -> [String: Int] {
        let range = NSRange(text.startIndex..., in: text)
        let withoutCorrectionCue = correctionCueExpression
            .stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: " wait "
            )
        let tokenRange = NSRange(
            withoutCorrectionCue.startIndex...,
            in: withoutCorrectionCue
        )
        var counts: [String: Int] = [:]
        for match in tokenExpression.matches(
            in: withoutCorrectionCue,
            range: tokenRange
        ) {
            guard let range = Range(match.range, in: withoutCorrectionCue) else {
                continue
            }
            let token = withoutCorrectionCue[range]
                .lowercased()
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "’", with: "")
            guard negations.contains(token)
                    || numberWords.contains(token)
                    || token.contains(where: \.isNumber) else {
                continue
            }
            counts[token, default: 0] += 1
        }
        return counts
    }
}
