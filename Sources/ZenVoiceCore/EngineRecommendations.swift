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

/// A recommendation for which engine to use for a given language profile.
///
/// The recommendation is computed from the active engine list, the language
/// profile, and the hardware profile. It is a default only; the user can
/// override it per `LanguageProfile`.
public struct EngineRecommendation: Equatable, Sendable {
    public let preferredEngineID: String
    public let fallbackEngineIDs: [String]
    public let rationale: String

    public init(
        preferredEngineID: String,
        fallbackEngineIDs: [String] = [],
        rationale: String
    ) {
        self.preferredEngineID = preferredEngineID
        self.fallbackEngineIDs = fallbackEngineIDs
        self.rationale = rationale
    }
}

/// Recommends a speech engine for a language profile.
///
/// In Phase 2a only Whisper and Apple Speech are active, so the recommendation
/// is simple: Apple Speech for supported locales on this Mac, Whisper
/// everywhere else. The structure is designed so Phase 2b can add Parakeet and
/// Nemotron by inserting them before Apple Speech/Whisper when they are active.
public enum EngineRecommendationEngine {
    /// Recommended engine and fallbacks for the profile.
    ///
    /// Returns `nil` only when the registry contains no compatible active
    /// engine. This should not happen in a correctly configured app because
    /// Whisper is always present.
    public static func recommendation(
        for profile: LanguageProfile,
        hardware: HardwareProfile,
        registry: EngineRegistry
    ) -> EngineRecommendation? {
        let active = registry.engines.filter {
            registry.isCompatible(engine: $0, profile: profile)
                && $0.isAvailable
        }
        guard !active.isEmpty else {
            return nil
        }

        // Hinglish is not supported by any built-in engine other than Whisper.
        if profile == .hinglish {
            return whisperOnlyRecommendation(
                active: active,
                rationale:
                    "Only Whisper supports Hinglish code-switching with "
                    + "Latin-script output."
            )
        }

        // English on Apple Silicon: prefer the highest-quality downloaded
        // model first (Cohere, then Parakeet TDT v3/v2, Flash, Nemotron),
        // then Apple Speech, then Whisper.
        if profile == .english {
            if hasCohereTranscribe(in: active) {
                return EngineRecommendation(
                    preferredEngineID: EngineIdentifiers.cohereTranscribe,
                    fallbackEngineIDs: [
                        EngineIdentifiers.parakeetTDTv3,
                        EngineIdentifiers.parakeetTDTv2,
                        EngineIdentifiers.parakeetFlash,
                        EngineIdentifiers.nemotronSpeechMultilingual,
                        EngineIdentifiers.nemotronSpeechUltraFast,
                        EngineIdentifiers.appleSpeech,
                        EngineIdentifiers.whisper
                    ],
                    rationale:
                        "Cohere Transcribe is the highest-accuracy local "
                        + "multilingual option. Parakeet, Nemotron, Apple "
                        + "Speech and Whisper are fallbacks."
                )
            }
            if hasParakeetTDTv3(in: active) {
                return EngineRecommendation(
                    preferredEngineID: EngineIdentifiers.parakeetTDTv3,
                    fallbackEngineIDs: [
                        EngineIdentifiers.parakeetTDTv2,
                        EngineIdentifiers.parakeetFlash,
                        EngineIdentifiers.nemotronSpeechMultilingual,
                        EngineIdentifiers.nemotronSpeechUltraFast,
                        EngineIdentifiers.appleSpeech,
                        EngineIdentifiers.whisper
                    ],
                    rationale:
                        "Parakeet TDT v3 is a fast local multilingual model. "
                        + "Parakeet TDT v2, Parakeet Flash, Nemotron, Apple "
                        + "Speech and Whisper are fallbacks."
                )
            }
            if hasParakeetTDTv2(in: active) {
                return EngineRecommendation(
                    preferredEngineID: EngineIdentifiers.parakeetTDTv2,
                    fallbackEngineIDs: [
                        EngineIdentifiers.parakeetFlash,
                        EngineIdentifiers.nemotronSpeechMultilingual,
                        EngineIdentifiers.nemotronSpeechUltraFast,
                        EngineIdentifiers.appleSpeech,
                        EngineIdentifiers.whisper
                    ],
                    rationale:
                        "Parakeet TDT v2 is a fast local English model. "
                        + "Parakeet Flash, Nemotron, Apple Speech and Whisper "
                        + "are the fallbacks."
                )
            }
            if hasNemotronSpeechMultilingual(in: active) {
                return EngineRecommendation(
                    preferredEngineID: EngineIdentifiers.nemotronSpeechMultilingual,
                    fallbackEngineIDs: [
                        EngineIdentifiers.nemotronSpeechUltraFast,
                        EngineIdentifiers.appleSpeech,
                        EngineIdentifiers.whisper
                    ],
                    rationale:
                        "Nemotron 3.5 Multilingual is a 40-locale on-device "
                        + "model. The streaming variant, Apple Speech and "
                        + "Whisper are fallbacks."
                )
            }
            if hasNemotronSpeechUltraFast(in: active) {
                return EngineRecommendation(
                    preferredEngineID: EngineIdentifiers.nemotronSpeechUltraFast,
                    fallbackEngineIDs: [
                        EngineIdentifiers.appleSpeech,
                        EngineIdentifiers.whisper
                    ],
                    rationale:
                        "Nemotron Speech 3.5 Ultra Fast is a cache-aware "
                        + "streaming model. Apple Speech and Whisper are "
                        + "fallbacks."
                )
            }
            if hasAppleSpeech(in: active) {
                return EngineRecommendation(
                    preferredEngineID: EngineIdentifiers.appleSpeech,
                    fallbackEngineIDs: [EngineIdentifiers.whisper],
                    rationale:
                        "Apple Speech needs no download and runs on-device. "
                        + "Whisper remains the quality fallback."
                )
            }
            return whisperOnlyRecommendation(
                active: active,
                rationale:
                    "Apple Speech on-device recognition is not available for "
                    + "this locale; Whisper is the fallback."
            )
        }

        // Multilingual profiles: prefer Cohere for its 14 supported locales,
        // then Parakeet TDT v3, then Nemotron, then Apple Speech, then Whisper.
        if hasCohereTranscribe(in: active) {
            return EngineRecommendation(
                preferredEngineID: EngineIdentifiers.cohereTranscribe,
                fallbackEngineIDs: [
                    EngineIdentifiers.parakeetTDTv3,
                    EngineIdentifiers.nemotronSpeechMultilingual,
                    EngineIdentifiers.nemotronSpeechUltraFast,
                    EngineIdentifiers.appleSpeech,
                    EngineIdentifiers.whisper
                ],
                rationale:
                    "Cohere Transcribe is the highest-accuracy local option "
                    + "for its supported languages. Parakeet, Nemotron, "
                    + "Apple Speech and Whisper are the fallbacks."
            )
        }
        if hasParakeetTDTv3(in: active) {
            return EngineRecommendation(
                preferredEngineID: EngineIdentifiers.parakeetTDTv3,
                fallbackEngineIDs: [
                    EngineIdentifiers.nemotronSpeechMultilingual,
                    EngineIdentifiers.nemotronSpeechUltraFast,
                    EngineIdentifiers.appleSpeech,
                    EngineIdentifiers.whisper
                ],
                rationale:
                    "Parakeet TDT v3 is a fast local multilingual model. "
                    + "Nemotron, Apple Speech and Whisper are the fallbacks."
            )
        }
        if hasNemotronSpeechMultilingual(in: active) {
            return EngineRecommendation(
                preferredEngineID: EngineIdentifiers.nemotronSpeechMultilingual,
                fallbackEngineIDs: [
                    EngineIdentifiers.nemotronSpeechUltraFast,
                    EngineIdentifiers.appleSpeech,
                    EngineIdentifiers.whisper
                ],
                rationale:
                    "Nemotron 3.5 Multilingual supports 40 locales on-device. "
                    + "The streaming variant, Apple Speech and Whisper are "
                    + "fallbacks."
            )
        }
        if hasAppleSpeech(in: active) {
            return EngineRecommendation(
                preferredEngineID: EngineIdentifiers.appleSpeech,
                fallbackEngineIDs: [EngineIdentifiers.whisper],
                rationale:
                    "Apple Speech supports this locale on-device with no "
                    + "download. Whisper covers the broadest language set."
            )
        }
        return whisperOnlyRecommendation(
            active: active,
            rationale:
                "Apple Speech on-device recognition is not available for "
                + "this locale; Whisper is the fallback."
        )
    }

    /// Ordered fallback list suitable for `EngineRegistry.fallbackOrder`.
    public static func fallbackOrder(
        for profile: LanguageProfile,
        hardware: HardwareProfile,
        registry: EngineRegistry
    ) -> [String] {
        guard let recommendation = recommendation(
            for: profile,
            hardware: hardware,
            registry: registry
        ) else {
            return [EngineIdentifiers.whisper]
        }
        return [recommendation.preferredEngineID]
            + recommendation.fallbackEngineIDs
    }

    private static func whisperOnlyRecommendation(
        active: [any SpeechEngine],
        rationale: String
    ) -> EngineRecommendation? {
        guard let whisper = active.first(
            where: { $0.descriptor.id == EngineIdentifiers.whisper }
        ) else {
            return nil
        }
        return EngineRecommendation(
            preferredEngineID: whisper.descriptor.id,
            fallbackEngineIDs: [],
            rationale: rationale
        )
    }

    private static func hasAppleSpeech(in active: [any SpeechEngine]) -> Bool {
        active.contains {
            $0.descriptor.id == EngineIdentifiers.appleSpeech
        }
    }

    private static func hasParakeetFlash(in active: [any SpeechEngine]) -> Bool {
        active.contains {
            $0.descriptor.id == EngineIdentifiers.parakeetFlash
        }
    }

    private static func hasParakeetTDTv2(in active: [any SpeechEngine]) -> Bool {
        active.contains {
            $0.descriptor.id == EngineIdentifiers.parakeetTDTv2
        }
    }

    private static func hasParakeetTDTv3(in active: [any SpeechEngine]) -> Bool {
        active.contains {
            $0.descriptor.id == EngineIdentifiers.parakeetTDTv3
        }
    }

    private static func hasNemotronSpeechUltraFast(
        in active: [any SpeechEngine]
    ) -> Bool {
        active.contains {
            $0.descriptor.id == EngineIdentifiers.nemotronSpeechUltraFast
        }
    }

    private static func hasNemotronSpeechMultilingual(
        in active: [any SpeechEngine]
    ) -> Bool {
        active.contains {
            $0.descriptor.id == EngineIdentifiers.nemotronSpeechMultilingual
        }
    }

    private static func hasCohereTranscribe(
        in active: [any SpeechEngine]
    ) -> Bool {
        active.contains {
            $0.descriptor.id == EngineIdentifiers.cohereTranscribe
        }
    }
}
