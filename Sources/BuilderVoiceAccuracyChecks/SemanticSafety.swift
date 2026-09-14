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

/// Whether refinement changed a token whose loss would change what the user
/// said, rather than merely how it reads.
///
/// Word error rate cannot express this. A dropped "not" costs one word out of
/// twenty and disappears into a 5% average, but it inverts the sentence — and
/// unlike a misheard noun, the user is unlikely to catch it, because the text
/// still reads fluently. So it is counted separately and reported as an
/// absolute number. One violation in a thousand dictations is a product
/// failure, and a percentage would hide it.
///
/// Refinement is compared with its raw ASR input. Transcription safety uses the
/// same protected-token accounting against the human reference, separately
/// from WER, so a fluent-looking number or negation error cannot hide in an
/// average score.
enum SemanticSafety {
    enum ProtectedKind {
        case negation
        case quantity
    }

    /// Negations, including the contracted forms. Scoring.normalize strips
    /// apostrophes, so "don't" arrives here as "dont".
    ///
    /// Bare "no" is handled separately: ASR scoring always protects it, while
    /// refinement's product guard recognizes punctuation-delimited correction
    /// cues such as "no, wait" structurally.
    static let negations: Set<String> = [
        "not", "never", "none", "nothing", "nobody", "nowhere",
        "cannot", "cant", "dont", "doesnt", "didnt", "wont", "wouldnt",
        "shouldnt", "couldnt", "isnt", "arent", "wasnt", "werent",
        "hasnt", "havent", "hadnt", "without", "nor", "neither"
    ]

    /// Spelled-out quantities. Digits are matched separately, by shape.
    static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
        "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion",
        "first", "second", "third", "half", "quarter", "double", "twice"
    ]

    static func isProtected(_ token: String) -> Bool {
        if negations.contains(token) || numberWords.contains(token) {
            return true
        }
        // Any token carrying a digit: "30", "3pm", "v2".
        return token.contains(where: \.isNumber)
    }

    /// A protected token whose count changed between raw and refined.
    struct Violation {
        let token: String
        let rawCount: Int
        let refinedCount: Int
        let kind: ProtectedKind

        var description: String {
            "\(token) \(rawCount)→\(refinedCount)"
        }
    }

    /// Counts are compared as a multiset rather than by presence, so replacing
    /// "thirty" with "thirteen" registers even though both are protected, and
    /// so an *added* negation registers too — inventing a "not" is as bad as
    /// dropping one.
    static func violations(
        raw: String,
        refined: String
    ) -> [Violation] {
        compareProtectedCounts(
            before: protectedCounts(in: raw, includeBareNo: false),
            after: protectedCounts(in: refined, includeBareNo: false)
        )
    }

    /// ASR safety is measured against the spoken reference, so bare "no" is
    /// protected here even though refinement has a structural correction-cue
    /// exception for phrases such as "no, wait".
    static func transcriptionViolations(
        reference: String,
        hypothesis: String
    ) -> [Violation] {
        compareProtectedCounts(
            before: protectedCounts(in: reference, includeBareNo: true),
            after: protectedCounts(in: hypothesis, includeBareNo: true)
        )
    }

    private static func compareProtectedCounts(
        before: [String: Int],
        after: [String: Int]
    ) -> [Violation] {
        let tokens = Set(before.keys).union(after.keys)
        return tokens.compactMap { token in
            let beforeCount = before[token] ?? 0
            let afterCount = after[token] ?? 0
            guard beforeCount != afterCount else { return nil }
            return Violation(
                token: token,
                rawCount: beforeCount,
                refinedCount: afterCount,
                kind: negations.contains(token) || token == "no"
                    ? .negation
                    : .quantity
            )
        }
        .sorted { $0.token < $1.token }
    }

    private static func protectedCounts(
        in text: String,
        includeBareNo: Bool
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for token in Scoring.normalize(text)
        where isProtected(token) || (includeBareNo && token == "no") {
            counts[token, default: 0] += 1
        }
        return counts
    }
}
