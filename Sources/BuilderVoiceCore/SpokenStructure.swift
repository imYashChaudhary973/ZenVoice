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

/// One decoded stretch of speech, with when it was said.
public struct TranscriptSegment: Equatable, Sendable {
    public let text: String
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval

    public init(
        text: String,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval
    ) {
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

/// Turns a run of timed segments into paragraphs, using the speaker's pauses.
///
/// A minute of dictation currently arrives as one unbroken block, which is the
/// most visible complaint about the output and the one no amount of word-level
/// tidying addresses. The information needed to fix it is already there —
/// Whisper reports when each segment started and ended — and was being thrown
/// away.
///
/// Nothing here is a language model. Where a speaker stops for breath is a
/// fact about the recording.
public enum SpokenStructure {
    /// Below this a gap is articulatory rather than intended — the mouth
    /// closing on a consonant, not the speaker pausing. Treating these as
    /// structure would shatter every sentence.
    public static let articulatoryFloorSeconds: TimeInterval = 0.25

    /// A paragraph break is never taken below this, however slowly the speaker
    /// is going, so a deliberate talker does not get a break at every comma.
    public static let minimumParagraphGapSeconds: TimeInterval = 0.9

    /// Nor above it, so a fast talker who never pauses long still gets
    /// structure.
    public static let maximumParagraphGapSeconds: TimeInterval = 3.0

    /// How much longer than usual a pause must be to count as a paragraph.
    ///
    /// Relative rather than absolute because speakers differ enormously, and
    /// the research consensus is against fixed thresholds. Someone who pauses
    /// 0.4 s between clauses means something different by a 1 s pause than
    /// someone whose habitual gap is already 0.9 s.
    public static let paragraphGapMultiple = 2.5

    /// The gap that separates paragraphs for this particular speaker, in this
    /// particular recording.
    public static func paragraphGap(
        for segments: [TranscriptSegment]
    ) -> TimeInterval {
        let gaps = self.gaps(between: segments)
            .filter { $0 > articulatoryFloorSeconds }
        guard !gaps.isEmpty else {
            return minimumParagraphGapSeconds
        }
        let median = gaps.sorted()[gaps.count / 2]
        return min(
            maximumParagraphGapSeconds,
            max(minimumParagraphGapSeconds, median * paragraphGapMultiple)
        )
    }

    public static func gaps(
        between segments: [TranscriptSegment]
    ) -> [TimeInterval] {
        guard segments.count > 1 else { return [] }
        return (1..<segments.count).map { index in
            max(
                0,
                segments[index].startSeconds
                    - segments[index - 1].endSeconds
            )
        }
    }

    /// Silent stretches in the recording, as time ranges.
    ///
    /// The pauses have to be measured from the audio, because Whisper's
    /// segment bounds do not contain them: it reports segments that abut, so
    /// `t1` of one equals `t0` of the next and every gap computes as zero even
    /// when the speaker stopped for a second and a half. The segment times are
    /// still what aligns text to the recording — they just cannot say where
    /// the silence was.
    ///
    /// Uses the same adaptive noise floor as live dictation, so a quiet
    /// microphone or a noisy room moves the threshold rather than breaking it.
    public static func silences(
        in samples: [Float],
        sampleRate: Double = 16_000,
        window: Int = 1_024
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        guard !samples.isEmpty else { return [] }
        var detector = SpeechActivityDetector()
        var result: [(start: TimeInterval, end: TimeInterval)] = []
        var silenceStart: Int?
        var cursor = 0
        while cursor < samples.count {
            let end = min(cursor + window, samples.count)
            let levels = SpeechActivityDetector.levels(
                of: samples[cursor..<end]
            )
            let isSpeech = detector.isSpeech(
                averageDecibels: levels.average,
                peakDecibels: levels.peak
            )
            if isSpeech {
                if let start = silenceStart {
                    result.append(
                        (
                            Double(start) / sampleRate,
                            Double(cursor) / sampleRate
                        )
                    )
                    silenceStart = nil
                }
            } else if silenceStart == nil {
                silenceStart = cursor
            }
            cursor = end
        }
        // A trailing silence is the recording ending, not a paragraph.
        return result
    }

    /// Joins segments into text, breaking a paragraph where the speaker took a
    /// long enough pause.
    ///
    /// `silences` comes from the audio. Without it no break is ever taken,
    /// because the segment times alone cannot distinguish a breath from a
    /// full stop.
    public static func text(
        from segments: [TranscriptSegment],
        silences: [(start: TimeInterval, end: TimeInterval)]
    ) -> String {
        let trimmed = segments
            .map {
                TranscriptSegment(
                    text: $0.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    startSeconds: $0.startSeconds,
                    endSeconds: $0.endSeconds
                )
            }
            .filter { !$0.text.isEmpty }
        guard let first = trimmed.first else { return "" }
        guard trimmed.count > 1 else { return first.text }

        // Every silence counts towards the typical gap, including the short
        // ones between words. Filtering to gaps above the articulatory floor
        // first left only paragraph-sized pauses in the sample, so the median
        // *was* a long pause and 2.5x of it put the threshold beyond anything
        // the speaker ever did — measured at 3.0 s against real pauses of
        // 1.5 s, and no break was ever taken. The floor belongs on what counts
        // as a break, not on what counts as typical.
        let durations = silences
            .map { $0.end - $0.start }
            .filter { $0 > 0.05 }
        let threshold: TimeInterval
        if durations.isEmpty {
            threshold = minimumParagraphGapSeconds
        } else {
            let median = durations.sorted()[durations.count / 2]
            threshold = min(
                maximumParagraphGapSeconds,
                max(
                    minimumParagraphGapSeconds,
                    median * paragraphGapMultiple
                )
            )
        }

        var result = first.text
        for index in 1..<trimmed.count {
            let boundary = trimmed[index - 1].endSeconds
            // The longest silence overlapping this boundary, allowing a little
            // slack because the segment time and the energy dip will not agree
            // to the millisecond.
            let pause = silences
                .filter {
                    $0.start <= boundary + 0.35
                        && $0.end >= boundary - 0.35
                }
                .map { $0.end - $0.start }
                .max() ?? 0
            // A break mid-sentence is a speaker hesitating, not starting a new
            // thought, so structure is only taken where the previous segment
            // also came to a close.
            let closed = trimmed[index - 1].text.last.map {
                ".!?।".contains($0)
            } ?? false
            result += pause >= threshold && closed ? "\n\n" : " "
            result += trimmed[index].text
        }
        return result
    }

    /// Segment-only overload, which can never break a paragraph. Kept so
    /// callers without the audio still compose the text correctly.
    public static func text(
        from segments: [TranscriptSegment]
    ) -> String {
        let trimmed = segments
            .map {
                TranscriptSegment(
                    text: $0.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    startSeconds: $0.startSeconds,
                    endSeconds: $0.endSeconds
                )
            }
            .filter { !$0.text.isEmpty }
        guard let first = trimmed.first else { return "" }
        guard trimmed.count > 1 else { return first.text }

        let threshold = paragraphGap(for: trimmed)
        var result = first.text
        for index in 1..<trimmed.count {
            let gap = max(
                0,
                trimmed[index].startSeconds - trimmed[index - 1].endSeconds
            )
            // A break mid-sentence is a speaker hesitating, not starting a new
            // thought, so structure is only taken where the previous segment
            // also came to a close.
            let closed = trimmed[index - 1].text.last.map {
                ".!?।".contains($0)
            } ?? false
            result += gap >= threshold && closed ? "\n\n" : " "
            result += trimmed[index].text
        }
        return result
    }
}
