import Foundation

/// The whole of refinement: spoken commands, then Instant Refine.
///
/// This replaces a coordinator that also drove a downloadable language model.
/// That path was removed after measurement: against 400 human-annotated
/// disfluent/fluent pairs the deterministic rules cut word error rate from
/// 23.2% to 7.2%, and the model added **0.0** on top. A perfect judge — one
/// allowed to read the reference — would have added 0.1. There was no work
/// left for a model to do, so a 1.1 GB download and a per-dictation wait were
/// buying nothing.
///
/// See docs/REFINEMENT_RD.md section 8.9.
public enum TranscriptRefinement {
    public static func refine(
        _ transcript: String,
        mode: InstantRefineMode,
        languageCode: String = "en",
        voiceCommandsEnabled: Bool = false
    ) -> InstantRefineResult {
        // Voice commands are deterministic and run first, so "new paragraph"
        // becomes a break before any rule inspects the words around it.
        let commands = LocalVoiceCommandEngine().apply(
            to: transcript,
            languageCode: languageCode,
            isEnabled: voiceCommandsEnabled
        )
        let refined = InstantRefineEngine().refine(
            commands.text,
            mode: mode
        )
        return InstantRefineResult(
            text: refined.text,
            correctionCount:
                commands.correctionCount + refined.correctionCount,
            wasRejected: refined.wasRejected
        )
    }
}
