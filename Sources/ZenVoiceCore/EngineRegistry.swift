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

/// Resolves which `SpeechEngine` to use for a language profile.
///
/// The registry is stateless apart from the immutable engine list. It reads the
/// user's saved preference each time, so callers on any actor can use it
/// without coordinating mutable state.
public struct EngineRegistry: Sendable {
    public let engines: [any SpeechEngine]
    /// Ordered fallback IDs when the preferred engine is unavailable.
    /// Whisper is intentionally the final fallback for every profile.
    public let fallbackOrder: [String]

    public init(
        engines: [any SpeechEngine],
        fallbackOrder: [String] = ["whisper"]
    ) {
        self.engines = engines
        self.fallbackOrder = fallbackOrder
    }

    /// All engines with their availability for the given profile.
    public func availability(
        for profile: LanguageProfile
    ) -> [EngineAvailability] {
        engines.map { engine in
            availability(engine: engine, profile: profile)
        }
    }

    /// The engine the user explicitly chose, if it is available.
    public func preferredEngine(
        for profile: LanguageProfile,
        selectedID: String?
    ) -> (any SpeechEngine)? {
        guard let selectedID else {
            return nil
        }
        guard let engine = engines.first(where: { $0.descriptor.id == selectedID }),
              isCompatible(engine: engine, profile: profile),
              engine.isAvailable else {
            return nil
        }
        return engine
    }

    /// The best engine for the profile, honoring the saved preference first,
    /// then the registry fallback order, then any available engine.
    ///
    /// Returns `nil` only when every engine reports itself unavailable.
    public func resolve(
        for profile: LanguageProfile,
        selectedID: String?
    ) -> (any SpeechEngine)? {
        if let preferred = preferredEngine(
            for: profile,
            selectedID: selectedID
        ) {
            return preferred
        }

        for id in fallbackOrder {
            guard let engine = engines.first(where: { $0.descriptor.id == id }),
                  isCompatible(engine: engine, profile: profile),
                  engine.isAvailable else {
                continue
            }
            return engine
        }

        return engines.first {
            isCompatible(engine: $0, profile: profile) && $0.isAvailable
        }
    }

    /// Convenience that reads the saved preference before resolving.
    public func resolve(
        for profile: LanguageProfile,
        defaults: UserDefaults
    ) -> (any SpeechEngine)? {
        let selectedID = SelectedEnginePreferences.load(
            for: profile,
            defaults: defaults
        )
        return resolve(for: profile, selectedID: selectedID)
    }

    /// Prepares the resolved engine for the profile.
    public func prepare(
        for profile: LanguageProfile,
        selectedID: String?
    ) async throws {
        guard let engine = resolve(for: profile, selectedID: selectedID) else {
            throw EngineError.noEngineAvailable
        }
        do {
            try await engine.prepare()
        } catch {
            throw EngineError.preparationFailed(
                engine.descriptor.id,
                error
            )
        }
    }

    /// Transcribes `audioURL` using the resolved engine.
    public func transcribe(
        audioURL: URL,
        profile: LanguageProfile,
        selectedID: String?,
        initialPrompt: String? = nil
    ) async throws -> TranscriptionResult {
        guard let engine = resolve(for: profile, selectedID: selectedID) else {
            throw EngineError.noEngineAvailable
        }
        do {
            return try await engine.transcribe(
                audioURL: audioURL,
                languageProfile: profile,
                initialPrompt: initialPrompt
            )
        } catch {
            throw EngineError.transcriptionFailed(
                engine.descriptor.id,
                error
            )
        }
    }

    /// Convenience that reads the saved preference before transcribing.
    public func transcribe(
        audioURL: URL,
        profile: LanguageProfile,
        defaults: UserDefaults,
        initialPrompt: String? = nil
    ) async throws -> TranscriptionResult {
        let selectedID = SelectedEnginePreferences.load(
            for: profile,
            defaults: defaults
        )
        return try await transcribe(
            audioURL: audioURL,
            profile: profile,
            selectedID: selectedID,
            initialPrompt: initialPrompt
        )
    }

    private func availability(
        engine: any SpeechEngine,
        profile: LanguageProfile
    ) -> EngineAvailability {
        let compatible = isCompatible(engine: engine, profile: profile)
        if !compatible {
            return EngineAvailability(
                engine: engine.descriptor,
                isAvailable: false,
                reason: .unsupportedLanguage(profile.inputDisplayName)
            )
        }
        if !engine.isAvailable {
            return EngineAvailability(
                engine: engine.descriptor,
                isAvailable: false,
                reason: .runtimeNotReady(engine.descriptor.id)
            )
        }
        return EngineAvailability(
            engine: engine.descriptor,
            isAvailable: true
        )
    }

    private func isCompatible(
        engine: any SpeechEngine,
        profile: LanguageProfile
    ) -> Bool {
        let supported = engine.descriptor.supportedLanguages
        if !supported.isEmpty {
            // Built-in engines list the concrete locales they support.
            if profile.inputLanguageCode == LanguageProfile.automaticCode {
                return supported.contains { $0.code == "en" }
            }
            return supported.contains { $0.code == profile.inputLanguageCode }
        }
        // Download-based engines declare no concrete locale list; they rely
        // on the broad language capability instead.
        return profile.isCompatible(with: engine.languageCapability)
    }
}

