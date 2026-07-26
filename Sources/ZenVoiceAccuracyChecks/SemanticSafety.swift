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
/// Comparison is raw-transcript against refined-transcript, never against the
/// fixture reference. Refinement's contract is that it does not alter meaning
/// relative to *what it was handed*; whether Whisper heard the word correctly
/// in the first place is a transcription question and is already scored by WER.
enum SemanticSafety {
    /// Negations, including the contracted forms. Scoring.normalize strips
    /// apostrophes, so "don't" arrives here as "dont".
    ///
    /// Bare "no" is deliberately absent. It is the one negation that is also a
    /// correction cue — "a login page, no wait, a sign-up page" — where
    /// deleting it is exactly the behaviour we want, so protecting it would
    /// flag correct refinement as a safety violation. It costs real coverage
    /// ("no changes needed" is a genuine negation), and the honest fix is
    /// structural: once the alignment guard understands correction phrases as
    /// units, "no" can be protected everywhere it is not part of one.
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
        let rawCounts = protectedCounts(in: raw)
        let refinedCounts = protectedCounts(in: refined)
        let tokens = Set(rawCounts.keys).union(refinedCounts.keys)
        return tokens.compactMap { token in
            let before = rawCounts[token] ?? 0
            let after = refinedCounts[token] ?? 0
            guard before != after else { return nil }
            return Violation(
                token: token,
                rawCount: before,
                refinedCount: after
            )
        }
        .sorted { $0.token < $1.token }
    }

    private static func protectedCounts(
        in text: String
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for token in Scoring.normalize(text) where isProtected(token) {
            counts[token, default: 0] += 1
        }
        return counts
    }
}
