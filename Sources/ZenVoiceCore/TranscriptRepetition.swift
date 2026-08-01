import Foundation

/// Detects and cuts runaway repetition — Whisper's classic failure on audio it
/// cannot handle.
///
/// Given code-switched Hindi, general multilingual models stop terminating: one
/// clip made Whisper Tiny emit "We are in India," about a hundred times, and
/// Whisper Turbo ran for fifteen minutes on seventy-three seconds of audio
/// before being abandoned. The decoder never reaches an end-of-segment token,
/// so it runs to its token limit on every window.
///
/// Two things then go wrong, and they need separate defences. The *time* is
/// wasted whatever the text says, which is what the decode deadline in
/// `WhisperTranscriber` is for. And the *text* is garbage, which is this.
///
/// Deliberately independent of Instant Refine. Refinement collapses repeated
/// words, but it is a user preference that can be switched off, and a
/// transcript that loops a hundred times is broken rather than untidy.
public enum TranscriptRepetition {
    /// The longest cycle treated as a loop. Long enough for "we are in India"
    /// but short of a genuinely repeated sentence.
    public static let maximumCycleWords = 6

    /// How many consecutive repeats before it is a malfunction rather than
    /// emphasis. "very very good" is speech; four identical phrases is not.
    public static let repeatsBeforeRunaway = 4

    /// Words a collapse must remove before the decode itself is distrusted
    /// and the speaker is told to check the result.
    ///
    /// Collapsing is tidying; this is diagnosis. A fourfold "no" loses three
    /// words and stays silent, because speakers do that. Twelve words is two
    /// full extra cycles of the longest pattern hunted, which no amount of
    /// emphasis produces — only a decoder that stopped terminating does.
    public static let wordsCutBeforeDistrust = 12

    /// Fraction of repeated n-grams above which a transcript is not trusted.
    ///
    /// Used as a signal that decoding failed, not to edit the text.
    public static func repetitionRate(
        _ text: String,
        gramLength: Int = 5
    ) -> Double {
        let words = tokens(in: text)
        guard words.count >= gramLength * 2 else { return 0 }
        var seen = Set<String>()
        var repeats = 0
        var total = 0
        for start in 0...(words.count - gramLength) {
            let gram = words[start..<(start + gramLength)]
                .joined(separator: " ")
            total += 1
            if !seen.insert(gram).inserted { repeats += 1 }
        }
        return total == 0 ? 0 : Double(repeats) / Double(total)
    }

    /// A collapse and how much it removed, so a caller can tell a tidied
    /// transcript from a decode that malfunctioned.
    public struct RunawayCollapse: Equatable {
        public let text: String
        public let wordsCut: Int
    }

    /// Collapses a runaway loop to a single occurrence, keeping everything
    /// around it.
    ///
    /// Truncation rather than rejection: "We are in India" followed by ninety
    /// nine copies of itself still contains what the speaker said, and
    /// throwing the whole transcript away would lose it.
    public static func collapsingRunaway(_ text: String) -> String {
        collapsingRunawayReporting(text).text
    }

    /// The collapse plus the number of words it cut, for callers that treat
    /// a large cut as evidence the decode failed rather than mere untidiness.
    public static func collapsingRunawayReporting(
        _ text: String
    ) -> RunawayCollapse {
        var words = text.split(
            separator: " ",
            omittingEmptySubsequences: true
        ).map(String.init)
        guard words.count > maximumCycleWords else {
            return RunawayCollapse(text: text, wordsCut: 0)
        }
        let wordCountBeforeCollapse = words.count

        var index = 0
        while index < words.count {
            var collapsed = false
            // Shortest cycle first, so "India India India" is caught as a
            // one-word loop rather than an arbitrary longer window.
            for cycle in 1...maximumCycleWords {
                guard index + cycle * repeatsBeforeRunaway <= words.count
                else { continue }
                let pattern = words[index..<(index + cycle)]
                var repeats = 1
                var cursor = index + cycle
                while cursor + cycle <= words.count,
                      words[cursor..<(cursor + cycle)].elementsEqual(
                        pattern,
                        by: matches
                      ) {
                    repeats += 1
                    cursor += cycle
                }
                if repeats >= repeatsBeforeRunaway {
                    words.removeSubrange((index + cycle)..<cursor)
                    collapsed = true
                    break
                }
            }
            if !collapsed { index += 1 }
        }
        return RunawayCollapse(
            text: words.joined(separator: " "),
            wordsCut: wordCountBeforeCollapse - words.count
        )
    }

    /// Compares words ignoring case and trailing punctuation, because a loop
    /// arrives as "India, India, India" rather than three identical strings.
    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs) && !normalized(lhs).isEmpty
    }

    private static func normalized(_ word: String) -> String {
        word.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .joined()
    }

    private static func tokens(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
