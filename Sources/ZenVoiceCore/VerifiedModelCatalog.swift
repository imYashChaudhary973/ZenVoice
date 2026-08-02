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

public enum SpeechModelRuntime: String, Codable, Sendable {
    case whisperCPP
    case parakeetCoreML
}

public struct VerifiedModelFile: Codable, Equatable, Sendable {
    public let relativePath: String
    public let fileSizeBytes: Int64
    public let sha256: String

    public init(
        relativePath: String,
        fileSizeBytes: Int64,
        sha256: String
    ) {
        self.relativePath = relativePath
        self.fileSizeBytes = fileSizeBytes
        self.sha256 = sha256
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
    public let runtime: SpeechModelRuntime
    public let bundleFiles: [VerifiedModelFile]

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
        attribution: String,
        runtime: SpeechModelRuntime = .whisperCPP,
        bundleFiles: [VerifiedModelFile] = []
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
        self.runtime = runtime
        self.bundleFiles = bundleFiles
    }

    public var downloadURL: URL {
        URL(
            string:
                "\(sourceRepository)/resolve/\(sourceRevision)/\(filename)"
                + "?download=true"
        )!
    }

    /// Revision-pinned source for one file of a multi-file bundle.
    ///
    /// Bundles are fetched file by file from this catalogue's pinned revision
    /// rather than from a dependency that resolves a moving branch, so the
    /// recorded `sourceRevision` describes what is actually requested.
    public func bundleFileURL(for file: VerifiedModelFile) -> URL? {
        guard !file.relativePath.hasPrefix("/"),
              !file.relativePath.split(separator: "/").contains("..") else {
            return nil
        }
        let encodedPath = file.relativePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map {
                $0.addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed
                ) ?? String($0)
            }
            .joined(separator: "/")
        return URL(
            string:
                "\(sourceRepository)/resolve/\(sourceRevision)/\(encodedPath)"
                + "?download=true"
        )
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
    public static let parakeetRevision =
        "4252711f6f060f9a2f91e5f081a806d7f45eebd8"
    public static let parakeetRepository =
        "https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml"

    /// Five models, each the measured best at one job.
    ///
    /// The catalogue was eleven. Nine of those were rungs on two size ladders —
    /// tiny, base, small, medium — offered on the assumption that model size
    /// buys a smooth speed-for-accuracy trade the user can position themselves
    /// on. Benchmarked end to end, that assumption is wrong in both families.
    ///
    /// In English there is no trade left to make. Parakeet is simultaneously the
    /// most accurate and very nearly the fastest thing measured, so every
    /// English whisper build is dominated outright:
    ///
    ///     parakeet      5.3% WER     61 ms
    ///     base.en       9.2%        149 ms
    ///     medium.en     6.6%      1,343 ms
    ///     tiny.en      13.8%         66 ms
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
        parakeetUnifiedModel(),
        // The fallback for Intel and small-memory Macs, where Turbo is too slow
        // and Parakeet has no Neural Engine to run on. Offered as a compromise,
        // not as a tier.
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
    ///     whisper-tiny-en      13.8% WER at 66 ms. Parakeet is 5.3% at 61 ms:
    ///                          faster *and* two and a half times better.
    ///     whisper-base-en      9.2% at 149 ms. Same comparison.
    ///     whisper-small-en     never benchmarked, and bracketed on both sides
    ///                          by models Parakeet already beats.
    ///     whisper-tiny-ml      64.5% WER. Not usable for dictation.
    ///     whisper-base-ml      55.1% WER, measured for the first time when
    ///                          this cut was made — it had been offered for
    ///                          months without anyone establishing whether it
    ///                          worked. It does not.
    public static let retiredModels: [VerifiedModel] = [
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

    /// Canonical digest of a bundle's pinned manifest.
    ///
    /// A multi-file bundle has no single file to hash, so `VerifiedModel.sha256`
    /// carries the digest of the manifest itself: every entry sorted by path and
    /// serialized as `path\nsize\nsha256\n`. Verifying it means a tampered
    /// *catalogue* is caught too, not only tampered downloads.
    public static func manifestDigest(
        of files: [VerifiedModelFile]
    ) -> String {
        let canonical = files
            .sorted { $0.relativePath < $1.relativePath }
            .map { "\($0.relativePath)\n\($0.fileSizeBytes)\n\($0.sha256)\n" }
            .joined()
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Every regular file actually present under `root`, relative to it.
    ///
    /// Used to reject a bundle that carries the approved files *plus* something
    /// unreviewed; checking only the manifest entries would accept that.
    private static func installedRelativePaths(
        under root: URL,
        fileManager: FileManager
    ) throws -> Set<String> {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw CatalogError.unreadableBundle
        }
        var found: Set<String> = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            if values.isSymbolicLink == true {
                throw CatalogError.unexpectedBundleEntry
            }
            guard values.isRegularFile == true else {
                continue
            }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else {
                throw CatalogError.unexpectedBundleEntry
            }
            found.insert(String(path.dropFirst(prefix.count)))
        }
        return found
    }

    public enum CatalogError: Error {
        case unreadableBundle
        case unexpectedBundleEntry
    }

    public static func verify(
        _ fileURL: URL,
        for model: VerifiedModel,
        fileManager: FileManager = .default
    ) throws -> Bool {
        if model.runtime == .parakeetCoreML {
            let values = try fileURL.resourceValues(forKeys: [
                .isDirectoryKey
            ])
            guard values.isDirectory == true,
                  !model.bundleFiles.isEmpty,
                  manifestDigest(of: model.bundleFiles) == model.sha256 else {
                return false
            }
            let bundleRoot = fileURL.standardizedFileURL
                .resolvingSymlinksInPath()
            let bundlePrefix = bundleRoot.path + "/"

            // An approved file set plus one unreviewed extra file would pass a
            // manifest-only walk, so compare the installed tree both ways.
            let expectedPaths = Set(model.bundleFiles.map(\.relativePath))
            let installedPaths: Set<String>
            do {
                installedPaths = try installedRelativePaths(
                    under: bundleRoot,
                    fileManager: fileManager
                )
            } catch {
                return false
            }
            guard installedPaths == expectedPaths else {
                return false
            }

            for file in model.bundleFiles {
                guard !file.relativePath.hasPrefix("/"),
                      !file.relativePath.split(separator: "/").contains("..")
                else {
                    return false
                }
                let candidate = bundleRoot
                    .appendingPathComponent(
                        file.relativePath,
                        isDirectory: false
                    )
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                guard candidate.path.hasPrefix(bundlePrefix) else {
                    return false
                }
                let candidateValues = try candidate.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .isSymbolicLinkKey
                ])
                guard candidateValues.isRegularFile == true,
                      candidateValues.isSymbolicLink != true,
                      Int64(candidateValues.fileSize ?? -1)
                        == file.fileSizeBytes,
                      try sha256Hex(of: candidate) == file.sha256 else {
                    return false
                }
            }
            return model.bundleFiles.reduce(Int64(0)) {
                $0 + $1.fileSizeBytes
            } == model.fileSizeBytes
        }

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

    private static func parakeetUnifiedModel() -> VerifiedModel {
        VerifiedModel(
            id: "parakeet-unified-en-int8",
            displayName: "Parakeet",
            filename: "parakeet-unified-en-0.6b",
            tier: .fast,
            languageCapability: .english,
            publisher: "FluidInference / NVIDIA",
            sourceRepository: parakeetRepository,
            upstreamRepository:
                "https://huggingface.co/nvidia/parakeet-unified-en-0.6b",
            sourceRevision: parakeetRevision,
            // Digest of the pinned manifest below, not of a single file — see
            // `manifestDigest(of:)`. The previous value here described nothing
            // any code computed, so verification silently ignored it.
            sha256:
                "04974b08a35d460ef32e37f747f938aa0c1df83120452125b01d52bded3f808a",
            fileSizeBytes: 614_082_275,
            format: "Core ML; INT8 encoder",
            license: "CC-BY-4.0",
            licenseURL:
                "https://creativecommons.org/licenses/by/4.0/legalcode",
            attribution:
                "Parakeet Unified EN 0.6B by NVIDIA, converted to Core ML "
                + "by FluidInference. INT8 encoder inference uses FluidAudio.",
            runtime: .parakeetCoreML,
            bundleFiles: parakeetBundleFiles
        )
    }

    private static let parakeetBundleFiles: [VerifiedModelFile] = [
        .init(
            relativePath: "config.json",
            fileSizeBytes: 1_355,
            sha256:
                "6cbe6c76445410c5c6debf3d44c8c3b75e9966bf09bba5cd138c2378c62120f6"
        ),
        .init(
            relativePath: "metadata.json",
            fileSizeBytes: 1_046,
            sha256:
                "2b26a96b76fe1f7a04d3e867f50c75d6ce5dd1650d0dbcd4c35b591b22305f0e"
        ),
        .init(
            relativePath:
                "parakeet_unified_decoder.mlmodelc/analytics/coremldata.bin",
            fileSizeBytes: 243,
            sha256:
                "9ae70f6559989f88b856b326e59315798f9f0d08207a19fcc2dd3287a30088a5"
        ),
        .init(
            relativePath:
                "parakeet_unified_decoder.mlmodelc/coremldata.bin",
            fileSizeBytes: 560,
            sha256:
                "ce99c4488840fc463d59f8d4d6d2a9e8ceae8138ead51e3c265dde4d2ba4a0e9"
        ),
        .init(
            relativePath: "parakeet_unified_decoder.mlmodelc/model.mil",
            fileSizeBytes: 13_102,
            sha256:
                "6e60965b89c93943aa2be2d991c2461108145851fde05e1d048223a32d4cb20d"
        ),
        .init(
            relativePath:
                "parakeet_unified_decoder.mlmodelc/weights/weight.bin",
            fileSizeBytes: 14_429_952,
            sha256:
                "96f990461a5986d5e7309ad1a0f36084fbf0f4b28aec35948f8b8d0dcbf8599e"
        ),
        .init(
            relativePath:
                "parakeet_unified_encoder_int8.mlmodelc/analytics/coremldata.bin",
            fileSizeBytes: 243,
            sha256:
                "57e116a9d5765e39c0cdf754137ab744ddae34d9c6d68a5fdcad6600ae3a7b6b"
        ),
        .init(
            relativePath:
                "parakeet_unified_encoder_int8.mlmodelc/coremldata.bin",
            fileSizeBytes: 492,
            sha256:
                "54f533d30343d5e62b324a0691e4c262a6768b07b6e88e7aa14c617a2baba8a3"
        ),
        .init(
            relativePath:
                "parakeet_unified_encoder_int8.mlmodelc/model.mil",
            fileSizeBytes: 1_110_902,
            sha256:
                "c1c5d71c6cbf4d35bba08458746bde3640da7b1b444e1229a269393a58222c10"
        ),
        .init(
            relativePath:
                "parakeet_unified_encoder_int8.mlmodelc/weights/weight.bin",
            fileSizeBytes: 595_051_904,
            sha256:
                "f984b81590a4deae041ae20fbab8981c2d2a5b528b2ac81fae81c432633535c6"
        ),
        .init(
            relativePath:
                "parakeet_unified_joint_decision_single_step.mlmodelc/analytics/coremldata.bin",
            fileSizeBytes: 243,
            sha256:
                "163877ad14af97ec4107cd854fd1c6d336ee5d40ad25a657cc764fb763f452f5"
        ),
        .init(
            relativePath:
                "parakeet_unified_joint_decision_single_step.mlmodelc/coremldata.bin",
            fileSizeBytes: 556,
            sha256:
                "68a081570a48b52ec9379e153bd56748a5408a50be16767601563f231eaeff03"
        ),
        .init(
            relativePath:
                "parakeet_unified_joint_decision_single_step.mlmodelc/model.mil",
            fileSizeBytes: 9_611,
            sha256:
                "03c21096090bcd0b71c896c5ae0eb815db31a91c6676f572a7868eee4299abe3"
        ),
        .init(
            relativePath:
                "parakeet_unified_joint_decision_single_step.mlmodelc/weights/weight.bin",
            fileSizeBytes: 3_446_978,
            sha256:
                "06831afa6d1beb0c0b10350ebf7886bc37638e951d14e738d7e06fbd2a05012f"
        ),
        .init(
            relativePath: "vocab.json",
            fileSizeBytes: 15_088,
            sha256:
                "e1a7bff4f5df133c0f4ad47b8e43c96f6bf1865d99126a4c4725ef51d0108bec"
        ),
    ]

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
