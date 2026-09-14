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

public enum DictationStatus: String, Codable, Sendable {
    case recording
    case transcribing
    case ready
    case inserted
    case copiedOnly
    case failed
}

public enum DictationCategory:
    String, Codable, CaseIterable, Identifiable, Sendable
{
    case documents
    case email
    case workMessages
    case personalMessages
    case aiPrompts
    case notes
    case development
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .documents: "Documents"
        case .email: "Email"
        case .workMessages: "Work messages"
        case .personalMessages: "Personal messages"
        case .aiPrompts: "AI prompts"
        case .notes: "Notes"
        case .development: "Development"
        case .other: "Other"
        }
    }
}

public struct DictationDraft: Sendable {
    public let id: UUID
    public let startedAt: Date
    public let language: String
    public let modelID: String
    public let targetBundleID: String?
    public let targetAppName: String?
    public let category: DictationCategory
    public let recoveryAudioURL: URL

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        language: String,
        modelID: String,
        targetBundleID: String?,
        targetAppName: String?,
        category: DictationCategory = .other,
        recoveryAudioURL: URL
    ) {
        self.id = id
        self.startedAt = startedAt
        self.language = language
        self.modelID = modelID
        self.targetBundleID = targetBundleID
        self.targetAppName = targetAppName
        self.category = category
        self.recoveryAudioURL = recoveryAudioURL
    }
}

public struct DictationRecord: Identifiable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let completedAt: Date?
    public let durationSeconds: TimeInterval
    public let rawTranscript: String?
    public let finalTranscript: String?
    public let wordCount: Int
    public let wordsPerMinute: Double
    public let language: String
    public let modelID: String
    public let targetBundleID: String?
    public let targetAppName: String?
    public let category: DictationCategory
    public let insertionOutcome: DictationStatus?
    public let correctionCount: Int
    public let isPartial: Bool
    public let status: DictationStatus
    public let recoveryAudioURL: URL?
    public let recoveryAudioExpiresAt: Date?
    public let errorMessage: String?

    public init(
        id: UUID,
        startedAt: Date,
        completedAt: Date?,
        durationSeconds: TimeInterval,
        rawTranscript: String?,
        finalTranscript: String?,
        wordCount: Int,
        wordsPerMinute: Double,
        language: String,
        modelID: String,
        targetBundleID: String?,
        targetAppName: String?,
        category: DictationCategory,
        insertionOutcome: DictationStatus?,
        correctionCount: Int,
        isPartial: Bool,
        status: DictationStatus,
        recoveryAudioURL: URL?,
        recoveryAudioExpiresAt: Date?,
        errorMessage: String?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.rawTranscript = rawTranscript
        self.finalTranscript = finalTranscript
        self.wordCount = wordCount
        self.wordsPerMinute = wordsPerMinute
        self.language = language
        self.modelID = modelID
        self.targetBundleID = targetBundleID
        self.targetAppName = targetAppName
        self.category = category
        self.insertionOutcome = insertionOutcome
        self.correctionCount = correctionCount
        self.isPartial = isPartial
        self.status = status
        self.recoveryAudioURL = recoveryAudioURL
        self.recoveryAudioExpiresAt = recoveryAudioExpiresAt
        self.errorMessage = errorMessage
    }
}

public enum DictationMetrics {
    public static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    public static func wordsPerMinute(
        wordCount: Int,
        durationSeconds: TimeInterval
    ) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }
        return Double(wordCount) / (durationSeconds / 60)
    }
}
