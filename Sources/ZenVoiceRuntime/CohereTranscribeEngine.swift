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
@preconcurrency import OnnxRuntimeBindings
import ZenVoiceCore

/// Cohere Transcribe via ONNX Runtime.
///
/// Uses the INT8 encoder/decoder ONNX export from
/// `cstr/cohere-transcribe-onnx-int8` on Hugging Face. The export takes raw
/// 16 kHz mono audio, runs a Conformer encoder, then autoregressively decodes
/// with a lightweight Transformer decoder and KV cache. This implementation
/// targets the `tokens.txt` tokenizer and the two-file (encoder + decoder)
/// INT8 release.
public final class CohereTranscribeEngine: @unchecked Sendable, SpeechEngine {
    public static let engineID = EngineIdentifiers.cohereTranscribe

    public static let encoderFilename = "cohere-encoder.int8.onnx"
    public static let encoderDataFilename = "cohere-encoder.int8.onnx.data"
    public static let decoderFilename = "cohere-decoder.int8.onnx"
    public static let decoderDataFilename = "cohere-decoder.int8.onnx.data"
    public static let tokenizerFilename = "tokens.txt"

    /// Languages supported by `CohereLabs/cohere-transcribe-03-2026`.
    private static let supportedLanguageCodes: Set<String> = [
        "en", "de", "fr", "it", "es", "pt", "nl", "pl", "el",
        "ar", "ja", "zh", "vi", "ko"
    ]

    public var descriptor: EngineDescriptor {
        EngineDescriptor(
            id: Self.engineID,
            displayName: "Cohere Transcribe",
            family: .cohereTranscribe,
            supportedLanguages: Self.supportedLanguageCodes.compactMap {
                LanguageCatalog.language(code: $0)
            },
            requiresDownload: true,
            requiresInternet: false,
            format: "ONNX INT8 (encoder-decoder)",
            publisher: "Cohere Labs",
            license: "Apache-2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0.html",
            attribution:
                "Cohere Transcribe 03-2026 by Cohere Labs. 2B parameter "
                + "Conformer encoder-decoder, 14 languages. INT8 ONNX export "
                + "by cstr/cohere-transcribe-onnx-int8. Runtime: ONNX Runtime.",
            privacyNote:
                "Runs entirely on this Mac. No audio leaves the device."
        )
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: encoderURL.path)
            && FileManager.default.fileExists(atPath: encoderDataURL.path)
            && FileManager.default.fileExists(atPath: decoderURL.path)
            && FileManager.default.fileExists(atPath: decoderDataURL.path)
            && FileManager.default.fileExists(atPath: tokenizerURL.path)
    }

    public var languageCapability: ModelLanguageCapability {
        .multilingual
    }

    private let modelsDirectory: URL
    private let encoderURL: URL
    private let encoderDataURL: URL
    private let decoderURL: URL
    private let decoderDataURL: URL
    private let tokenizerURL: URL
    private let queue: DispatchQueue
    private var tokenizer: CohereTokenizer?
    private var encoderSession: ORTSession?
    private var decoderSession: ORTSession?
    private var environment: ORTEnv?

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        self.encoderURL = modelsDirectory
            .appendingPathComponent(Self.encoderFilename, isDirectory: false)
        self.encoderDataURL = modelsDirectory
            .appendingPathComponent(Self.encoderDataFilename, isDirectory: false)
        self.decoderURL = modelsDirectory
            .appendingPathComponent(Self.decoderFilename, isDirectory: false)
        self.decoderDataURL = modelsDirectory
            .appendingPathComponent(Self.decoderDataFilename, isDirectory: false)
        self.tokenizerURL = modelsDirectory
            .appendingPathComponent(Self.tokenizerFilename, isDirectory: false)
        self.queue = DispatchQueue(
            label: "dev.yashchaudhary.ZenVoice.cohere",
            qos: .userInitiated
        )
    }

    /// Whether the sessions are currently resident.
    public var isLoaded: Bool {
        queue.sync { encoderSession != nil }
    }

    /// Frees the ONNX sessions. The next `transcribe` reloads on demand.
    ///
    /// Worth more here than anywhere else: the Cohere encoder alone is a
    /// 2.6 GB weights file.
    public func release() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.encoderSession = nil
                self?.decoderSession = nil
                self?.environment = nil
                continuation.resume()
            }
        }
    }

    /// Loads the sessions if needed and hands back strong references.
    ///
    /// Same reason as the other engines: load-if-nil and use have to happen
    /// together on `queue`, because idle unloading nils these properties from
    /// that queue. Reading them twice around an `await` let a dictation that
    /// started as the idle timer fired see loaded sessions and then nil ones,
    /// failing outright instead of reloading.
    private func loadedSessions() async throws
        -> (ORTSession, ORTSession, CohereTokenizer) {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<
                (ORTSession, ORTSession, CohereTokenizer), Error
            >) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(
                        throwing: CohereError.modelNotAvailable
                    )
                    return
                }
                do {
                    if self.encoderSession == nil
                        || self.decoderSession == nil
                        || self.tokenizer == nil {
                        try self.loadSessionsOnQueue()
                    }
                    guard let encoder = self.encoderSession,
                          let decoder = self.decoderSession,
                          let tokenizer = self.tokenizer else {
                        continuation.resume(
                            throwing: CohereError.modelNotAvailable
                        )
                        return
                    }
                    continuation.resume(
                        returning: (encoder, decoder, tokenizer)
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Builds the ONNX environment, both sessions, and the tokenizer.
    ///
    /// - Important: must run on `queue`. `prepare()` and `loadedSessions()`
    ///   both funnel here so there is one loading path rather than two that
    ///   can drift.
    private func loadSessionsOnQueue() throws {
        self.environment = try ORTEnv(
            loggingLevel: ORTLoggingLevel.warning
        )
        guard let environment = self.environment else {
            throw CohereError.environmentNotCreated
        }
        let sessionOptions = try ORTSessionOptions()
        // CoreML execution provider is disabled for this model
        // because ONNX Runtime 1.24.x has a known bug where the
        // CoreML EP resolves external data relative to the model
        // *file* path instead of the model *directory*, producing
        // ".../model.onnx/model.onnx.data: Not a directory". The
        // CPU provider loads the external `.onnx.data` files
        // correctly. Re-enable CoreML after upgrading to a release
        // that includes microsoft/onnxruntime#28062.
        //
        // if #available(macOS 14.0, *) {
        //     do {
        //         let coreMLOptions = ORTCoreMLExecutionProviderOptions()
        //         try sessionOptions.appendCoreMLExecutionProvider(
        //             with: coreMLOptions
        //         )
        //     } catch {
        //         // CoreML is optional; fall back to CPU.
        //     }
        // }
        self.encoderSession = try ORTSession(
            env: environment,
            modelPath: self.encoderURL.path,
            sessionOptions: sessionOptions
        )
        self.decoderSession = try ORTSession(
            env: environment,
            modelPath: self.decoderURL.path,
            sessionOptions: sessionOptions
        )
        self.tokenizer = try CohereTokenizer(
            contentsOf: self.tokenizerURL
        )
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
                    try self.loadSessionsOnQueue()
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
            throw CohereError.modelNotAvailable
        }
        let (encoderSession, decoderSession, tokenizer) =
            try await loadedSessions()

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<TranscriptionResult, Error>)
            in
            queue.async {
                do {
                    let startTime = Date()
                    let samples = try AudioSampleLoader
                        .load16kHzMonoFloatSamples(from: audioURL)
                    let normalized = CohereMelSpectrogram.normalize(samples)
                    let languageCode = Self.languageCode(
                        for: languageProfile
                    )
                    let transcript = try self.greedyDecode(
                        samples: normalized,
                        languageCode: languageCode,
                        encoderSession: encoderSession,
                        decoderSession: decoderSession,
                        tokenizer: tokenizer
                    )
                    let result = TranscriptionResult(
                        rawTranscript: transcript,
                        finalTranscript: transcript,
                        correctionCount: 0,
                        isPartial: false,
                        modelID: Self.engineID,
                        processingDurationSeconds: Date().timeIntervalSince(startTime)
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Decoding

    private func greedyDecode(
        samples: [Float],
        languageCode: String,
        encoderSession: ORTSession,
        decoderSession: ORTSession,
        tokenizer: CohereTokenizer
    ) throws -> String {
        let encoderOutputs = try runEncoder(
            samples: samples,
            session: encoderSession
        )
        guard let crossK = encoderOutputs["n_layer_cross_k"],
              let crossV = encoderOutputs["n_layer_cross_v"] else {
            throw CohereError.encoderOutputMissing
        }

        let nLayers = 8
        let heads = 8
        let headDim = 128
        let maxContext = 1024

        let promptTokens: [Int] = [
            tokenizer.id(for: "<|startofcontext|>") ?? 7,
            tokenizer.id(for: "<|startoftranscript|>") ?? 4,
            tokenizer.id(for: "<|emo:undefined|>") ?? 16,
            tokenizer.id(for: "<|\(languageCode)|>")
                ?? tokenizer.id(for: "<|en|>") ?? 25,
            tokenizer.id(for: "<|\(languageCode)|>")
                ?? tokenizer.id(for: "<|en|>") ?? 25,
            tokenizer.id(for: "<|pnc|>") ?? 5,
            tokenizer.id(for: "<|noitn|>") ?? 9,
            tokenizer.id(for: "<|notimestamp|>") ?? 11,
            tokenizer.id(for: "<|nodiarize|>") ?? 13
        ]

        var generated = promptTokens
        var selfKCache = [Float](
            repeating: 0,
            count: nLayers * 1 * heads * maxContext * headDim
        )
        var selfVCache = [Float](
            repeating: 0,
            count: nLayers * 1 * heads * maxContext * headDim
        )

        let endOfTextID = tokenizer.id(for: "<|endoftext|>") ?? 3
        let maxNewTokens = 256

        for step in 0..<maxNewTokens {
            let inputIDs: [Int]
            let offset: Int
            if step == 0 {
                inputIDs = generated
                offset = 0
            } else {
                inputIDs = [generated.last!]
                offset = generated.count - 1
            }
            let logits = try runDecoder(
                inputIDs: inputIDs,
                offset: offset,
                selfKCache: &selfKCache,
                selfVCache: &selfVCache,
                crossK: crossK,
                crossV: crossV,
                session: decoderSession,
                tokenizer: tokenizer
            )
            let nextID = argmax(logits)
            if nextID == endOfTextID {
                break
            }
            generated.append(nextID)
        }

        return tokenizer.decode(generated)
    }

    private func runEncoder(
        samples: [Float],
        session: ORTSession
    ) throws -> [String: ORTValue] {
        let shape: [NSNumber] = [1, NSNumber(value: samples.count)]
        let inputData = dataCopiedFromArray(samples)
        let inputTensor = try ORTValue(
            tensorData: NSMutableData(data: inputData),
            elementType: ORTTensorElementDataType.float,
            shape: shape
        )
        return try session.run(
            withInputs: ["audio": inputTensor],
            outputNames: Set(["n_layer_cross_k", "n_layer_cross_v"]),
            runOptions: nil
        )
    }

    private func runDecoder(
        inputIDs: [Int],
        offset: Int,
        selfKCache: inout [Float],
        selfVCache: inout [Float],
        crossK: ORTValue,
        crossV: ORTValue,
        session: ORTSession,
        tokenizer: CohereTokenizer
    ) throws -> [Float] {
        let inputShape: [NSNumber] = [1, NSNumber(value: inputIDs.count)]
        let inputData = dataCopiedFromInt64Array(inputIDs)
        let inputTensor = try ORTValue(
            tensorData: NSMutableData(data: inputData),
            elementType: ORTTensorElementDataType.int64,
            shape: inputShape
        )

        let selfKTensor = try ORTValue(
            tensorData: NSMutableData(data: dataCopiedFromArray(selfKCache)),
            elementType: ORTTensorElementDataType.float,
            shape: cacheShape()
        )
        let selfVTensor = try ORTValue(
            tensorData: NSMutableData(data: dataCopiedFromArray(selfVCache)),
            elementType: ORTTensorElementDataType.float,
            shape: cacheShape()
        )

        let offsetTensor = try ORTValue(
            tensorData: NSMutableData(data: dataCopiedFromInt64Array([offset])),
            elementType: ORTTensorElementDataType.int64,
            shape: []
        )

        let outputs = try session.run(
            withInputs: [
                "tokens": inputTensor,
                "in_n_layer_self_k_cache": selfKTensor,
                "in_n_layer_self_v_cache": selfVTensor,
                "n_layer_cross_k": crossK,
                "n_layer_cross_v": crossV,
                "offset": offsetTensor
            ],
            outputNames: Set([
                "logits",
                "out_n_layer_self_k_cache",
                "out_n_layer_self_v_cache"
            ]),
            runOptions: nil
        )

        guard let logitsValue = outputs["logits"],
              let newKValue = outputs["out_n_layer_self_k_cache"],
              let newVValue = outputs["out_n_layer_self_v_cache"] else {
            throw CohereError.decoderOutputMissing
        }

        let newKData = try newKValue.tensorData() as Data
        let newVData = try newVValue.tensorData() as Data
        selfKCache = newKData.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        selfVCache = newVData.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }

        let logitsData = try logitsValue.tensorData() as Data
        let allLogits = logitsData.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        let vocabSize = allLogits.count / inputIDs.count
        let start = (inputIDs.count - 1) * vocabSize
        return Array(allLogits[start..<start + vocabSize])
    }

    private func cacheShape() -> [NSNumber] {
        let nLayers = 8
        let heads = 8
        let headDim = 128
        let maxContext = 1024
        return [
            NSNumber(value: nLayers),
            1,
            NSNumber(value: heads),
            NSNumber(value: maxContext),
            NSNumber(value: headDim)
        ]
    }

    private static func languageCode(for profile: LanguageProfile) -> String {
        let code = profile.inputLanguageCode
        if supportedLanguageCodes.contains(code) {
            return code
        }
        return "en"
    }
}

private func argmax(_ values: [Float]) -> Int {
    guard !values.isEmpty else { return 0 }
    var bestIndex = 0
    var bestValue = values[0]
    for (index, value) in values.enumerated() {
        if value > bestValue {
            bestValue = value
            bestIndex = index
        }
    }
    return bestIndex
}

private func dataCopiedFromArray<T>(_ array: [T]) -> Data {
    array.withUnsafeBufferPointer { buffer -> Data in
        Data(buffer: buffer)
    }
}

private func dataCopiedFromIntArray(_ array: [Int]) -> Data {
    let int32Array = array.map { Int32($0) }
    return int32Array.withUnsafeBufferPointer { buffer -> Data in
        Data(buffer: buffer)
    }
}

private func dataCopiedFromInt64Array(_ array: [Int]) -> Data {
    let int64Array = array.map { Int64($0) }
    return int64Array.withUnsafeBufferPointer { buffer -> Data in
        Data(buffer: buffer)
    }
}

enum CohereError: LocalizedError {
    case environmentNotCreated
    case modelNotAvailable
    case encoderOutputMissing
    case decoderOutputMissing

    var errorDescription: String? {
        switch self {
        case .environmentNotCreated:
            return "ONNX Runtime environment could not be created."
        case .modelNotAvailable:
            return "Cohere Transcribe model files are not installed."
        case .encoderOutputMissing:
            return "Cohere encoder did not produce cross-attention keys."
        case .decoderOutputMissing:
            return "Cohere decoder did not produce logits or updated caches."
        }
    }
}
