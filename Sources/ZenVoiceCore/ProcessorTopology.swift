import Darwin
import Foundation

/// How many threads a decode should ask for.
///
/// The interesting thing here is a change that was tried and rejected.
///
/// `activeProcessorCount` counts efficiency cores alongside performance ones,
/// and whisper splits a batch evenly across the threads it is given — so the
/// expectation was that threads landing on E-cores would hold up the P-core
/// threads waiting at the join, and that asking for the performance count only
/// would be faster. Measured on a 4P/6E machine against the accuracy harness's
/// twelve clips, whisper-large-v3-turbo, GPU enabled:
///
///     8 threads (whole machine)   11.02 s
///     4 threads (P-cores only)    11.10 s
///
/// No difference beyond noise, and if anything the narrower pool was slower.
/// The theory does not hold because `use_gpu` is on: the encoder runs on Metal
/// and the decoder is a small share of a short clip, so the thread count barely
/// participates. The original whole-machine count therefore stands, and
/// ``performanceCoreCount`` is kept only because the next person to have this
/// idea should find the measurement rather than repeat the experiment.
public enum ProcessorTopology {
    /// Logical cores in the highest-performance level, or the whole machine's
    /// count where no such level is reported (Intel has no perflevel split).
    public static let performanceCoreCount: Int = {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname(
            "hw.perflevel0.logicalcpu",
            &count,
            &size,
            nil,
            0
        )
        guard status == 0, count > 0 else {
            return ProcessInfo.processInfo.activeProcessorCount
        }
        return Int(count)
    }()

    /// Thread count for a whisper decode.
    ///
    /// The ceiling is whisper's own: past eight threads the per-thread
    /// coordination cost outweighs the extra parallelism on the models ZenVoice
    /// ships.
    ///
    /// `ZENVOICE_DECODE_THREADS` overrides the choice, so the question above
    /// can be re-measured on other hardware without another build.
    public static var decodeThreadCount: Int32 {
        if let override = ProcessInfo.processInfo
            .environment["ZENVOICE_DECODE_THREADS"]
            .flatMap(Int.init),
           override > 0 {
            return Int32(min(16, override))
        }
        return Int32(
            max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
        )
    }
}
