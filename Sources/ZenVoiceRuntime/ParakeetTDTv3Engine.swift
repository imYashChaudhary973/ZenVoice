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

import AVFoundation
import Foundation
import ZenVoiceCore

/// Parakeet TDT v3 (multilingual) via parakeet.cpp.
///
/// Model weights are downloaded as a GGUF file into the shared `Models`
/// directory. The runtime is the vendored `parakeet.xcframework`, which uses
/// Metal on Apple Silicon and CPU on Intel.
public final class ParakeetTDTv3Engine: @unchecked Sendable, SpeechEngine {
    public static let engineID = EngineIdentifiers.parakeetTDTv3

    /// Expected GGUF filename in the Models directory.
    public static let modelFilename = "tdt-0.6b-v3-q8_0.gguf"

    public var descriptor: EngineDescriptor {
        EngineDescriptor(
            id: Self.engineID,
            displayName: "Parakeet TDT v3",
            family: .parakeetTDT,
            supportedLanguages: [],
            requiresDownload: true,
            requiresInternet: false,
            format: "GGUF (parakeet.cpp v0.5.0)",
            publisher: "NVIDIA",
            license: "CC-BY-4.0",
            licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            attribution:
                "Parakeet TDT 0.6B v3 by NVIDIA. Runtime: parakeet.cpp "
                + "v0.5.0 (MIT) by Ettore Di Giacinto / LocalAI.",
            privacyNote:
                "Runs entirely on this Mac. No audio leaves the device."
        )
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    public var languageCapability: ModelLanguageCapability {
        .multilingual
    }

    private let modelURL: URL
    private var context: ParakeetContext?
    private let queue: DispatchQueue

    public init(modelURL: URL) {
        self.modelURL = modelURL
        self.queue = DispatchQueue(
            label: "dev.yashchaudhary.ZenVoice.parakeet-tdt-v3",
            qos: .userInitiated
        )
    }

    /// Whether the model is currently resident.
    public var isLoaded: Bool {
        queue.sync { context != nil }
    }

    /// Frees the loaded model. The next `transcribe` reloads on demand.
    ///
    /// Without this the idle unload only reclaimed Whisper, and whichever
    /// engine the user had actually selected stayed resident forever.
    public func release() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.context = nil
                continuation.resume()
            }
        }
    }

    /// Loads the model if needed and hands back a strong reference to it.
    ///
    /// Load-if-nil and use must happen together on `queue`, and the caller must
    /// hold the returned object rather than re-reading `context`. Idle
    /// unloading nils that property from the same queue, so the old
    /// `if context == nil { prepare() }` / `guard let context` pair had a
    /// window between its two reads: a dictation starting exactly as the idle
    /// timer fired saw a loaded engine, then a nil one, and failed with
    /// "no engine available" instead of reloading. A strong reference also
    /// keeps the underlying context alive for the duration of a decode that is
    /// already running when `release()` lands — it is freed on deinit, not on
    /// the property going nil.
    private func loadedContext() async throws -> ParakeetContext {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<ParakeetContext, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(
                        throwing: EngineError.noEngineAvailable
                    )
                    return
                }
                do {
                    if self.context == nil {
                        self.context = try ParakeetContext(
                            modelPath: self.modelURL.path
                        )
                    }
                    guard let context = self.context else {
                        continuation.resume(
                            throwing: EngineError.noEngineAvailable
                        )
                        return
                    }
                    continuation.resume(returning: context)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func prepare() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                do {
                    self.context = try ParakeetContext(
                        modelPath: self.modelURL.path
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        guard isAvailable else {
            throw EngineError.noEngineAvailable
        }
        let context = try await loadedContext()

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<TranscriptionResult, Error>)
            in
            queue.async {
                do {
                    let transcript = try context.transcribe(
                        url: audioURL,
                        languageCode: Self.targetLanguageCode(
                            for: languageProfile
                        )
                    )
                    let result = TranscriptionResult(
                        rawTranscript: transcript,
                        finalTranscript: transcript,
                        correctionCount: 0,
                        isPartial: false,
                        modelID: Self.engineID,
                        processingDurationSeconds: 0
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func targetLanguageCode(
        for profile: LanguageProfile
    ) -> String? {
        let code = profile.inputLanguageCode
        if code == LanguageProfile.automaticCode {
            return nil
        }
        return code
    }
}
