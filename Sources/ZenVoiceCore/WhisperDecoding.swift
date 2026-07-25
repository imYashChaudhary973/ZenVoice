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
    public static let beamSearchSizeCeilingBytes: Int64 = 300_000_000

    public static func usesBeamSearch(modelFileSizeBytes: Int64) -> Bool {
        modelFileSizeBytes > 0
            && modelFileSizeBytes < beamSearchSizeCeilingBytes
    }
}
