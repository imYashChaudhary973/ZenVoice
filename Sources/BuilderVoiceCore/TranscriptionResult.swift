// Copyright 2026 Yash Chaudhary
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
    /// Words removed by the runaway-repetition collapse. Past
    /// `TranscriptRepetition.wordsCutBeforeDistrust` the decode looped and
    /// the speaker should be told to check what was inserted.
    public let runawayWordsCut: Int

    public init(
        rawTranscript: String,
        finalTranscript: String,
        correctionCount: Int,
        isPartial: Bool = false,
        modelID: String = "unknown",
        processingDurationSeconds: TimeInterval = 0,
        segments: [TranscriptSegment] = [],
        runawayWordsCut: Int = 0
    ) {
        self.rawTranscript = rawTranscript
        self.finalTranscript = finalTranscript
        self.correctionCount = correctionCount
        self.isPartial = isPartial
        self.modelID = modelID
        self.processingDurationSeconds = processingDurationSeconds
        self.segments = segments
        self.runawayWordsCut = runawayWordsCut
    }
}
