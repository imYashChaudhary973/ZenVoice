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

import CryptoKit
import Foundation

public enum ModelPerformanceTier: String, Codable, CaseIterable, Sendable {
    case fast
    case balanced
    case highAccuracy

    public var displayName: String {
        switch self {
        case .fast: "Fast"
        case .balanced: "Balanced"
        case .highAccuracy: "High Accuracy"
        }
    }
}

public enum ModelLanguageCapability: String, Codable, CaseIterable, Sendable {
    case english
    case multilingual
    /// Fine-tuned for Hindi-English code-switching and writes its output in
    /// Latin script directly.
    ///
    /// Not a subset of `multilingual`: the training is Hindi-dominant and the
    /// model has no claim to the other 98 languages Whisper covers, so pairing
    /// it with a French profile would produce confident nonsense. It is
    /// selectable only under the Hinglish profile.
    case hinglish

    public var displayName: String {
        switch self {
        case .english: "English"
        case .multilingual: "Multilingual"
        case .hinglish: "Hinglish"
        }
    }

    /// Whether the model already writes Latin script.
    ///
    /// Everything else reaches Hinglish by transcribing Devanagari and
    /// romanizing it afterwards, which destroys English loanwords —
    /// `computer → कंप्यूटर → kampyutara`. A Hinglish-native model skips both
    /// steps, so running the romanizer over its output would corrupt text that
    /// is already correct.
    public var emitsLatinScriptNatively: Bool {
        self == .hinglish
    }
}

public struct VerifiedModel: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let filename: String
    public let tier: ModelPerformanceTier
    public let languageCapability: ModelLanguageCapability
    public let publisher: String
    public let sourceRepository: String
    public let upstreamRepository: String
    public let sourceRevision: String
    public let sha256: String
    public let fileSizeBytes: Int64
    public let format: String
    public let license: String
    public let licenseURL: String
    public let attribution: String
    public init(
        id: String,
        displayName: String,
        filename: String,
        tier: ModelPerformanceTier,
        languageCapability: ModelLanguageCapability,
        publisher: String,
        sourceRepository: String,
        upstreamRepository: String,
        sourceRevision: String,
        sha256: String,
        fileSizeBytes: Int64,
        format: String,
        license: String,
        licenseURL: String,
        attribution: String
    ) {
        self.id = id
        self.displayName = displayName
        self.filename = filename
        self.tier = tier
        self.languageCapability = languageCapability
        self.publisher = publisher
        self.sourceRepository = sourceRepository
        self.upstreamRepository = upstreamRepository
        self.sourceRevision = sourceRevision
        self.sha256 = sha256
        self.fileSizeBytes = fileSizeBytes
        self.format = format
        self.license = license
        self.licenseURL = licenseURL
        self.attribution = attribution
    }

    public var downloadURL: URL {
        URL(
            string:
                "\(sourceRepository)/resolve/\(sourceRevision)/\(filename)"
                + "?download=true"
        )!
    }

    public var formattedFileSize: String {
        ByteCountFormatter.string(
            fromByteCount: fileSizeBytes,
            countStyle: .file
        )
    }
}

public enum VerifiedModelCatalog {
    public static let sourceRevision =
        "5359861c739e955e79d9a303bcbc70fb988958b1"
    public static let sourceRepository =
        "https://huggingface.co/ggerganov/whisper.cpp"

    /// Four models, each the measured best at one job.
    ///
    /// The catalogue was eleven. Nine of those were rungs on two size ladders —
    /// tiny, base, small, medium — offered on the assumption that model size
    /// buys a smooth speed-for-accuracy trade the user can position themselves
    /// on. Benchmarked end to end, that assumption is wrong in both families.
    ///
    /// In English the trade is between speed and accuracy. Whisper Turbo is the
    /// default on Apple Silicon; Whisper Small is the fallback where GPU
    /// transcription is unavailable.
    ///
    /// In multilingual the trade is a cliff rather than a curve. Anything below
    /// Turbo is not "faster with a little less accuracy", it is unusable:
    ///
    ///     turbo        13.2% WER   1,451 ms
    ///     medium       14.5%       1,173 ms
    ///     small        35.5%         456 ms
    ///     base         55.1%         139 ms
    ///     tiny         64.5%          91 ms
    ///
    /// Small survives only as the fallback for Macs that cannot run Turbo well,
    /// and it is offered as exactly that rather than as a speed choice — at
    /// 35.5% it is European-languages-only in practice, scoring 100% on both
    /// Japanese and Mandarin.
    ///
    /// Nothing here is deleted; see ``retiredModels``.
    public static let models: [VerifiedModel] = [
        // The fallback for Intel and small-memory Macs, where Turbo is too slow.
        // Offered as a compromise, not as a tier.
        model(
            id: "whisper-small-multilingual",
            name: "Whisper Small",
            filename: "ggml-small.bin",
            tier: .balanced,
            language: .multilingual,
            sha256:
                "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
            size: 487_601_967
        ),
        // Matches Whisper Medium's accuracy at roughly a third of the download,
        // and handles every language rather than English alone. The default
        // recommendation on Apple Silicon.
        model(
            id: "whisper-large-v3-turbo",
            name: "Whisper Turbo",
            filename: "ggml-large-v3-turbo-q5_0.bin",
            tier: .highAccuracy,
            language: .multilingual,
            sha256:
                "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
            size: 574_041_195
        ),
        // Hindi-English code-switching, written in Latin script directly.
        //
        // Every other model reaches Hinglish by transcribing Devanagari and
        // romanizing it, which destroys the English half of the sentence:
        // `computer` becomes `कंप्यूटर` becomes `kampyutara`. Measured on the
        // accuracy harness, that path preserves 0 of 26 English words. This
        // model preserves 21.
        //
        // It is a specialist and is offered only for the Hinglish profile.
        // On English dictation it scores 16.8% word error rate against Whisper
        // Medium's 2.0%, because 700 hours of Hindi fine-tuning cost it the
        // technical English vocabulary it started with.
        hinglishModel(
            id: "hindi2hinglish-apex",
            name: "Hinglish Apex",
            filename: "ggml-hindi2hinglish-apex-q8_0.bin",
            sha256:
                "0b4324d2c1ad64f20883ee7fcd5d2bb0a8466287dc70d74bc47066200c28c719",
            size: 874_188_075
        ),
        model(
            id: "whisper-medium-multilingual",
            name: "Whisper Medium",
            filename: "ggml-medium.bin",
            tier: .highAccuracy,
            language: .multilingual,
            sha256:
                "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208",
            size: 1_533_763_059
        )
    ]

    /// Models no longer offered, but still resolvable.
    ///
    /// Retired rather than deleted because deleting would strand anyone who
    /// already installed one: selection is stored by identifier and resolved
    /// through this catalogue, so a missing entry turns a working model on disk
    /// into "no model installed" — and `discover()` would quietly fall through
    /// to the legacy `ggml-base.en.bin` path or fail outright. Retired entries
    /// stay resolvable and verifiable, and simply stop being offered.
    ///
    /// Each is superseded, with the measurement that retired it:
    ///
    ///     whisper-medium-en    2.9% WER against the multilingual build's 2.7%
    ///                          — same 1.5 GB, same speed, slightly worse, and
    ///                          English-only.
    ///     whisper-tiny-en      13.8% WER at 66 ms. Retired in favour of larger
    ///                          whisper models.
    ///     whisper-base-en      9.2% at 149 ms. Retired in favour of larger
    ///                          whisper models.
    ///     whisper-small-en     never benchmarked, and bracketed on both sides
    ///                          by larger whisper models.
    ///     whisper-tiny-ml      64.5% WER. Not usable for dictation.
    ///     whisper-base-ml      55.1% WER, measured for the first time when
    ///                          this cut was made — it had been offered for
    ///                          months without anyone establishing whether it
    ///                          worked. It does not.
    ///     parakeet-unified-en-int8  Formerly used a closed-source FluidAudio
    ///                               runtime; retired to keep ZenVoice fully
    ///                               independent and open-source.
    public static let retiredModels: [VerifiedModel] = [
        retiredParakeetModel(),
        model(
            id: "whisper-medium-en",
            name: "Whisper Medium",
            filename: "ggml-medium.en.bin",
            tier: .highAccuracy,
            language: .english,
            sha256:
                "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356",
            size: 1_533_774_781
        ),
        model(
            id: "whisper-tiny-en",
            name: "Whisper Tiny",
            filename: "ggml-tiny.en.bin",
            tier: .fast,
            language: .english,
            sha256:
                "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
            size: 77_704_715
        ),
        model(
            id: "whisper-tiny-multilingual",
            name: "Whisper Tiny",
            filename: "ggml-tiny.bin",
            tier: .fast,
            language: .multilingual,
            sha256:
                "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
            size: 77_691_713
        ),
        model(
            id: "whisper-base-en",
            name: "Whisper Base",
            filename: "ggml-base.en.bin",
            tier: .balanced,
            language: .english,
            sha256:
                "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
            size: 147_964_211
        ),
        model(
            id: "whisper-base-multilingual",
            name: "Whisper Base",
            filename: "ggml-base.bin",
            tier: .balanced,
            language: .multilingual,
            sha256:
                "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            size: 147_951_465
        ),
        model(
            id: "whisper-small-en",
            name: "Whisper Small",
            filename: "ggml-small.en.bin",
            tier: .balanced,
            language: .english,
            sha256:
                "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d",
            size: 487_614_201
        )
    ]

    /// Everything the app can resolve, offered or not.
    public static var allModels: [VerifiedModel] {
        models + retiredModels
    }

    public static func model(id: String) -> VerifiedModel? {
        allModels.first { $0.id == id }
    }

    public static func model(filename: String) -> VerifiedModel? {
        allModels.first { $0.filename == filename }
    }

    public static func isRetired(_ model: VerifiedModel) -> Bool {
        retiredModels.contains { $0.id == model.id }
    }

    public static func modelsDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportDirectory
            .appendingPathComponent("ZenVoice", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    public static func installedURL(
        for model: VerifiedModel,
        fileManager: FileManager = .default
    ) throws -> URL {
        try modelsDirectory(fileManager: fileManager)
            .appendingPathComponent(model.filename)
    }

    public static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(
        _ fileURL: URL,
        for model: VerifiedModel,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let values = try fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              Int64(values.fileSize ?? -1) == model.fileSizeBytes else {
            return false
        }
        return try sha256Hex(of: fileURL) == model.sha256
    }

    private static func retiredParakeetModel() -> VerifiedModel {
        VerifiedModel(
            id: "parakeet-unified-en-int8",
            displayName: "Parakeet (retired)",
            filename: "parakeet-unified-en-0.6b",
            tier: .fast,
            languageCapability: .english,
            publisher: "FluidInference / NVIDIA",
            sourceRepository:
                "https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml",
            upstreamRepository:
                "https://huggingface.co/nvidia/parakeet-unified-en-0.6b",
            sourceRevision:
                "4252711f6f060f9a2f91e5f081a806d7f45eebd8",
            sha256:
                "04974b08a35d460ef32e37f747f938aa0c1df83120452125b01d52bded3f808a",
            fileSizeBytes: 614_082_275,
            format: "Core ML; INT8 encoder",
            license: "NVIDIA Open Model License",
            licenseURL:
                "https://www.nvidia.com/en-us/agreements/enterprise-software/"
                + "nvidia-open-model-license/",
            attribution:
                "Licensed by NVIDIA Corporation under the NVIDIA Open Model "
                + "License. Parakeet Unified EN 0.6B by NVIDIA, converted to "
                + "Core ML by FluidInference. Retired from active use in "
                + "ZenVoice because it requires the closed-source FluidAudio "
                + "runtime."
        )
    }


    /// Weights ZenVoice converted itself, pinned by commit.
    ///
    /// Oriserve publish Apex as HuggingFace safetensors and whisper.cpp needs
    /// GGML, so somebody has to convert it. Rather than depend on a stranger's
    /// conversion, ZenVoice runs it and republishes the result — which means
    /// the checksum below is pinned against a file this project produced and
    /// measured, not one it merely found.
    ///
    /// A commit hash rather than a branch or tag, for the same reason the
    /// stock models use one: a tag can be moved to point at different bytes,
    /// a commit cannot.
    public static let convertedModelRevision =
        "0c540ce8945ef96b2880f2d2c0d05ba419621171"
    public static let convertedModelRepository =
        "https://huggingface.co/imYChaudhary22/zenvoice-hinglish-apex-ggml"

    private static func hinglishModel(
        id: String,
        name: String,
        filename: String,
        sha256: String,
        size: Int64
    ) -> VerifiedModel {
        VerifiedModel(
            id: id,
            displayName: name,
            filename: filename,
            tier: .highAccuracy,
            languageCapability: .hinglish,
            // Who produced *this file*, matching how the stock entries name
            // ggml-org rather than OpenAI. Oriserve trained the weights and
            // are credited for them in `attribution` and `upstreamRepository`,
            // but they never published a GGML — this conversion is ours, and
            // the checksum below is pinned against it.
            publisher: "ZenVoice",
            sourceRepository: convertedModelRepository,
            upstreamRepository:
                "https://github.com/OriserveAI/Whisper-Hindi2Hinglish",
            sourceRevision: convertedModelRevision,
            sha256: sha256,
            fileSizeBytes: size,
            format: "whisper.cpp GGML",
            license: "Apache-2.0",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0",
            attribution:
                "Whisper-Hindi2Hinglish-Apex by Oriserve, fine-tuned from "
                + "OpenAI Whisper large-v3-turbo. Converted to whisper.cpp "
                + "GGML and quantized to q8_0 for ZenVoice."
        )
    }

    private static func model(
        id: String,
        name: String,
        filename: String,
        tier: ModelPerformanceTier,
        language: ModelLanguageCapability,
        sha256: String,
        size: Int64
    ) -> VerifiedModel {
        VerifiedModel(
            id: id,
            displayName: name,
            filename: filename,
            tier: tier,
            languageCapability: language,
            publisher: "ggml-org / Georgi Gerganov",
            sourceRepository: sourceRepository,
            upstreamRepository: "https://github.com/openai/whisper",
            sourceRevision: sourceRevision,
            sha256: sha256,
            fileSizeBytes: size,
            format: "whisper.cpp GGML",
            license: "MIT",
            licenseURL:
                "https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE",
            attribution:
                "OpenAI Whisper weights converted for whisper.cpp by ggml-org."
        )
    }
}

public enum ModelSelectionPreferences {
    public static let preferenceKey = "ZenVoice.selectedModelID"

    public static func load(
        defaults: UserDefaults = .standard
    ) -> VerifiedModel? {
        guard let id = defaults.string(forKey: preferenceKey) else {
            return nil
        }
        return VerifiedModelCatalog.model(id: id)
    }

    public static func save(
        _ model: VerifiedModel,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(model.id, forKey: preferenceKey)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: preferenceKey)
    }
}
