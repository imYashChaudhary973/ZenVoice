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

/// Provenance metadata for a speech engine.
///
/// Unlike ``VerifiedModel``, an engine may have no downloadable file at all
/// or may have a runtime package that is not itself a model weight. This
/// structure records whatever can be verified: publisher, licence, revision,
/// checksum, and download source.
public struct VerifiedEngine: Equatable, Sendable {
    public let descriptor: EngineDescriptor
    public let runtimeIdentifier: String
    public let sourceRepository: String?
    public let sourceRevision: String?
    public let downloadURL: URL?
    public let sha256: String?
    public let fileSizeBytes: Int64?

    public init(
        descriptor: EngineDescriptor,
        runtimeIdentifier: String,
        sourceRepository: String? = nil,
        sourceRevision: String? = nil,
        downloadURL: URL? = nil,
        sha256: String? = nil,
        fileSizeBytes: Int64? = nil
    ) {
        self.descriptor = descriptor
        self.runtimeIdentifier = runtimeIdentifier
        self.sourceRepository = sourceRepository
        self.sourceRevision = sourceRevision
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.fileSizeBytes = fileSizeBytes
    }

    /// Hugging Face model this engine loads, e.g. `nvidia/parakeet-tdt-0.6b-v3`.
    public var wrappedModelID: String? {
        guard let sourceRepository,
              let url = URL(string: sourceRepository),
              url.host() == "huggingface.co",
              url.pathComponents.count >= 3
        else {
            return nil
        }
        // pathComponents starts with "/", so this is the org/model path.
        return url.pathComponents[1...].joined(separator: "/")
    }

    public var downloadFilename: String? {
        downloadURL?.lastPathComponent
    }
}

/// Catalogue of every engine ZenVoice knows about, offered or reserved.
public enum VerifiedEngineCatalog {
    public static let engines: [VerifiedEngine] = [
        appleSpeech(),
        qwen3ASR(),
        nemotronSpeech(),
        parakeetTDTv3(),
        parakeetTDTv2(),
        cohereTranscribe()
    ] + VerifiedModelCatalog.models.map(whisperEngine)

    public static let cohereEncoderFilename = "cohere-encoder.int8.onnx"
    public static let cohereDecoderFilename = "cohere-decoder.int8.onnx"
    public static let cohereTokenizerFilename = "tokens.txt"
    public static let cohereEncoderDataFilename =
        "cohere-encoder.int8.onnx.data"
    public static let cohereDecoderDataFilename =
        "cohere-decoder.int8.onnx.data"
    public static let cohereEncoderSHA256 =
        "27ef3d3a2352c972fa4831ae680d52937a2d4e5d62910060f140b13e2f4ccd2b"
    public static let cohereEncoderSizeBytes: Int64 = 6_164_263
    public static let cohereDecoderSHA256 =
        "4be3bdfe855b751985dd2b53d39cca66967bdcb656a138753daf12c451900358"
    public static let cohereDecoderSizeBytes: Int64 = 530_119
    public static let cohereTokenizerSHA256 =
        "013ede043ae2480e3a9205cc34550d9686100cc682bacc90f702facdfbb93035"
    public static let cohereTokenizerSizeBytes: Int64 = 207_437
    public static let cohereEncoderDataSHA256 =
        "0a6ebd1efbaeef6d15106e33671ce73067cad862bbb20f5e2dfbcd56695fbb76"
    public static let cohereEncoderDataSizeBytes: Int64 = 2_839_314_432
    public static let cohereDecoderDataSHA256 =
        "8e4d5d7ea5092cf0779b711c65dfef9ecd2b88df951c6c7aa334df345c2eb4d8"
    public static let cohereDecoderDataSizeBytes: Int64 = 222_937_088
    public static let cohereBundleSizeBytes: Int64 =
        cohereEncoderSizeBytes
        + cohereEncoderDataSizeBytes
        + cohereDecoderSizeBytes
        + cohereDecoderDataSizeBytes
        + cohereTokenizerSizeBytes
    public static let qwen3DirectoryName = "qwen3-asr-0.6b-6bit"
    public static let qwen3WeightsFilename = "model.safetensors"
    public static let qwen3WeightsSHA256 =
        "1df8abe1df012cf60cbf953acb9e2515ea1d1ac081ca09b5f6c1d6c9538c8d0c"
    public static let qwen3WeightsSizeBytes: Int64 = 857_233_233
    public static let qwen3ConfigSHA256 =
        "81c21f975d386f859328045dc963e2de04ac6a55f0cdcca24e691a361cf29e3e"
    public static let qwen3ConfigSizeBytes: Int64 = 7_187
    public static let qwen3TokenizerConfigSHA256 =
        "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"
    public static let qwen3TokenizerConfigSizeBytes: Int64 = 12_487
    public static let qwen3VocabSHA256 =
        "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
    public static let qwen3VocabSizeBytes: Int64 = 2_776_833
    public static let qwen3MergesSHA256 =
        "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
    public static let qwen3MergesSizeBytes: Int64 = 1_671_853
    public static let qwen3BundleSizeBytes: Int64 =
        qwen3WeightsSizeBytes
        + qwen3ConfigSizeBytes
        + qwen3TokenizerConfigSizeBytes
        + qwen3VocabSizeBytes
        + qwen3MergesSizeBytes

    public static let reservedEngines: [VerifiedEngine] = []

    public static var allEngines: [VerifiedEngine] {
        engines + reservedEngines
    }

    public static func engine(id: String) -> VerifiedEngine? {
        let id = EngineIdentifiers.canonical(id)
        return allEngines.first { $0.descriptor.id == id }
    }

    private static func whisperEngine(_ model: VerifiedModel) -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: model.id,
                displayName: model.displayName,
                family: .whisper,
                supportedLanguages: [],
                requiresDownload: true,
                requiresInternet: false,
                format: model.format,
                publisher: model.publisher,
                license: model.license,
                licenseURL: model.licenseURL,
                attribution: model.attribution,
                privacyNote:
                    "On-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "whisper.cpp.\(model.id)",
            sourceRepository: model.sourceRepository,
            sourceRevision: model.sourceRevision,
            downloadURL: model.downloadURL,
            sha256: model.sha256,
            fileSizeBytes: model.fileSizeBytes
        )
    }

    private static func appleSpeech() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: EngineIdentifiers.appleSpeech,
                displayName: "Apple Speech Analyzer",
                family: .appleSpeech,
                supportedLanguages: [],
                requiresDownload: false,
                requiresInternet: false,
                format: "SpeechAnalyzer (on-device)",
                publisher: "Apple",
                license: "Apple Software License",
                licenseURL:
                    "https://www.apple.com/legal/sla/docs/macOSSonoma.pdf",
                attribution:
                    "On-device speech recognition provided by Apple Speech "
                    + "framework on macOS.",
                privacyNote:
                    "Built into macOS. Nothing to download. Audio stays on this Mac."
            ),
            runtimeIdentifier: "apple.speech.on-device"
        )
    }

    private static func parakeetTDTv3() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: EngineIdentifiers.parakeetTDTv3,
                displayName: "NVIDIA Parakeet TDT 0.6B V3",
                family: .parakeetTDT,
                supportedLanguages: LanguageProfile.parakeetTDTv3Languages,
                requiresDownload: true,
                requiresInternet: false,
                format: "GGUF (parakeet.cpp v0.5.0)",
                publisher: "NVIDIA",
                license: "CC-BY-4.0",
                licenseURL: "https://creativecommons.org/licenses/by/4.0/",
                attribution:
                    "Parakeet TDT 0.6B v3 by NVIDIA. Multilingual (25 "
                    + "European languages). Runtime: parakeet.cpp (MIT) v0.5.0 "
                    + "with Metal on Apple Silicon and CPU fallback on Intel.",
                privacyNote:
                    "On-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.parakeet.tdt.v3",
            sourceRepository:
                "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3",
            sourceRevision: "main",
            downloadURL: URL(
                string:
                    "https://huggingface.co/mudler/parakeet-cpp-gguf/"
                    + "resolve/main/tdt-0.6b-v3-q8_0.gguf?download=true"
            ),
            sha256:
                "4d69a4a6683f4f2d952bad794c1357ca6eb628027695b4699c5a9ad4cd07d757",
            fileSizeBytes: 940_663_680
        )
    }

    private static func parakeetTDTv2() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: EngineIdentifiers.parakeetTDTv2,
                displayName: "NVIDIA Parakeet TDT 0.6B V2",
                family: .parakeetTDT,
                supportedLanguages: LanguageCatalog.language(code: "en").map { [$0] } ?? [],
                requiresDownload: true,
                requiresInternet: false,
                format: "GGUF (parakeet.cpp v0.5.0)",
                publisher: "NVIDIA",
                license: "CC-BY-4.0",
                licenseURL: "https://creativecommons.org/licenses/by/4.0/",
                attribution:
                    "Parakeet TDT 0.6B v2 by NVIDIA. English-only. Runtime: "
                    + "parakeet.cpp (MIT) v0.5.0.",
                privacyNote:
                    "On-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.parakeet.tdt.v2",
            sourceRepository:
                "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2",
            sourceRevision: "main",
            downloadURL: URL(
                string:
                    "https://huggingface.co/mudler/parakeet-cpp-gguf/"
                    + "resolve/main/tdt-0.6b-v2-q8_0.gguf?download=true"
            ),
            sha256:
                "2027e2e1a4dc60ccdd8558f93b15e7c0db4ef8895b4e82e889f3a6275d8119c6",
            fileSizeBytes: 903_835_936
        )
    }

    private static func nemotronSpeech() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: EngineIdentifiers.nemotronSpeech,
                displayName: "NVIDIA Nemotron 3.5 Multilingual 0.6B",
                family: .nemotronSpeech,
                supportedLanguages: [
                    "en", "es", "fr", "de", "zh", "ja", "ko", "pt"
                ].compactMap(LanguageCatalog.language(code:)),
                requiresDownload: true,
                requiresInternet: false,
                format: "GGUF (parakeet.cpp v0.5.0)",
                publisher: "NVIDIA",
                license: "OpenMDW-1.1",
                licenseURL: "https://openmdw.ai/license/1-1/",
                attribution:
                    "Nemotron 3.5 ASR Streaming 0.6B by NVIDIA. Runtime: "
                    + "parakeet.cpp v0.5.0 (MIT).",
                privacyNote:
                    "On-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.nemotron.speech.0.6b",
            sourceRepository:
                "https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b",
            sourceRevision: "main",
            downloadURL: URL(
                string:
                    "https://huggingface.co/mudler/parakeet-cpp-gguf/"
                    + "resolve/main/"
                    + "nemotron-3.5-asr-streaming-0.6b-q8_0.gguf?download=true"
            ),
            sha256:
                "ba2f13eccd4a5245be728f77e6149bd6a4fdcdd133ff2e08ac6005bcef7a99f1",
            fileSizeBytes: 983_696_512
        )
    }

    private static func cohereTranscribe() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: EngineIdentifiers.cohereTranscribe,
                displayName: "Cohere Transcribe",
                family: .cohereTranscribe,
                supportedLanguages: [
                    "en", "de", "fr", "it", "es", "pt", "nl", "pl", "el",
                    "ar", "ja", "zh", "vi", "ko"
                ].compactMap(LanguageCatalog.language(code:)),
                requiresDownload: true,
                requiresInternet: false,
                format: "ONNX INT8 (encoder-decoder)",
                publisher: "Cohere Labs",
                license: "Apache-2.0",
                licenseURL: "https://www.apache.org/licenses/LICENSE-2.0.html",
                attribution:
                    "Cohere Transcribe 03-2026 by Cohere Labs. 2B parameter "
                    + "Conformer encoder-decoder, 14 languages. INT8 ONNX "
                    + "export by cstr/cohere-transcribe-onnx-int8.",
                privacyNote:
                    "On-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "cohere.transcribe.onnx",
            sourceRepository:
                "https://huggingface.co/cstr/cohere-transcribe-onnx-int8",
            sourceRevision: "main",
            // This engine is a five-file bundle (see the cohere* constants).
            // downloadURL + sha256 verify only the primary encoder file; the
            // remaining files are verified file-by-file at download time and
            // the full layout is asserted when the engine is loaded.
            downloadURL: URL(
                string:
                    "https://huggingface.co/cstr/cohere-transcribe-onnx-int8/"
                    + "resolve/main/cohere-encoder.int8.onnx?download=true"
            ),
            sha256: cohereEncoderSHA256,
            fileSizeBytes: cohereBundleSizeBytes
        )
    }

    private static func qwen3ASR() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: EngineIdentifiers.qwen3ASR,
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
                    "On-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "qwen.qwen3.asr.0.6b",
            sourceRepository:
                "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-6bit",
            sourceRevision: "main",
            // This engine is a five-file bundle (see the qwen3* constants).
            // downloadURL + sha256 verify only the weights file; the
            // remaining files are verified file-by-file at download time and
            // the full layout is asserted when the engine is loaded.
            downloadURL: URL(
                string:
                    "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-6bit/"
                    + "resolve/main/model.safetensors?download=true"
            ),
            sha256: qwen3WeightsSHA256,
            fileSizeBytes: qwen3BundleSizeBytes
        )
    }


}
