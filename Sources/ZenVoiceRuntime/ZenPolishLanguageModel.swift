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
import MLXLMCommon
import MLXLLM
import Tokenizers
import ZenVoiceCore
import os

/// Bridges swift-transformers' tokenizer to the loader MLXLMCommon expects.
/// mlx-swift-lm ships no production loader; the official docs leave this to
/// the consumer.
struct ZenPolishTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await Tokenizers.AutoTokenizer.from(
            modelFolder: directory
        )
        return ZenPolishTokenizerAdapter(tokenizer: tokenizer)
    }
}

struct ZenPolishTokenizerAdapter: MLXLMCommon.Tokenizer {
    private let tokenizer: any Tokenizers.Tokenizer

    init(tokenizer: any Tokenizers.Tokenizer) {
        self.tokenizer = tokenizer
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        tokenizer.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        tokenizer.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        tokenizer.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        tokenizer.convertIdToToken(id)
    }

    var bosToken: String? { tokenizer.bosToken }
    var eosToken: String? { tokenizer.eosToken }
    var unknownToken: String? { tokenizer.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try tokenizer.applyChatTemplate(
            messages: messages,
            tools: nil,
            additionalContext: additionalContext
        )
    }
}

/// ZenVoice's own fine-tuned dictation-enhancement model (ZenPolish v2,
/// fine-tuned from a Qwen3-1.7B base, 4-bit MLX). Loads from the verified
/// download under the
/// models directory and runs fully in-process: no network at inference time,
/// no child process.
public struct ZenPolishLanguageModel: LocalLanguageModel {
    public static let modelID = "zen-polish-v2-1.7b-4bit"
    public static let directoryName = "zen-polish-v2-1.7b-4bit"

    /// MUST stay byte-identical to `training/common.py` SYSTEM_PROMPT.
    /// Every fine-tuning pair was built with this exact string.
    public static let systemPrompt = """
    You clean up raw speech-to-text dictation. Fix punctuation and \
    capitalization, remove filler words and false restarts, and restore the \
    written forms of numbers, dates, times, money, URLs, and email \
    addresses. Keep the speaker's meaning and wording. If an 'app:' line is \
    given, match capitalization and tone to that context. Output only the \
    cleaned text, with no commentary.
    """

    /// Pinned bundle. Hashes and sizes must match the Hugging Face revision
    /// recorded in VerifiedModelCatalog.
    public static let files: [(name: String, sha256: String, sizeBytes: Int64)] = [
        (
            "config.json",
            "507a6701220524eb8b283425bf0856a9ae4f21f4052e563896ddd668994b1dc7",
            937
        ),
        (
            "model.safetensors",
            "cff3264565e97a3732a263e60c7e1beab1fd71c0a06972f02a4e4cb4734c0239",
            968_080_210
        ),
        (
            "model.safetensors.index.json",
            "b2e5b0437ba3dd97c262018713af2fea5c010a8a95d6e24ee6dd045f4cac8ce0",
            49_771
        ),
        (
            "tokenizer.json",
            "be75606093db2094d7cd20f3c2f385c212750648bd6ea4fb2bf507a6a4c55506",
            11_422_650
        ),
        (
            "tokenizer_config.json",
            "d93ac1a2c7adb9ad022f354d822f1f0f57e32e62ef2989e902782d6ab896acfe",
            413
        ),
        (
            "chat_template.jinja",
            "87a2728cb8dc9fe424d624542f6060ec05a1d285ebbec578bb078900e33396b5",
            4_116
        ),
    ]

    public static var bundleSizeBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }

    private let directory: URL?

    public init(modelsDirectory: URL?) {
        guard let modelsDirectory else {
            directory = nil
            return
        }
        directory = modelsDirectory.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
    }

    /// Convenience for local development: point directly at an unpacked
    /// model directory (used by runtime checks via ZENVOICE_MODEL_PATH).
    public init(directory: URL) {
        self.directory = directory
    }

    public var availability: LocalIntelligenceAvailability {
        guard let directory else {
            return .modelNotReady
        }
        for file in Self.files {
            // Download time verified hashes; this cheap size re-check
            // catches truncated or corrupted files without re-hashing on
            // every poll.
            let values = try? directory
                .appendingPathComponent(file.name)
                .resourceValues(forKeys: [.fileSizeKey])
            guard Int64(values?.fileSize ?? -1) == file.sizeBytes else {
                return .modelNotReady
            }
        }
        return .available
    }

    public func generate(
        prompt: String,
        maximumResponseTokens: Int
    ) async throws -> String {
        guard availability == .available, let directory else {
            throw LocalIntelligenceError.unavailable(.modelNotReady)
        }
        let output = try await ZenPolishRuntime.shared.respond(
            prompt: prompt,
            directory: directory,
            maximumTokens: maximumResponseTokens
        )
        guard !output.isEmpty else {
            throw LocalIntelligenceError.emptyResponse
        }
        return output
    }

    /// Preloads the weights so the first dictation does not pay the load.
    public func prepare() async {
        guard availability == .available, let directory else { return }
        _ = try? await ZenPolishRuntime.shared.respond(
            prompt: "hello",
            directory: directory,
            maximumTokens: 1
        )
    }
}

/// Caches the loaded container and drops it after five idle minutes,
/// matching the engine registry's memory discipline.
actor ZenPolishRuntime {
    static let shared = ZenPolishRuntime()

    private static let loadLogger = Logger(
        subsystem: "com.zenvoice.app",
        category: "ZenPolish"
    )

    private var container: ModelContainer?
    private var loadedDirectory: URL?
    private var unloadTask: Task<Void, Never>?

    func respond(
        prompt: String,
        directory: URL,
        maximumTokens: Int
    ) async throws -> String {
        unloadTask?.cancel()
        defer { scheduleUnload() }
        let container: ModelContainer
        do {
            container = try await preparedContainer(directory: directory)
        } catch {
            // Load failures are otherwise invisible: the caller surfaces a
            // generic unavailable error. One line, no prompt or transcript
            // content.
            Self.loadLogger.error(
                "ZenPolish model load failed: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
        // A fresh session per call: dictation requests are independent and
        // must not see each other's transcripts.
        let session = ChatSession(
            container,
            instructions: ZenPolishLanguageModel.systemPrompt,
            generateParameters: GenerateParameters(
                maxTokens: maximumTokens,
                temperature: 0
            ),
            additionalContext: ["enable_thinking": false]
        )
        let output = try await session.respond(to: prompt)
        return Self.stripReasoning(output)
    }

    private func preparedContainer(
        directory: URL
    ) async throws -> ModelContainer {
        if let container, loadedDirectory == directory {
            return container
        }
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: directory,
            using: ZenPolishTokenizerLoader()
        )
        container = loaded
        loadedDirectory = directory
        return loaded
    }

    private func scheduleUnload() {
        unloadTask?.cancel()
        unloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.unloadNow()
        }
    }

    func unloadNow() {
        container = nil
        loadedDirectory = nil
    }

    /// Qwen3 emits a reasoning block when the chat template defaults to
    /// thinking mode. Dictation output must never contain it. An
    /// unterminated block is dropped wholesale — from the opening tag to
    /// the end of the output — rather than letting reasoning text leak.
    static func stripReasoning(_ text: String) -> String {
        var output = text
        if let start = output.range(of: "<think>") {
            if let end = output.range(
                of: "</think>",
                range: start.upperBound..<output.endIndex
            ) {
                output.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                output.removeSubrange(start.lowerBound..<output.endIndex)
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
