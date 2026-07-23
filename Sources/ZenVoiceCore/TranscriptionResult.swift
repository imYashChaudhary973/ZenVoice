import Foundation

public struct TranscriptionResult: Equatable, Sendable {
    public let rawTranscript: String
    public let finalTranscript: String
    public let correctionCount: Int

    public init(
        rawTranscript: String,
        finalTranscript: String,
        correctionCount: Int
    ) {
        self.rawTranscript = rawTranscript
        self.finalTranscript = finalTranscript
        self.correctionCount = correctionCount
    }
}

