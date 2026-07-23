import Foundation

public struct ZenVoiceConfiguration {
    public let modelURL: URL
    public let language: String

    public init(
        modelURL: URL,
        language: String = "en"
    ) {
        self.modelURL = modelURL
        self.language = language
    }

    public var modelID: String {
        VerifiedModelCatalog.model(filename: modelURL.lastPathComponent)?.id
            ?? modelURL.deletingPathExtension().lastPathComponent
    }

    public static func discover(
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
        let language = selectedCatalogueModel?
            .languageCapability.whisperLanguageArgument
            ?? (model.contains(".en.") ? "en" : "auto")
        return ZenVoiceConfiguration(
            modelURL: URL(fileURLWithPath: model),
            language: language
        )
    }

    public enum ConfigurationError: LocalizedError {
        case modelMissing

        public var errorDescription: String? {
            switch self {
            case .modelMissing:
                return "No local Whisper model was found. Download one in Models or set ZENVOICE_MODEL_PATH."
            }
        }
    }
}
