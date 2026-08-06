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
/// (Apple Speech) or may have a runtime package that is not itself a model
/// weight. This structure records whatever can be verified: publisher, licence,
/// revision, checksum, and download source.
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
}

/// Catalogue of every engine ZenVoice knows about, offered or reserved.
///
/// Reserved entries keep the schema stable for later phases. They are not
/// shown in the UI as available, but their descriptors, licences, and provenance
/// are recorded here so the roadmap has a single source of truth.
public enum VerifiedEngineCatalog {
    /// Engines that can be selected in Phase 1 and Phase 2a.
    public static let engines: [VerifiedEngine] = [
        appleSpeech(),
        parakeetFlash(),
        parakeetTDTv2(),
        parakeetTDTv3(),
        nemotronSpeechUltraFast(),
        nemotronSpeechMultilingual(),
        cohereTranscribe()
    ]

    /// Engines planned for later phases. Their IDs and families are fixed so
    /// Phase 2/3/5 code can refer to them without changing this file.
    public static let reservedEngines: [VerifiedEngine] = []

    /// GGUF filename shared by both Nemotron engine entries.
    public static let nemotronModelFilename =
        "nemotron-3.5-asr-streaming-0.6b-q8_0.gguf"
    public static let cohereEncoderFilename =
        "cohere-encoder.int8.onnx"
    public static let cohereDecoderFilename =
        "cohere-decoder.int8.onnx"
    public static let cohereTokenizerFilename =
        "tokens.txt"
    public static let cohereEncoderSHA256 =
        "27ef3d3a2352c972fa4831ae680d52937a2d4e5d62910060f140b13e2f4ccd2b"
    public static let cohereEncoderSizeBytes: Int64 = 6_164_263
    public static let cohereDecoderSHA256 =
        "4be3bdfe855b751985dd2b53d39cca66967bdcb656a138753daf12c451900358"
    public static let cohereDecoderSizeBytes: Int64 = 530_119
    public static let cohereTokenizerSHA256 =
        "013ede043ae2480e3a9205cc34550d9686100cc682bacc90f702facdfbb93035"
    public static let cohereTokenizerSizeBytes: Int64 = 207_437
    public static let cohereEncoderDataFilename =
        "cohere-encoder.int8.onnx.data"
    public static let cohereEncoderDataSHA256 =
        "0a6ebd1efbaeef6d15106e33671ce73067cad862bbb20f5e2dfbcd56695fbb76"
    public static let cohereEncoderDataSizeBytes: Int64 = 2_839_314_432
    public static let cohereDecoderDataFilename =
        "cohere-decoder.int8.onnx.data"
    public static let cohereDecoderDataSHA256 =
        "8e4d5d7ea5092cf0779b711c65dfef9ecd2b88df951c6c7aa334df345c2eb4d8"
    public static let cohereDecoderDataSizeBytes: Int64 = 222_937_088
    public static let cohereBundleSizeBytes: Int64 =
        cohereEncoderSizeBytes
            + cohereEncoderDataSizeBytes
            + cohereDecoderSizeBytes
            + cohereDecoderDataSizeBytes
            + cohereTokenizerSizeBytes

    /// Everything, offered or reserved.
    public static var allEngines: [VerifiedEngine] {
        engines + reservedEngines
    }

    public static func engine(id: String) -> VerifiedEngine? {
        allEngines.first { $0.descriptor.id == id }
    }

    private static func appleSpeech() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: "apple-speech",
                displayName: "Apple Speech",
                family: .appleSpeech,
                supportedLanguages: LanguageCatalog.languages,
                requiresDownload: false,
                requiresInternet: false,
                format: "SFSpeechRecognizer (on-device)",
                publisher: "Apple",
                license: "Apple Software License",
                licenseURL:
                    "https://www.apple.com/legal/sla/docs/macOSSonoma.pdf",
                attribution:
                    "On-device speech recognition provided by Apple Speech "
                    + "framework on macOS.",
                privacyNote:
                    "Audio is processed on this Mac. Nothing is sent to Apple."
            ),
            runtimeIdentifier: "com.apple.speech.SFSpeechRecognizer",
            sourceRepository: nil,
            sourceRevision: nil,
            downloadURL: nil,
            sha256: nil,
            fileSizeBytes: nil
        )
    }

    private static func parakeetTDTv2() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: "parakeet-tdt-v2",
                displayName: "Parakeet TDT v2",
                family: .parakeetTDT,
                supportedLanguages: [],
                requiresDownload: true,
                requiresInternet: false,
                format: "GGUF (parakeet.cpp v0.5.0)",
                publisher: "NVIDIA",
                license: "CC-BY-4.0",
                licenseURL: "https://creativecommons.org/licenses/by/4.0/",
                attribution:
                    "Parakeet TDT 0.6B v2 by NVIDIA. English-only. Runtime: "
                    + "parakeet.cpp v0.5.0 (MIT) by Ettore Di Giacinto / LocalAI.",
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

    private static func parakeetTDTv3() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: "parakeet-tdt-v3",
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

    private static func parakeetFlash() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: "parakeet-flash",
                displayName: "Parakeet Flash (Beta)",
                family: .parakeetFlash,
                supportedLanguages: [],
                requiresDownload: true,
                requiresInternet: false,
                format: "GGUF (parakeet.cpp v0.5.0, streaming)",
                publisher: "NVIDIA",
                license: "CC-BY-4.0",
                licenseURL: "https://creativecommons.org/licenses/by/4.0/",
                attribution:
                    "Parakeet Realtime EOU 120M v1 by NVIDIA. Cache-aware "
                    + "streaming model. Runtime: parakeet.cpp v0.5.0 (MIT) by "
                    + "Ettore Di Giacinto / LocalAI.",
                privacyNote:
                    "On-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.parakeet.flash",
            sourceRepository:
                "https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1",
            sourceRevision: "main",
            downloadURL: URL(
                string:
                    "https://huggingface.co/mudler/parakeet-cpp-gguf/"
                    + "resolve/main/realtime_eou_120m-v1-q8_0.gguf?download=true"
            ),
            sha256:
                "62616b914d6f5a683a5dea672df055b57de5c49dddf871b8b44b9c814dc3d896",
            fileSizeBytes: 176_001_472
        )
    }

    private static func nemotronSpeechUltraFast() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: "nemotron-speech-ultra-fast",
                displayName: "Nemotron Speech 3.5 Ultra Fast",
                family: .nemotronSpeech,
                supportedLanguages: [],
                requiresDownload: true,
                requiresInternet: false,
                format: "GGUF (parakeet.cpp v0.5.0, streaming)",
                publisher: "NVIDIA",
                license: "OpenMDW-1.1",
                licenseURL: "https://openmdw.ai/license/1-1/",
                attribution:
                    "Nemotron 3.5 ASR Streaming 0.6B by NVIDIA. Cache-aware "
                    + "streaming model with 40 locales. Runtime: parakeet.cpp "
                    + "v0.5.0 (MIT) by Ettore Di Giacinto / LocalAI.",
                privacyNote:
                    "On-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.nemotron.speech.ultra.fast",
            sourceRepository:
                "https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b",
            sourceRevision: "main",
            downloadURL: URL(
                string:
                    "https://huggingface.co/mudler/parakeet-cpp-gguf/"
                    + "resolve/main/nemotron-3.5-asr-streaming-0.6b-q8_0.gguf"
                    + "?download=true"
            ),
            sha256:
                "ba2f13eccd4a5245be728f77e6149bd6a4fdcdd133ff2e08ac6005bcef7a99f1",
            fileSizeBytes: 983_696_512
        )
    }

    private static func nemotronSpeechMultilingual() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: "nemotron-speech-multilingual",
                displayName: "Nemotron 3.5 Multilingual",
                family: .nemotronSpeech,
                supportedLanguages: [],
                requiresDownload: true,
                requiresInternet: false,
                format: "GGUF (parakeet.cpp v0.5.0)",
                publisher: "NVIDIA",
                license: "OpenMDW-1.1",
                licenseURL: "https://openmdw.ai/license/1-1/",
                attribution:
                    "Same upstream checkpoint as Nemotron Speech 3.5 Ultra Fast "
                    + "(nvidia/nemotron-3.5-asr-streaming-0.6b), run in "
                    + "offline/whole-file mode for 40-locale multilingual "
                    + "transcription. Runtime: parakeet.cpp v0.5.0 (MIT) by "
                    + "Ettore Di Giacinto / LocalAI.",
                privacyNote:
                    "On-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.nemotron.speech.multilingual",
            sourceRepository:
                "https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b",
            sourceRevision: "main",
            downloadURL: URL(
                string:
                    "https://huggingface.co/mudler/parakeet-cpp-gguf/"
                    + "resolve/main/nemotron-3.5-asr-streaming-0.6b-q8_0.gguf"
                    + "?download=true"
            ),
            sha256:
                "ba2f13eccd4a5245be728f77e6149bd6a4fdcdd133ff2e08ac6005bcef7a99f1",
            fileSizeBytes: 983_696_512
        )
    }

    private static func cohereTranscribe() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: "cohere-transcribe",
                displayName: "Cohere Transcribe",
                family: .cohereTranscribe,
                supportedLanguages: cohereSupportedLanguages(),
                requiresDownload: true,
                requiresInternet: false,
                format: "ONNX INT8 (encoder-decoder)",
                publisher: "Cohere",
                license: "Apache-2.0",
                licenseURL:
                    "https://www.apache.org/licenses/LICENSE-2.0.html",
                attribution:
                    "Cohere Transcribe 03-2026 by Cohere Labs. 2B parameter "
                    + "Conformer encoder-decoder, 14 languages. INT8 ONNX "
                    + "export by cstr/cohere-transcribe-onnx-int8. Weights are "
                    + "Apache-2.0. Optional cloud API remains Phase 5.",
                privacyNote:
                    "On-device engine using ONNX Runtime with optional CoreML "
                    + "provider. No audio leaves the Mac."
            ),
            runtimeIdentifier: "cohere.transcribe.onnx",
            sourceRepository:
                "https://huggingface.co/cstr/cohere-transcribe-onnx-int8",
            sourceRevision: "main",
            downloadURL: URL(
                string:
                    "https://huggingface.co/cstr/cohere-transcribe-onnx-int8/"
                    + "resolve/main/cohere-encoder.int8.onnx?download=true"
            ),
            sha256: cohereEncoderSHA256,
            fileSizeBytes: cohereEncoderSizeBytes
        )
    }

    private static func cohereSupportedLanguages() -> [SupportedLanguage] {
        [
            "en", "de", "fr", "it", "es", "pt", "nl", "pl", "el",
            "ar", "ja", "zh", "vi", "ko"
        ].compactMap { LanguageCatalog.language(code: $0) }
    }
}
