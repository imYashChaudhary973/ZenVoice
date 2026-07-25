import Foundation

/// Words refinement may never remove, whatever else it is allowed to do.
///
/// Dropping one of these does not make the transcript untidy, it makes it
/// false — and fluently false, which is worse. A user proof-reading a
/// dictation will catch a garbled noun because it reads wrong; they will not
/// catch a missing "not", because the sentence still reads perfectly and
/// simply means the opposite of what they said.
///
/// This is the floor under every refinement mode. Deterministic Clean cannot
/// reach these words because its rules do not name them, and the local model
/// is denied them explicitly by the drop guard.
public enum ProtectedTokens {
    /// Negations, including contracted forms with the apostrophe removed, so
    /// "don't" and "dont" both match.
    ///
    /// Bare "no" is deliberately absent: it doubles as a correction cue in
    /// "a login page, no wait, a sign-up page", where removing it is the
    /// desired behaviour. Protecting it everywhere would forbid a correct
    /// edit. It costs real coverage — "no changes needed" is a genuine
    /// negation — and the honest fix is to teach the guard about correction
    /// phrases as units, at which point "no" can be protected everywhere it
    /// is not part of one.
    public static let negations: Set<String> = [
        "not", "never", "none", "nothing", "nobody", "nowhere",
        "cannot", "cant", "dont", "doesnt", "didnt", "wont", "wouldnt",
        "shouldnt", "couldnt", "isnt", "arent", "wasnt", "werent",
        "hasnt", "havent", "hadnt", "without", "nor", "neither"
    ]

    /// Spelled-out quantities. Digits are matched by shape instead, so "30",
    /// "3pm" and "v2" need no listing.
    public static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
        "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion",
        "first", "second", "third", "half", "quarter", "double", "twice"
    ]

    /// Strips surrounding punctuation and case so "Not," and "not" match.
    public static func normalized(_ word: String) -> String {
        word.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .joined()
    }

    public static func isProtected(_ word: String) -> Bool {
        let token = normalized(word)
        guard !token.isEmpty else {
            return false
        }
        if negations.contains(token) || numberWords.contains(token) {
            return true
        }
        return token.contains(where: \.isNumber)
    }
}
