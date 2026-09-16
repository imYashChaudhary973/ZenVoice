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
/// Parakeet TDT v3 on Apple Silicon with 16 GB or more. Distil or Turbo on
/// Intel and 8 GB Macs. Apex for Hinglish.
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
        }
        guard !active.isEmpty else {
            return nil
        }

        if profile.isHinglish {
            return firstAvailable(
                [EngineIdentifiers.whisperLargeV3Turbo],
                in: active,
                rationale:
                    "Apex is retired. Whisper Large V3 Turbo covers Hinglish "
                    + "until a replacement ships."
            )
        }

        if !hardware.hasGPUAcceleratedTranscription
            || hardware.isMemoryConstrained
        {
            return firstAvailable(
                [
                    EngineIdentifiers.appleSpeech,
                    EngineIdentifiers.whisperDistilLargeV3,
                    EngineIdentifiers.whisperLargeV3Turbo
                ],
                in: active,
                rationale:
                    "Apple Speech is built in. Distil-Whisper is the local "
                    + "download if Speech is unavailable."
            )
        }

        if profile.prefersParakeetTDTv3 {
            return firstAvailable(
                [
                    EngineIdentifiers.appleSpeech,
                    EngineIdentifiers.parakeetTDTv3,
                    EngineIdentifiers.whisperLargeV3Turbo
                ],
                in: active,
                rationale:
                    "Apple Speech is ready now. Parakeet TDT v3 is the "
                    + "fastest download; Whisper Large V3 Turbo covers 99 "
                    + "languages."
            )
        }

        return firstAvailable(
            [
                EngineIdentifiers.appleSpeech,
                EngineIdentifiers.whisperLargeV3Turbo
            ],
            in: active,
            rationale:
                "Apple Speech is built in. Whisper Large V3 Turbo covers 99 "
                + "languages."
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
            return [EngineIdentifiers.whisperLargeV3Turbo]
        }
        return [recommendation.preferredEngineID]
            + recommendation.fallbackEngineIDs
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
