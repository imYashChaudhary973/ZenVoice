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
import ZenVoiceStorage

/// MCP tools over encrypted `MeetingStore` sidecars.
public struct MeetingStoreMCPSource: MeetingMCPDataSource, @unchecked Sendable {
    private let store: MeetingStore
    private let keyProvider: VaultKeyProviding

    public init(store: MeetingStore, keyProvider: VaultKeyProviding) {
        self.store = store
        self.keyProvider = keyProvider
    }

    public func listReady() throws -> [MeetingMCPSummary] {
        try readyRecords().map(Self.summary)
    }

    public func search(query: String) throws -> [MeetingMCPSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return try listReady() }
        return try readyRecords().compactMap { record in
            guard try matches(record, query: q) else { return nil }
            return Self.summary(record)
        }
    }

    public func get(id: String) throws -> MeetingMCPDetail {
        let record = try readyRecord(id)
        return MeetingMCPDetail(
            summary: Self.summary(record),
            transcript: try store.originalTranscript(
                for: record.id,
                keyProvider: keyProvider
            ) ?? "",
            notes: [],
            followUpDraft: try store.summary(
                for: record.id,
                keyProvider: keyProvider
            )
        )
    }

    public func notes(meetingID: String?) throws -> [MeetingMCPNote] {
        if let meetingID {
            _ = try readyRecord(meetingID)
        }
        return []
    }

    private func readyRecords() throws -> [MeetingStore.Record] {
        try store.all().filter { $0.originalTranscriptCiphertext != nil }
    }

    private func readyRecord(_ id: String) throws -> MeetingStore.Record {
        guard let uuid = UUID(uuidString: id) else {
            throw MeetingError.missingMeeting
        }
        let record = try store.load(id: uuid)
        guard record.originalTranscriptCiphertext != nil else {
            throw MeetingError.missingMeeting
        }
        return record
    }

    private func matches(
        _ record: MeetingStore.Record,
        query: String
    ) throws -> Bool {
        if record.displayTitle.localizedCaseInsensitiveContains(query) {
            return true
        }
        if let original = try store.originalTranscript(
            for: record.id,
            keyProvider: keyProvider
        ), original.localizedCaseInsensitiveContains(query) {
            return true
        }
        if let recap = try store.summary(
            for: record.id,
            keyProvider: keyProvider
        ), recap.localizedCaseInsensitiveContains(query) {
            return true
        }
        return false
    }

    private static func summary(
        _ record: MeetingStore.Record
    ) -> MeetingMCPSummary {
        let ended = record.elapsedSeconds > 0
            ? record.startedAt.addingTimeInterval(record.elapsedSeconds)
            : nil
        return MeetingMCPSummary(
            id: record.id.uuidString,
            title: record.displayTitle,
            startedAt: record.startedAt.ISO8601Format(),
            endedAt: ended?.ISO8601Format(),
            status: record.listStatus.rawValue,
            sourceName: record.captureSource
        )
    }
}
