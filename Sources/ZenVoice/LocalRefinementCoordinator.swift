import Foundation
import ZenVoiceCore
import ZenVoiceRefinementRuntime

final class LocalRefinementCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var refiner: LocalTextRefiner?

    func update(modelURL: URL?) {
        lock.withLock {
            refiner = modelURL.map(LocalTextRefiner.init(modelURL:))
        }
    }

    func refine(
        _ transcript: String,
        mode: InstantRefineMode
    ) -> InstantRefineResult {
        guard mode == .localModel else {
            return InstantRefineEngine().refine(
                transcript,
                mode: mode
            )
        }
        guard let refiner = lock.withLock({ refiner }) else {
            return fallback(transcript)
        }
        do {
            let output = try refiner.refine(transcript)
            guard let candidate =
                LocalRefinementGuard.validatedCandidate(
                    output: output,
                    original: transcript
                ) else {
                return fallback(transcript)
            }
            return InstantRefineResult(
                text: candidate,
                correctionCount: candidate == transcript ? 0 : 1
            )
        } catch {
            return fallback(transcript)
        }
    }

    private func fallback(_ transcript: String) -> InstantRefineResult {
        InstantRefineEngine().refine(
            transcript,
            mode: .clean
        )
    }
}
