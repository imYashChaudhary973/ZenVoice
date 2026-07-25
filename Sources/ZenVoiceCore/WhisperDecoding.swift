import Foundation

/// How aggressively the decoder should search for a better transcript.
public enum WhisperDecoding {
    /// Greedy decoding commits to the most likely token at every step and never
    /// reconsiders. Beam search keeps several candidate transcripts alive and
    /// picks whichever reads best overall, so an early wrong guess can still be
    /// corrected.
    ///
    /// That safety net is worth roughly three points of word error rate on
    /// Whisper Base, and nothing measurable on Medium or Turbo — those models
    /// are confident enough that the alternatives it explores are identical, so
    /// the extra decode time buys nothing. It is therefore paid for only where
    /// it pays back.
    public static let beamSize: Int32 = 5

    /// Tiny and Base fall below this; Small and everything larger sit above it.
    ///
    /// The ceiling looks like a crude proxy for "is this model confident
    /// enough", and it was reasonable to expect it to misclassify
    /// Whisper-Hindi2Hinglish-Apex: 874 MB puts it far above the line, yet it
    /// decodes an under-represented language where alternatives should be
    /// worth exploring. Measured, and the proxy holds anyway:
    ///
    ///     greedy       English 16.8%   loanwords 21/26   long-form clean
    ///     beam size 5  English 15.5%   loanwords 21/26   invents 5 words
    ///
    /// Beam search bought 1.3 points of English word error rate, nothing at all
    /// on the metric Apex exists for, and started fabricating — enough to trip
    /// the harness's 5% insertion ceiling on long-form. Invented text is the
    /// worst failure a dictation tool has, because the user may never notice
    /// words they did not say. Not worth 1.3 points.
    public static let beamSearchSizeCeilingBytes: Int64 = 300_000_000

    public static func usesBeamSearch(modelFileSizeBytes: Int64) -> Bool {
        modelFileSizeBytes > 0
            && modelFileSizeBytes < beamSearchSizeCeilingBytes
    }

    /// How long decoding may run, as a multiple of the recording's own length.
    ///
    /// Decoding is normally far faster than real time — Whisper Turbo runs at
    /// about nine times, Tiny at a hundred — so a decode that takes twice the
    /// audio's duration is not slow, it is stuck. Measured: seventy-three
    /// seconds of code-switched Hindi ran for fifteen minutes under Turbo
    /// before being abandoned, because the decoder loops and runs to its token
    /// limit on every window.
    ///
    /// Set high enough that an unaccelerated Intel Mac running a large model
    /// never trips it, and low enough that the user is not left staring at a
    /// frozen app.
    public static let decodeTimeoutMultiple: Double = 2

    /// Floor for the deadline, so a two-second utterance still gets a workable
    /// budget including model load.
    public static let minimumDecodeTimeoutSeconds: TimeInterval = 15

    public static func decodeDeadline(
        audioSeconds: TimeInterval
    ) -> TimeInterval {
        max(
            minimumDecodeTimeoutSeconds,
            audioSeconds * decodeTimeoutMultiple
        )
    }

    /// Silence prepended to every recording before decoding.
    ///
    /// Push-to-talk gives Whisper no lead-in: the user presses the key and
    /// starts talking, so speech begins in the opening milliseconds of the
    /// buffer. Some models drop the first word outright when that happens.
    /// Measured on Whisper-Hindi2Hinglish-Apex with the same clip, and the
    /// first word is simply gone:
    ///
    ///     no padding    "Ka status kya hai? Mainne email bhej diya."
    ///     0.5 s padding "Project ka status kya hai? Mainne email bhej diya."
    ///
    /// The word error rate on that clip halves, 22.2% to 11.1%.
    ///
    /// This is free. whisper.cpp pads every input out to its 30-second window
    /// regardless, so half a second of leading silence costs no extra decode
    /// time — it only moves where the speech sits inside a window that was
    /// going to be filled anyway.
    public static let leadInSilenceSeconds = 0.5

    public static func withLeadInSilence(
        _ samples: [Float],
        sampleRate: Double = 16_000
    ) -> [Float] {
        guard !samples.isEmpty else {
            return samples
        }
        let padding = Int(leadInSilenceSeconds * sampleRate)
        return [Float](repeating: 0, count: padding) + samples
    }
}
