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
import MLXASR
import ZenVoiceCore

/// Qwen3-ASR 0.6B (6-bit MLX) via `mlx-swift-asr`.
public final class Qwen3ASREngine: @unchecked Sendable, SpeechEngine {
    public static let engineID = EngineIdentifiers.qwen3ASR
    public static let directoryName = "qwen3-asr-0.6b-6bit"
    public static let requiredFiles = [
        "config.json",
        "model.safetensors",
        "vocab.json",
        "merges.txt",
        "tokenizer_config.json"
    ]

    public var descriptor: EngineDescriptor {
        EngineDescriptor(
            id: Self.engineID,
            displayName: "Qwen3-ASR 0.6B",
            family: .qwen3ASR,
            supportedLanguages: [],
            requiresDownload: true,
            requiresInternet: false,
            format: "MLX safetensors (6-bit)",
            publisher: "Qwen / Alibaba",
            license: "Apache-2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0.html",
            attribution:
                "Qwen3-ASR 0.6B by Qwen. 6-bit MLX conversion by "
                + "mlx-community. Runtime: mlx-swift-asr (MIT).",
            privacyNote:
                "Runs entirely on this Mac. No audio leaves the device."
        )
    }

    public var transformsSpokenLanguage: Bool { false }
    public var detectsLanguageAutomatically: Bool { true }
    public var languageCapability: ModelLanguageCapability { .multilingual }

    public var isAvailable: Bool {
        Self.isInstalled(in: modelsDirectory)
    }

    private let modelsDirectory: URL
    private var stt: Qwen3ASRSTT?

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    public static func isInstalled(in modelsDirectory: URL) -> Bool {
        let directory = modelsDirectory.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        return requiredFiles.allSatisfy { name in
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(name).path
            )
        }
    }

    public var modelDirectory: URL {
        modelsDirectory.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
    }

    public func prepare() async throws {
        if stt != nil { return }
        guard isAvailable else {
            throw EngineError.engineUnavailable(Self.engineID)
        }
        stt = try await Qwen3ASRSTT.loadWithWarmup(from: modelDirectory)
    }

    public func release() async {
        stt = nil
        Qwen3ASRSTT.flushMemoryPool()
    }

    public func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> ZenVoiceCore.TranscriptionResult {
        try await prepare()
        guard let stt else {
            throw EngineError.engineUnavailable(Self.engineID)
        }
        let samples = try AudioSampleLoader.load16kHzMonoFloatSamples(
            from: audioURL
        )
        let languageName: String?
        if languageProfile.inputLanguageCode == LanguageProfile.automaticCode {
            languageName = nil
        } else {
            languageName = LanguageCatalog.language(
                code: languageProfile.inputLanguageCode
            )?.displayName
        }
        let mlx = try await stt.transcribe(
            audio: samples,
            language: languageName,
            context: initialPrompt
        )
        return ZenVoiceCore.TranscriptionResult(
            rawTranscript: mlx.text,
            finalTranscript: mlx.text,
            correctionCount: 0,
            isPartial: false,
            modelID: Self.engineID,
            processingDurationSeconds: mlx.processingTime
        )
    }

}
