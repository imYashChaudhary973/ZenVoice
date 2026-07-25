import Foundation

public struct ZenVoiceConfiguration {
    public let modelURL: URL
    public let languageProfile: LanguageProfile

    public init(
        modelURL: URL,
        languageProfile: LanguageProfile = .english
    ) {
        self.modelURL = modelURL
        self.languageProfile = languageProfile
    }

    public var language: String {
        languageProfile.whisperLanguageArgument
    }

    public var shouldTranslateToEnglish: Bool {
        languageProfile.shouldTranslateToEnglish
    }

    public var shouldTransliterateToLatin: Bool {
        languageProfile.shouldTransliterateToLatin
    }

    public var modelID: String {
        VerifiedModelCatalog.model(filename: modelURL.lastPathComponent)?.id
            ?? modelURL.deletingPathExtension().lastPathComponent
    }

    /// Size of the selected model on disk, preferring the catalogue's reviewed
    /// figure and falling back to the file itself for a legacy or overridden
    /// model.
    public var modelFileSizeBytes: Int64 {
        if let model = VerifiedModelCatalog.model(
            filename: modelURL.lastPathComponent
        ) {
            return model.fileSizeBytes
        }
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: modelURL.path(percentEncoded: false)
        )
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Smaller models are uncertain enough that exploring alternatives finds a
    /// better transcript; larger ones are not. See ``WhisperDecoding``.
    public var usesBeamSearchDecoding: Bool {
        WhisperDecoding.usesBeamSearch(
            modelFileSizeBytes: modelFileSizeBytes
        )
    }

    public var modelLanguageCapability: ModelLanguageCapability {
        VerifiedModelCatalog.model(
            filename: modelURL.lastPathComponent
        )?.languageCapability
            ?? (modelURL.lastPathComponent.contains(".en.")
                ? .english
                : .multilingual)
    }

    public static func discover(
        languageProfile: LanguageProfile? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> ZenVoiceConfiguration {
        let fileManager = FileManager.default

        let selectedModel = ModelSelectionPreferences.load()
        let selectedModelPath = selectedModel.flatMap {
            try? VerifiedModelCatalog.installedURL(for: $0).path
        }
        let legacyModelPath = homeDirectory
            .appendingPathComponent(
                "Library/Application Support/ZenVoice/Models/ggml-base.en.bin"
            )
            .path(percentEncoded: false)
        let model: String
        if let override = environment["ZENVOICE_MODEL_PATH"],
           fileManager.fileExists(atPath: override) {
            model = override
        } else if let selectedModel,
                  let selectedModelPath,
                  (try? VerifiedModelCatalog.verify(
                    URL(fileURLWithPath: selectedModelPath),
                    for: selectedModel,
                    fileManager: fileManager
                  )) == true {
            model = selectedModelPath
        } else if legacyModelPath != selectedModelPath,
                  fileManager.fileExists(atPath: legacyModelPath) {
            model = legacyModelPath
        } else {
            throw ConfigurationError.modelMissing
        }

        let selectedCatalogueModel = selectedModel.flatMap { selected in
            selected.filename == URL(fileURLWithPath: model).lastPathComponent
                ? selected
                : nil
        }
        let capability = selectedCatalogueModel?.languageCapability
            ?? (model.contains(".en.") ? .english : .multilingual)
        let resolvedLanguageProfile =
            languageProfile ?? LanguagePreferences.load()
        guard resolvedLanguageProfile.isCompatible(with: capability) else {
            throw ConfigurationError.multilingualModelRequired(
                resolvedLanguageProfile.displayName
            )
        }
        return ZenVoiceConfiguration(
            modelURL: URL(fileURLWithPath: model),
            languageProfile: resolvedLanguageProfile
        )
    }

    public enum ConfigurationError: LocalizedError {
        case modelMissing
        case multilingualModelRequired(String)

        public var errorDescription: String? {
            switch self {
            case .modelMissing:
                return "No local Whisper model was found. Download one in Models or set ZENVOICE_MODEL_PATH."
            case .multilingualModelRequired(let profile):
                return "\(profile) requires a multilingual Whisper model. Download and select one in Models."
            }
        }
    }
}
