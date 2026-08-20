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
import ZenVoiceCore
import whisper

/// Whisper.cpp wrapped as a `SpeechEngine`.
///
/// This type keeps the low-level `WhisperTranscriber` as a plain wrapper and
/// adds the engine protocol on top. Model discovery, verification, and language
/// compatibility remain in `ZenVoiceConfiguration`.
public final class WhisperSpeechEngine: @unchecked Sendable, SpeechEngine {
    public static let engineID = EngineIdentifiers.whisper

    public var descriptor: EngineDescriptor {
        EngineDescriptor(
            id: Self.engineID,
            displayName: "Whisper",
            family: .whisper,
            supportedLanguages: [],
            requiresDownload: true,
            requiresInternet: false,
            format: "whisper.cpp GGML",
            publisher: "ggml-org / Georgi Gerganov",
            license: "MIT",
            licenseURL:
                "https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE",
            attribution: "OpenAI Whisper weights converted for whisper.cpp "
                + "by ggml-org.",
            privacyNote: "Runs entirely on this Mac. No audio leaves the device."
        )
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: configuration.modelURL.path)
    }

    public var modelID: String {
        configuration.modelID
    }

    public var languageCapability: ModelLanguageCapability {
        configuration.modelLanguageCapability
    }

    private let configuration: ZenVoiceConfiguration
    public let transcriber: WhisperTranscriber
    private let queue: DispatchQueue

    public init(configuration: ZenVoiceConfiguration) {
        self.configuration = configuration
        self.transcriber = WhisperTranscriber(configuration: configuration)
        self.queue = DispatchQueue(
            label: "dev.yashchaudhary.ZenVoice.whisper-\(configuration.modelID)",
            qos: .userInitiated
        )
    }

    /// Whether the model is currently resident.
    public var isLoaded: Bool {
        transcriber.isLoaded
    }

    public func release() async {
        // On the engine's own serial queue, matching `prepare()`. The
        // transcriber additionally waits out any decode started from
        // elsewhere before it frees anything.
        await withCheckedContinuation { continuation in
            queue.async { [transcriber] in
                transcriber.unload()
                continuation.resume()
            }
        }
    }

    public func prepare() async throws {
        // Warm-up touches the unguarded whisper context, so it must run on the
        // engine's own serial queue.
        await withCheckedContinuation { continuation in
            queue.async { [transcriber] in
                transcriber.warmUp()
                continuation.resume()
            }
        }
    }

    public func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        let cancellation = WhisperCancellationToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [transcriber] in
                    do {
                        guard !cancellation.isCancelled else {
                            throw CancellationError()
                        }
                        let result = try transcriber.transcribe(
                            audioURL: audioURL,
                            languageProfile: languageProfile,
                            initialPrompt: initialPrompt,
                            cancellation: cancellation
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// Queued decode of in-memory samples, for live preview fragments.
    ///
    /// Hops to the engine's serial queue like every other decode, so a
    /// preview fragment can never run whisper_full concurrently with a final
    /// whole-recording decode on the same context.
    public func enqueuePreview(
        samples: [Float],
        languageProfile: LanguageProfile,
        initialPrompt: String? = nil
    ) async throws -> TranscriptionResult {
        let cancellation = WhisperCancellationToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [transcriber] in
                    do {
                        guard !cancellation.isCancelled else {
                            throw CancellationError()
                        }
                        let result = try transcriber.transcribe(
                            samples: samples,
                            languageProfile: languageProfile,
                            initialPrompt: initialPrompt,
                            cancellation: cancellation
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// Synchronous decode for callers already serialized on this engine's
    /// queue. Anything else must use the queued variants above.
    public func transcribe(
        samples: [Float],
        languageProfile: LanguageProfile,
        initialPrompt: String? = nil
    ) throws -> TranscriptionResult {
        try transcriber.transcribe(
            samples: samples,
            languageProfile: languageProfile,
            initialPrompt: initialPrompt
        )
    }
}
