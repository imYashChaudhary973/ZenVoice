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

/// A single archived full recording in the Audio History feature.
///
/// Audio archives are stored as plain WAV files in private Application Support
/// storage. Metadata is kept in the same SQLite database as transcripts, but
/// only references the file path, size, and non-sensitive capture facts. The
/// audio file itself is not encrypted; the archive is gated by the user's
/// opt-in and bounded by size/age budgets.
public struct AudioArchiveRecord: Identifiable, Sendable {
    public let id: UUID
    public let dictationID: UUID
    public let startedAt: Date
    public let durationSeconds: TimeInterval
    public let fileSize: Int64
    public let audioURL: URL
    public let language: String
    public let modelID: String
    public let targetBundleID: String?
    public let targetAppName: String?
    public let category: DictationCategory

    public init(
        id: UUID,
        dictationID: UUID,
        startedAt: Date,
        durationSeconds: TimeInterval,
        fileSize: Int64,
        audioURL: URL,
        language: String,
        modelID: String,
        targetBundleID: String?,
        targetAppName: String?,
        category: DictationCategory
    ) {
        self.id = id
        self.dictationID = dictationID
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.fileSize = fileSize
        self.audioURL = audioURL
        self.language = language
        self.modelID = modelID
        self.targetBundleID = targetBundleID
        self.targetAppName = targetAppName
        self.category = category
    }
}
