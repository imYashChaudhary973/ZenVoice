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

/// The whole of refinement: spoken commands, then Instant Refine.
///
/// This replaces a coordinator that also drove a downloadable language model.
/// That path was removed after measurement: against 400 human-annotated
/// disfluent/fluent pairs the deterministic rules cut word error rate from
/// 23.2% to 7.2%, and the model added **0.0** on top. A perfect judge — one
/// allowed to read the reference — would have added 0.1. There was no work
/// left for a model to do, so a 1.1 GB download and a per-dictation wait were
/// buying nothing.
/// The measurement lives in git history with the R&D report that produced it.
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
        guard TranscriptSemanticGuard.preservesProtectedTerms(
            original: transcript,
            candidate: refined.text
        ) else {
            return InstantRefineResult(
                text: transcript,
                correctionCount: 0,
                wasRejected: true
            )
        }
        return InstantRefineResult(
            text: refined.text,
            correctionCount:
                commands.correctionCount + refined.correctionCount,
            wasRejected: refined.wasRejected
        )
    }
}
