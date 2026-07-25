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
            .map(String.init)
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
