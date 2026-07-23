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
        guard let refiner = lock.withLock({ refiner }) else {
            return fallback(
                commandText,
                commandCorrectionCount:
                    commandResult.correctionCount
            )
        }
        do {
            let output = try refiner.refine(
                commandText,
                context: context
            )
            guard let candidate =
                LocalRefinementGuard.validatedCandidate(
                    output: output,
                    original: commandText
                ) else {
                return fallback(
                    commandText,
                    commandCorrectionCount:
                        commandResult.correctionCount
                )
            }
            return InstantRefineResult(
                text: candidate,
                correctionCount:
                    commandResult.correctionCount
                    + (candidate == commandText ? 0 : 1)
            )
        } catch {
            return fallback(
                commandText,
                commandCorrectionCount:
                    commandResult.correctionCount
            )
        }
    }

    private func fallback(
        _ transcript: String,
        commandCorrectionCount: Int
    ) -> InstantRefineResult {
        let refined = InstantRefineEngine().refine(
            transcript,
            mode: .clean
        )
        return InstantRefineResult(
            text: refined.text,
            correctionCount:
                commandCorrectionCount + refined.correctionCount,
            wasRejected: refined.wasRejected
        )
    }
}
