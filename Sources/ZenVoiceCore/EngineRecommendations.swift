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
                && $0.isAvailable(for: profile)
                && !EngineIdentifiers.isPreviewOnly($0.descriptor.id)
        }
        guard !active.isEmpty else {
            return nil
        }

        if profile.isHinglish {
            return whisperOnlyRecommendation(
                active: active,
                rationale:
                    "Only Whisper Apex supports Hinglish code-switching with "
                    + "Latin-script output."
            )
        }

        if !hardware.hasGPUAcceleratedTranscription {
            return firstAvailable(
                [
                    EngineIdentifiers.whisper,
                    EngineIdentifiers.appleSpeech
                ],
                in: active,
                rationale:
                    "Intel has no Metal path. Whisper Small is the "
                    + "compromise; Apple Speech is the zero-download fallback."
            )
        }

        if profile.prefersParakeetTDTv3 {
            return firstAvailable(
                [
                    EngineIdentifiers.parakeetTDTv3,
                    EngineIdentifiers.appleSpeech,
                    EngineIdentifiers.whisper
                ],
                in: active,
                rationale:
                    "Parakeet TDT v3 is the measured English/European default "
                    + "(6.9% WER, 73×). Apple Speech is the zero-download "
                    + "fallback. Whisper Turbo covers 99 languages."
            )
        }

        return firstAvailable(
            [
                EngineIdentifiers.whisper,
                EngineIdentifiers.appleSpeech
            ],
            in: active,
            rationale:
                "Whisper Turbo is the 99-language default. Apple Speech is "
                + "the zero-download fallback."
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

    private static func firstAvailable(
        _ ids: [String],
        in active: [any SpeechEngine],
        rationale: String
    ) -> EngineRecommendation? {
        let present = ids.filter { id in
            active.contains { $0.descriptor.id == id }
        }
        guard let preferred = present.first else {
            return nil
        }
        return EngineRecommendation(
            preferredEngineID: preferred,
            fallbackEngineIDs: Array(present.dropFirst()),
            rationale: rationale
        )
    }
}
