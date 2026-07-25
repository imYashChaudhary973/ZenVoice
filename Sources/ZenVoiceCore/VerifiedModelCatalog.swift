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

    public var displayName: String {
        switch self {
        case .english: "English"
        case .multilingual: "Multilingual"
        }
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

    public static let models: [VerifiedModel] = [
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
        ),
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

    public static func model(id: String) -> VerifiedModel? {
        models.first { $0.id == id }
    }

    public static func model(filename: String) -> VerifiedModel? {
        models.first { $0.filename == filename }
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
