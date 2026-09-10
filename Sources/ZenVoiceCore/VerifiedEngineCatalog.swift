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
              let host = sourceRepository.range(of: "huggingface.co/")
        else {
            return nil
        }
        return String(sourceRepository[host.upperBound...])
    }

    public var downloadFilename: String? {
        downloadURL?.lastPathComponent
    }
}

/// Catalogue of every engine ZenVoice knows about, offered or reserved.
public enum VerifiedEngineCatalog {
    public static let engines: [VerifiedEngine] = [
        parakeetTDTv3()
    ] + VerifiedModelCatalog.models.map(whisperEngine)

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

    private static func parakeetTDTv3() -> VerifiedEngine {
        VerifiedEngine(
            descriptor: EngineDescriptor(
                id: EngineIdentifiers.parakeetTDTv3,
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
}
