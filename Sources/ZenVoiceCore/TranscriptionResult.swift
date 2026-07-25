import Foundation

public struct TranscriptionResult: Equatable, Sendable {
    public let rawTranscript: String
    public let finalTranscript: String
    public let correctionCount: Int
    public let isPartial: Bool
    public let modelID: String
    public let processingDurationSeconds: TimeInterval
    /// The decoded stretches with their timings, kept so pauses can become
    /// paragraphs. Empty when the runtime did not report them.
    public let segments: [TranscriptSegment]

    public init(
        rawTranscript: String,
        finalTranscript: String,
        correctionCount: Int,
        isPartial: Bool = false,
        modelID: String = "unknown",
        processingDurationSeconds: TimeInterval = 0,
        segments: [TranscriptSegment] = []
    ) {
        self.rawTranscript = rawTranscript
        self.finalTranscript = finalTranscript
        self.correctionCount = correctionCount
        self.isPartial = isPartial
        self.modelID = modelID
        self.processingDurationSeconds = processingDurationSeconds
        self.segments = segments
    }
}
