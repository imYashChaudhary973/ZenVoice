import Foundation

public struct ZenVoiceConfiguration {
    public let whisperExecutableURL: URL
    public let modelURL: URL
    public let language: String

    public init(
        whisperExecutableURL: URL,
        modelURL: URL,
        language: String = "en"
    ) {
        self.whisperExecutableURL = whisperExecutableURL
        self.modelURL = modelURL
        self.language = language
    }

    public var modelID: String {
        modelURL.deletingPathExtension().lastPathComponent
    }

    public static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> ZenVoiceConfiguration {
        let fileManager = FileManager.default

        let executableCandidates = [
            environment["ZENVOICE_WHISPER_PATH"],
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli"
        ].compactMap { $0 }

        guard let executable = executableCandidates.first(where: {
            fileManager.isExecutableFile(atPath: $0)
        }) else {
            throw ConfigurationError.whisperExecutableMissing
        }

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
            whisperExecutableURL: URL(fileURLWithPath: executable),
            modelURL: URL(fileURLWithPath: model),
            language: language
        )
    }

    public enum ConfigurationError: LocalizedError {
        case whisperExecutableMissing
        case modelMissing

        public var errorDescription: String? {
            switch self {
            case .whisperExecutableMissing:
                return "whisper-cli is missing. Install it with: brew install whisper-cpp"
            case .modelMissing:
                return "No local Whisper model was found. Set ZENVOICE_MODEL_PATH to a ggml model."
            }
        }
    }
}
