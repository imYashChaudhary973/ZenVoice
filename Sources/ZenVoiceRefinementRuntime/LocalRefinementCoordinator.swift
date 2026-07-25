import Foundation
import ZenVoiceCore

public final class LocalRefinementCoordinator: @unchecked Sendable {
    public init() {}

    private let lock = NSLock()
    private var refiner: LocalTextRefiner?

    public func update(modelURL: URL?) {
        lock.withLock {
            refiner = modelURL.map(LocalTextRefiner.init(modelURL:))
        }
    }

    /// Loads the model and prefills the instruction block before the user asks
    /// for anything.
    ///
    /// Without this the first dictation of a session pays the model load
    /// inside the path it is waiting on. Failures are deliberately ignored:
    /// this is an optimization, and every caller of `refine` already falls
    /// back to deterministic Clean when the model is unavailable.
    ///
    /// Blocks the calling thread, so call it off the main queue.
    public func warmUp() {
        guard let refiner = lock.withLock({ refiner }) else {
            return
        }
        try? refiner.warmUp()
    }

    public func refine(
        _ transcript: String,
        mode: InstantRefineMode,
        languageCode: String = "en",
        context: String = "",
        voiceCommandsEnabled: Bool = false
    ) -> InstantRefineResult {
        let commandResult = LocalVoiceCommandEngine().apply(
            to: transcript,
            languageCode: languageCode,
            isEnabled: voiceCommandsEnabled
        )
        let commandText = commandResult.text
        guard mode == .localModel else {
            let refined = InstantRefineEngine().refine(
                commandText,
                mode: mode
            )
            return InstantRefineResult(
                text: refined.text,
                correctionCount:
                    commandResult.correctionCount
                    + refined.correctionCount,
                wasRejected: refined.wasRejected
            )
        }
        let cleanResult = InstantRefineEngine().refine(
            commandText,
            mode: .clean
        )
        let safeBaseline = cleanResult.text
        guard let refiner = lock.withLock({ refiner }) else {
            return InstantRefineResult(
                text: safeBaseline,
                correctionCount:
                    commandResult.correctionCount
                    + cleanResult.correctionCount,
                wasRejected: cleanResult.wasRejected
            )
        }
        do {
            let output = try refiner.refine(
                safeBaseline,
                context: context
            )
            guard let candidate =
                LocalRefinementGuard.validatedCandidate(
                    output: output,
                    original: safeBaseline
                ) else {
                return InstantRefineResult(
                    text: safeBaseline,
                    correctionCount:
                        commandResult.correctionCount
                        + cleanResult.correctionCount,
                    wasRejected: true
                )
            }
            return InstantRefineResult(
                text: candidate,
                correctionCount:
                    commandResult.correctionCount
                    + cleanResult.correctionCount
                    + (candidate == safeBaseline ? 0 : 1)
            )
        } catch {
            return InstantRefineResult(
                text: safeBaseline,
                correctionCount:
                    commandResult.correctionCount
                    + cleanResult.correctionCount,
                wasRejected: cleanResult.wasRejected
            )
        }
    }
}
