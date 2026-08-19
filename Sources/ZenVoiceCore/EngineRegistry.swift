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
        guard let selectedID,
              !EngineIdentifiers.isPreviewOnly(selectedID) else {
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

        for id in fallbackOrder where !EngineIdentifiers.isPreviewOnly(id) {
            guard let engine = engines.first(where: { $0.descriptor.id == id }),
                  isCompatible(engine: engine, profile: profile),
                  engine.isAvailable else {
                continue
            }
            return engine
        }

        return engines.first {
            !EngineIdentifiers.isPreviewOnly($0.descriptor.id)
                && isCompatible(engine: $0, profile: profile)
                && $0.isAvailable
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

    /// Live-preview engine: Flash, then Nemotron Ultra Fast (streaming mode),
    /// then Whisper. Never used for final insert.
    public func resolvePreview(
        for profile: LanguageProfile,
        nemotronMode: NemotronPreferences.Mode = NemotronPreferences.load()
    ) -> (any SpeechEngine)? {
        var order = [EngineIdentifiers.parakeetFlash]
        if nemotronMode == .streaming {
            order.append(EngineIdentifiers.nemotronSpeechUltraFast)
        }
        order.append(EngineIdentifiers.whisper)
        for id in order {
            guard let engine = engines.first(where: { $0.descriptor.id == id }),
                  engine.isAvailable,
                  isCompatible(engine: engine, profile: profile) else {
                continue
            }
            return engine
        }
        return nil
    }

    /// Prepares the resolved engine for the profile.
    public func prepare(
        for profile: LanguageProfile,
        selectedID: String?
    ) async throws {
        let candidates = candidateEngines(
            for: profile,
            selectedID: selectedID
        )
        guard !candidates.isEmpty else {
            throw EngineError.noEngineAvailable
        }
        var lastFailure: (id: String, error: Error)?
        for engine in candidates {
            try Task.checkCancellation()
            do {
                try await engine.prepare()
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                lastFailure = (engine.descriptor.id, error)
            }
        }
        if let lastFailure {
            throw EngineError.preparationFailed(
                lastFailure.id,
                lastFailure.error
            )
        }
        throw EngineError.noEngineAvailable
    }

    /// Frees every engine's loaded model.
    ///
    /// Called when dictation has been idle. Releasing all of them rather than
    /// only the resolved one matters because the resolved engine changes with
    /// the language profile and the user's selection, so an engine prepared
    /// earlier in the session can still be holding a model nothing is going to
    /// ask for.
    public func releaseAll() async {
        for engine in engines {
            await engine.release()
        }
    }

    /// Transcribes `audioURL` using the resolved engine.
    public func transcribe(
        audioURL: URL,
        profile: LanguageProfile,
        selectedID: String?,
        initialPrompt: String? = nil
    ) async throws -> TranscriptionResult {
        let candidates = candidateEngines(
            for: profile,
            selectedID: selectedID
        )
        guard !candidates.isEmpty else {
            throw EngineError.noEngineAvailable
        }
        var lastFailure: (id: String, error: Error)?
        for engine in candidates {
            try Task.checkCancellation()
            do {
                return try await engine.transcribe(
                    audioURL: audioURL,
                    languageProfile: profile,
                    initialPrompt: initialPrompt
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                lastFailure = (engine.descriptor.id, error)
            }
        }
        if let lastFailure {
            throw EngineError.transcriptionFailed(
                lastFailure.id,
                lastFailure.error
            )
        }
        throw EngineError.noEngineAvailable
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

    /// Compatible, available engines in the exact order they should be tried.
    ///
    /// Deduplication matters because the selected engine can also appear in
    /// `fallbackOrder`. The final pass preserves the registry's historical
    /// behavior of using another compatible engine when a configured fallback
    /// list is incomplete.
    private func candidateEngines(
        for profile: LanguageProfile,
        selectedID: String?
    ) -> [any SpeechEngine] {
        var ordered: [any SpeechEngine] = []
        var seen: Set<String> = []

        func append(_ engine: any SpeechEngine) {
            guard !EngineIdentifiers.isPreviewOnly(engine.descriptor.id),
                  !seen.contains(engine.descriptor.id),
                  isCompatible(engine: engine, profile: profile),
                  engine.isAvailable else {
                return
            }
            seen.insert(engine.descriptor.id)
            ordered.append(engine)
        }

        if let selectedID,
           let selected = engines.first(where: {
               $0.descriptor.id == selectedID
           }) {
            append(selected)
        }
        for id in fallbackOrder {
            if let fallback = engines.first(where: {
                $0.descriptor.id == id
            }) {
                append(fallback)
            }
        }
        for engine in engines {
            append(engine)
        }
        return ordered
    }

    func isCompatible(
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
