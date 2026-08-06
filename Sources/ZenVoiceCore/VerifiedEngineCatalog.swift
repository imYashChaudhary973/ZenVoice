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
    /// Engines that can be selected in Phase 1.
    public static let engines: [VerifiedEngine] = [
        appleSpeech()
    ]

    /// Engines planned for later phases. Their IDs and families are fixed so
    /// Phase 2/3/5 code can refer to them without changing this file.
    public static let reservedEngines: [VerifiedEngine] = [
        parakeetTDTv2(),
        parakeetTDTv3(),
        parakeetFlash(),
        nemotronSpeechUltraFast(),
        nemotronSpeechMultilingual(),
        cohereTranscribe()
    ]

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
                format: "Core ML / ONNX",
                publisher: "NVIDIA",
                license: "NVIDIA Open Model License",
                licenseURL:
                    "https://www.nvidia.com/en-us/agreements/enterprise-software/"
                    + "nvidia-open-model-license/",
                attribution:
                    "Parakeet TDT by NVIDIA. Runtime integration planned for "
                    + "Phase 2.",
                privacyNote:
                    "Planned on-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.parakeet.tdt.v2",
            sourceRepository:
                "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2",
            sourceRevision: nil,
            downloadURL: nil,
            sha256: nil,
            fileSizeBytes: nil
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
                format: "Core ML / ONNX",
                publisher: "NVIDIA",
                license: "NVIDIA Open Model License",
                licenseURL:
                    "https://www.nvidia.com/en-us/agreements/enterprise-software/"
                    + "nvidia-open-model-license/",
                attribution:
                    "Parakeet TDT by NVIDIA. Runtime integration planned for "
                    + "Phase 2.",
                privacyNote:
                    "Planned on-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.parakeet.tdt.v3",
            sourceRepository:
                "https://huggingface.co/nvidia/parakeet-tdt-1.1b",
            sourceRevision: nil,
            downloadURL: nil,
            sha256: nil,
            fileSizeBytes: nil
        )
    }

    private static func parakeetFlash() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: "parakeet-flash",
                displayName: "Parakeet Flash",
                family: .parakeetFlash,
                supportedLanguages: [],
                requiresDownload: true,
                requiresInternet: false,
                format: "Core ML / ONNX",
                publisher: "NVIDIA",
                license: "NVIDIA Open Model License",
                licenseURL:
                    "https://www.nvidia.com/en-us/agreements/enterprise-software/"
                    + "nvidia-open-model-license/",
                attribution:
                    "Parakeet Flash by NVIDIA. Runtime integration planned for "
                    + "Phase 2.",
                privacyNote:
                    "Planned on-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.parakeet.flash",
            sourceRepository:
                "https://huggingface.co/nvidia/parakeet-rnn-v2",
            sourceRevision: nil,
            downloadURL: nil,
            sha256: nil,
            fileSizeBytes: nil
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
                format: "Core ML / ONNX",
                publisher: "NVIDIA",
                license: "NVIDIA Open Model License",
                licenseURL:
                    "https://www.nvidia.com/en-us/agreements/enterprise-software/"
                    + "nvidia-open-model-license/",
                attribution:
                    "Nemotron Speech 3.5 by NVIDIA. Runtime integration planned "
                    + "for Phase 2.",
                privacyNote:
                    "Planned on-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.nemotron.speech.ultra.fast",
            sourceRepository:
                "https://huggingface.co/nvidia/Nemotron-Speech-3.5-Ultra-Fast",
            sourceRevision: nil,
            downloadURL: nil,
            sha256: nil,
            fileSizeBytes: nil
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
                format: "Core ML / ONNX",
                publisher: "NVIDIA",
                license: "NVIDIA Open Model License",
                licenseURL:
                    "https://www.nvidia.com/en-us/agreements/enterprise-software/"
                    + "nvidia-open-model-license/",
                attribution:
                    "Nemotron 3.5 Multilingual by NVIDIA. Runtime integration "
                    + "planned for Phase 2.",
                privacyNote:
                    "Planned on-device engine. No audio leaves the Mac."
            ),
            runtimeIdentifier: "nvidia.nemotron.speech.multilingual",
            sourceRepository:
                "https://huggingface.co/nvidia/Nemotron-Speech-3.5-Multilingual",
            sourceRevision: nil,
            downloadURL: nil,
            sha256: nil,
            fileSizeBytes: nil
        )
    }

    private static func cohereTranscribe() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: "cohere-transcribe",
                displayName: "Cohere Transcribe",
                family: .cohereTranscribe,
                supportedLanguages: [],
                requiresDownload: false,
                requiresInternet: true,
                format: "Cloud API",
                publisher: "Cohere",
                license: "Cohere Terms of Service",
                licenseURL: "https://cohere.com/terms",
                attribution:
                    "Cohere Transcribe cloud API. Optional enhancement planned "
                    + "for Phase 5; requires explicit opt-in and an API key.",
                privacyNote:
                    "Cloud engine: audio leaves this Mac only with explicit "
                    + "opt-in."
            ),
            runtimeIdentifier: "cohere.transcribe.api",
            sourceRepository: nil,
            sourceRevision: nil,
            downloadURL: nil,
            sha256: nil,
            fileSizeBytes: nil
        )
    }
}
