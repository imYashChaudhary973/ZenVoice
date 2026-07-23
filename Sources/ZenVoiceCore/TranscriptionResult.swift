import Foundation

public struct TranscriptionResult: Equatable, Sendable {
    public let rawTranscript: String
    public let finalTranscript: String
    public let correctionCount: Int
    public let isPartial: Bool
    public let modelID: String
    public let processingDurationSeconds: TimeInterval

    public init(
        rawTranscript: String,
        finalTranscript: String,
        correctionCount: Int,
        isPartial: Bool = false,
        modelID: String = "unknown",
        processingDurationSeconds: TimeInterval = 0
    ) {
        self.rawTranscript = rawTranscript
        self.finalTranscript = finalTranscript
        self.correctionCount = correctionCount
        self.isPartial = isPartial
        self.modelID = modelID
        self.processingDurationSeconds = processingDurationSeconds
    }
}
