import Foundation
import ZenVoiceCore

final class WhisperTranscriber: @unchecked Sendable {
    enum TranscriptionError: LocalizedError {
        case commandFailed
        case noSpeech

        var errorDescription: String? {
            switch self {
            case .commandFailed:
                return "Local transcription failed."
            case .noSpeech:
                return "No speech detected."
            }
        }
    }

    private let configuration: ZenVoiceConfiguration
    private let cleaner = TranscriptCleaner()

    init(configuration: ZenVoiceConfiguration) {
        self.configuration = configuration
    }

    func transcribe(audioURL: URL) throws -> String {
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let process = Process()
        process.executableURL = configuration.whisperExecutableURL
        process.arguments = [
            "--model", configuration.modelURL.path,
            "--file", audioURL.path,
            "--language", "en",
            "--no-timestamps",
            "--no-prints",
            "--threads", "8"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TranscriptionError.commandFailed
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let rawTranscript = String(data: data, encoding: .utf8) ?? ""
        let transcript = cleaner.clean(rawTranscript)

        guard !transcript.isEmpty else {
            throw TranscriptionError.noSpeech
        }

        return transcript
    }
}
