import Foundation
import ZenVoiceCore

/// Word Error Rate: of every 100 reference words, how many were substituted,
/// deleted, or invented. Punctuation, case, and digit formatting are ignored so
/// the score reflects recognition rather than presentation.
enum Scoring {
    struct Result {
        var distance: Int
        var referenceWords: Int
        /// Wrong word in the right place.
        var substitutions: Int = 0
        /// Word the speaker said that never made it out.
        var deletions: Int = 0
        /// Word in the output that the speaker never said.
        ///
        /// Tracked separately because it is the fabrication signal. A
        /// substitution is a misheard word; an insertion is invented content,
        /// which for a dictation tool is the more dangerous failure — the user
        /// may never notice text they did not say.
        var insertions: Int = 0

        var rate: Double {
            referenceWords == 0 ? 0 : Double(distance) / Double(referenceWords)
        }

        var insertionRate: Double {
            referenceWords == 0
                ? 0
                : Double(insertions) / Double(referenceWords)
        }

        var percentage: String {
            String(format: "%.1f%%", rate * 100)
        }

        static func + (lhs: Result, rhs: Result) -> Result {
            Result(
                distance: lhs.distance + rhs.distance,
                referenceWords: lhs.referenceWords + rhs.referenceWords,
                substitutions: lhs.substitutions + rhs.substitutions,
                deletions: lhs.deletions + rhs.deletions,
                insertions: lhs.insertions + rhs.insertions
            )
        }

        static let zero = Result(distance: 0, referenceWords: 0)
    }

    static func normalize(_ text: String) -> [String] {
        let folded = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(folded)
            .split(separator: " ")
            .flatMap { spelled(String($0)) }
    }

    /// Expands a number into the words for it, so digits and spelling compare
    /// equal.
    ///
    /// Reference transcripts spell numbers out and Whisper writes digits, and
    /// scoring one against the other counts a correct transcription as wrong.
    /// It was the single largest source of apparent error in the real-speech
    /// corpus: "CHAPTER THIRTY THREE A CONFIDANT" came back as "Chapter 33, A
    /// Confidant" — word-perfect — and scored 40%.
    ///
    /// Only up to 9999, which covers chapter numbers, years and quantities in
    /// dictation. Anything larger is left as digits, where at least both sides
    /// are consistent.
    static func spelled(_ token: String) -> [String] {
        guard let value = Int(token), value >= 0, value <= 9_999 else {
            return [token]
        }
        return words(for: value)
    }

    private static let units = [
        "zero", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
        "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"
    ]
    private static let tens = [
        "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
        "eighty", "ninety"
    ]

    private static func words(for value: Int) -> [String] {
        if value < 20 { return [units[value]] }
        if value < 100 {
            let remainder = value % 10
            return remainder == 0
                ? [tens[value / 10]]
                : [tens[value / 10], units[remainder]]
        }
        if value < 1_000 {
            let remainder = value % 100
            let head = [units[value / 100], "hundred"]
            return remainder == 0 ? head : head + words(for: remainder)
        }
        let remainder = value % 1_000
        let head = words(for: value / 1_000) + ["thousand"]
        return remainder == 0 ? head : head + words(for: remainder)
    }

    static func wordErrorRate(
        reference: String,
        hypothesis: String
    ) -> Result {
        let reference = normalize(reference)
        let hypothesis = normalize(hypothesis)
        guard !reference.isEmpty else {
            return Result(
                distance: hypothesis.count,
                referenceWords: 0,
                insertions: hypothesis.count
            )
        }

        // Full matrix rather than two rows: the backtrace is what separates
        // insertions from substitutions, and that distinction is the point.
        var costs = [[Int]](
            repeating: [Int](repeating: 0, count: hypothesis.count + 1),
            count: reference.count + 1
        )
        for row in 0...reference.count { costs[row][0] = row }
        for column in 0...hypothesis.count { costs[0][column] = column }

        for row in 1...reference.count {
            for column in 1...hypothesis.count {
                let substitution =
                    reference[row - 1] == hypothesis[column - 1] ? 0 : 1
                costs[row][column] = min(
                    costs[row - 1][column] + 1,       // deletion
                    costs[row][column - 1] + 1,       // insertion
                    costs[row - 1][column - 1] + substitution
                )
            }
        }

        var result = Result(
            distance: costs[reference.count][hypothesis.count],
            referenceWords: reference.count
        )
        var row = reference.count
        var column = hypothesis.count
        while row > 0 || column > 0 {
            if row > 0, column > 0 {
                let substitution =
                    reference[row - 1] == hypothesis[column - 1] ? 0 : 1
                if costs[row][column]
                    == costs[row - 1][column - 1] + substitution {
                    if substitution == 1 { result.substitutions += 1 }
                    row -= 1
                    column -= 1
                    continue
                }
            }
            if column > 0, costs[row][column] == costs[row][column - 1] + 1 {
                result.insertions += 1
                column -= 1
                continue
            }
            result.deletions += 1
            row -= 1
        }
        return result
    }

    struct LoanwordResult {
        var preserved: Int
        var total: Int
        /// The English words that did not come back as English.
        var lost: [String]

        var rate: Double {
            total == 0 ? 0 : Double(preserved) / Double(total)
        }

        var percentage: String {
            String(format: "%.0f%%", rate * 100)
        }

        static func + (lhs: LoanwordResult, rhs: LoanwordResult) -> Self {
            LoanwordResult(
                preserved: lhs.preserved + rhs.preserved,
                total: lhs.total + rhs.total,
                lost: lhs.lost + rhs.lost
            )
        }

        static let zero = LoanwordResult(preserved: 0, total: 0, lost: [])
    }

    /// Fewest loanwords a Hinglish-capable model may preserve before the run
    /// fails, out of the 26 the fixtures contain.
    ///
    /// Applies only to a model that claims `.hinglish`. A general multilingual
    /// model scores zero by construction and is not failed for it — that gap is
    /// the reason a Hinglish model exists.
    static let hinglishLoanwordFloor = 18

    /// How many of the English words in a code-switched sentence survived as
    /// English.
    ///
    /// This is the metric the Hinglish path is actually judged on. Word error
    /// rate cannot do the job — Hinglish has no canonical spelling, so half the
    /// "errors" it reports are legitimate spelling variation. Meanwhile the
    /// check that Hinglish output merely contains no Devanagari is passed
    /// equally by `kampyutara par kama kara raha hum` and by
    /// `computer par kaam kar raha hoon`, so it cannot see the defect either.
    ///
    /// Asking whether `computer` came back as `computer` is unambiguous, is
    /// independent of romanization convention, and is exactly the failure
    /// documented in `docs/hinglish/01-diagnosis.md`: an English word spoken
    /// mid-sentence is written by Whisper in Devanagari and then romanized back
    /// by a transform that has no idea it was ever English.
    ///
    /// Multi-word terms are matched as a whole sequence, so `pull request`
    /// counts once and only when both words survive in order.
    static func loanwordPreservation(
        expected: [String],
        hypothesis: String
    ) -> LoanwordResult {
        guard !expected.isEmpty else {
            return .zero
        }
        // Padded so a term match is always bounded by spaces, which keeps
        // `test` from matching inside `stetasa` or `latest`.
        let haystack = " " + normalize(hypothesis).joined(separator: " ") + " "
        var result = LoanwordResult.zero
        for term in expected {
            let needle = " " + normalize(term).joined(separator: " ") + " "
            result.total += 1
            if haystack.contains(needle) {
                result.preserved += 1
            } else {
                result.lost.append(term)
            }
        }
        return result
    }

    /// Fraction of n-grams that have appeared before.
    ///
    /// Whisper's classic long-form failure is a loop — it emits the same phrase
    /// over and over after losing its place at a window boundary. That barely
    /// moves word error rate if the loop replaces a similar amount of text, so
    /// it needs its own detector.
    static func repetitionRate(_ text: String, gramLength: Int = 5) -> Double {
        let words = normalize(text)
        guard words.count >= gramLength * 2 else {
            return 0
        }
        var seen = Set<String>()
        var repeats = 0
        var total = 0
        for start in 0...(words.count - gramLength) {
            let gram = words[start..<(start + gramLength)].joined(separator: " ")
            total += 1
            if !seen.insert(gram).inserted {
                repeats += 1
            }
        }
        return total == 0 ? 0 : Double(repeats) / Double(total)
    }
}

/// Reproduces the boundaries live dictation would cut at, offline.
///
/// The app feeds capture buffers in as they arrive and asks
/// ``StablePauseDetector`` whether a stable phrase has ended. This walks the
/// same decision over a finished recording using the same thresholds, so the
/// harness can compare "decoded in the pieces the app would use" against
/// "decoded whole".
enum LiveSegmentation {
    /// Matches the capture buffer size the recorder typically receives.
    static let analysisWindow = 1_024

    static func segments(
        of samples: [Float],
        sampleRate: Double = 16_000
    ) -> [ArraySlice<Float>] {
        var segments: [ArraySlice<Float>] = []
        var committed = 0
        var lastSpeechSample = 0
        var detector = SpeechActivityDetector()

        var cursor = 0
        while cursor < samples.count {
            let end = min(cursor + analysisWindow, samples.count)
            let levels = SpeechActivityDetector.levels(of: samples[cursor..<end])
            if detector.isSpeech(
                averageDecibels: levels.average,
                peakDecibels: levels.peak
            ) {
                lastSpeechSample = end
            }
            cursor = end

            // Mirrors the recorder: stability is evaluated on every buffer and
            // the boundary is taken as soon as it occurs, not when a timer
            // happens to fire.
            if StablePauseDetector.isStable(
                segmentStart: committed,
                totalSamples: cursor,
                lastSpeechSample: lastSpeechSample,
                sampleRate: sampleRate
            ) {
                segments.append(samples[committed..<cursor])
                committed = cursor
            }
        }

        if committed < samples.count {
            segments.append(samples[committed..<samples.count])
        }
        return segments
    }
}
