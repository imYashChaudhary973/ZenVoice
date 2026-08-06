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
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [transcriber] in
                do {
                    let result = try transcriber.transcribe(
                        audioURL: audioURL,
                        languageProfile: languageProfile,
                        initialPrompt: initialPrompt
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous decode for live preview fragments.
    ///
    /// Callers that already serialize on this engine's queue can call this
    /// directly; otherwise use the async `transcribe(audioURL:languageProfile:)`.
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
