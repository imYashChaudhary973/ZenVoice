import Foundation

public struct ZenVoiceConfiguration {
    public let whisperExecutableURL: URL
    public let modelURL: URL

    public init(whisperExecutableURL: URL, modelURL: URL) {
        self.whisperExecutableURL = whisperExecutableURL
        self.modelURL = modelURL
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

        let modelCandidates = [
            environment["ZENVOICE_MODEL_PATH"],
            homeDirectory
                .appendingPathComponent("Library/Application Support/ZenVoice/Models/ggml-base.en.bin")
                .path(percentEncoded: false)
        ].compactMap { $0 }

        guard let model = modelCandidates.first(where: {
            fileManager.fileExists(atPath: $0)
        }) else {
            throw ConfigurationError.modelMissing
        }

        return ZenVoiceConfiguration(
            whisperExecutableURL: URL(fileURLWithPath: executable),
            modelURL: URL(fileURLWithPath: model)
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
