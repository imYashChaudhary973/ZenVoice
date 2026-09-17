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
///
/// An actor because the loaded `Qwen3ASRSTT` is mutable MLX state that
/// `prepare`, `release`, and `transcribe` all touch from arbitrary tasks;
/// actor isolation gives the load-release-use sequence a single serialized
/// owner where a plain `@unchecked Sendable` class raced on all three.
public actor Qwen3ASREngine: SpeechEngine {
    public static let engineID = EngineIdentifiers.qwen3ASR
    public static let directoryName = "qwen3-asr-0.6b-6bit"

    nonisolated public var descriptor: EngineDescriptor {
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

    nonisolated public var transformsSpokenLanguage: Bool { false }
    nonisolated public var detectsLanguageAutomatically: Bool { true }
    nonisolated public var languageCapability: ModelLanguageCapability {
        .multilingual
    }

    nonisolated public var isAvailable: Bool {
        Self.isInstalled(in: modelsDirectory)
    }

    private let modelsDirectory: URL
    private var stt: Qwen3ASRSTT?
    private var loadTask: Task<Qwen3ASRSTT, Error>?
    /// Bumped by every `release()` so a load that finishes after its release
    /// cannot adopt the model back into `stt`.
    private var loadGeneration = 0
    /// Number of `transcribe` calls currently past `preparedSTT()`.
    private var transcribesInFlight = 0

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    public static func isInstalled(in modelsDirectory: URL) -> Bool {
        // Download time verified hashes; this cheap size re-check catches
        // truncated or corrupted files without re-hashing on every poll.
        let sizes: [(String, Int64)] = [
            ("config.json", VerifiedEngineCatalog.qwen3ConfigSizeBytes),
            ("model.safetensors", VerifiedEngineCatalog.qwen3WeightsSizeBytes),
            ("vocab.json", VerifiedEngineCatalog.qwen3VocabSizeBytes),
            ("merges.txt", VerifiedEngineCatalog.qwen3MergesSizeBytes),
            (
                "tokenizer_config.json",
                VerifiedEngineCatalog.qwen3TokenizerConfigSizeBytes
            ),
        ]
        let directory = modelsDirectory.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        return sizes.allSatisfy { name, expectedBytes in
            let values = try? directory
                .appendingPathComponent(name)
                .resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? -1) == expectedBytes
        }
    }

    public var modelDirectory: URL {
        modelsDirectory.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
    }

    public func prepare() async throws {
        _ = try await preparedSTT()
    }

    public func release() async {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        stt = nil
        // The pool is process-global: flushing while another transcription
        // is mid-flight could free buffers it is still using, so defer the
        // flush to the next release.
        guard transcribesInFlight == 0 else { return }
        Qwen3ASRSTT.flushMemoryPool()
    }

    /// The resident model, loading it first when needed.
    ///
    /// `loadTask` deduplicates concurrent prepares into one load, and the
    /// generation check keeps a load that outlived its `release()` from
    /// repopulating `stt`.
    private func preparedSTT() async throws -> Qwen3ASRSTT {
        if let stt { return stt }
        if let loadTask {
            return try await loadTask.value
        }
        guard isAvailable else {
            throw EngineError.engineUnavailable(Self.engineID)
        }
        loadGeneration += 1
        let generation = loadGeneration
        let task = Task {
            try await Qwen3ASRSTT.loadWithWarmup(from: modelDirectory)
        }
        loadTask = task
        do {
            let loaded = try await task.value
            guard generation == loadGeneration else {
                // release() ran while the load was in flight. Respect it and
                // hand this caller the model without caching it; the next
                // idle unload or release clears it again.
                return loaded
            }
            stt = loaded
            loadTask = nil
            return loaded
        } catch {
            if generation == loadGeneration {
                loadTask = nil
            }
            throw error
        }
    }

    public func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> ZenVoiceCore.TranscriptionResult {
        let stt = try await preparedSTT()
        transcribesInFlight += 1
        defer { transcribesInFlight -= 1 }
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
