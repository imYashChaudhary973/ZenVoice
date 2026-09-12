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
import ZenVoiceCore

/// Local meeting audio and sidecar metadata. Not dictation History.
///
/// WAVs are unencrypted (same honesty as Audio History). Original transcript
/// and recap are encrypted with the vault key.
public struct MeetingStore {
    public static let maximumDuration: TimeInterval = 90 * 60
    public static let sampleRate = 16_000
    public static let bytesPerSample = 4
    /// Mic + system audio, 90 minutes each.
    public static let reservedAudioBytes: Int64 =
        Int64(sampleRate * bytesPerSample) * Int64(maximumDuration) * 2

    public enum Status: String, Codable, Equatable, Sendable {
        case recording
        case paused
        case incomplete
        case complete
        case transcribing
        case failed
        case completeAtCap
    }

    public struct Record: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var startedAt: Date
        public var status: Status
        public var elapsedSeconds: TimeInterval
        public var title: String?
        public var engineID: String?
        public var captureSource: String
        public var youName: String?
        public var themName: String?
        public var originalTranscriptCiphertext: Data?
        public var summaryCiphertext: Data?

        public init(
            id: UUID = UUID(),
            startedAt: Date = Date(),
            status: Status,
            elapsedSeconds: TimeInterval = 0,
            title: String? = nil,
            engineID: String? = nil,
            captureSource: String = "local",
            youName: String? = nil,
            themName: String? = nil,
            originalTranscriptCiphertext: Data? = nil,
            summaryCiphertext: Data? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.status = status
            self.elapsedSeconds = elapsedSeconds
            self.title = title
            self.engineID = engineID
            self.captureSource = captureSource
            self.youName = youName
            self.themName = themName
            self.originalTranscriptCiphertext = originalTranscriptCiphertext
            self.summaryCiphertext = summaryCiphertext
        }

        public enum ListStatus: String, Equatable, Sendable {
            case recording
            case transcribed
            case summarized
            case failed
        }

        public var listStatus: ListStatus {
            if status == .failed { return .failed }
            if summaryCiphertext != nil { return .summarized }
            if originalTranscriptCiphertext != nil { return .transcribed }
            return .recording
        }

        public var displayTitle: String {
            if let title, !title.isEmpty { return title }
            return startedAt.formatted(date: .abbreviated, time: .shortened)
        }
    }

    public struct Inventory: Equatable, Sendable {
        public let meetingCount: Int
        public let audioBytes: Int64
    }

    public enum StoreError: LocalizedError {
        case insufficientDisk
        case escapedDirectory
        case originalTranscriptLocked
        case io(String)

        public var errorDescription: String? {
            switch self {
            case .insufficientDisk:
                return "Not enough free disk for a 90-minute meeting."
            case .escapedDirectory:
                return "Meeting path left the Meetings folder."
            case .originalTranscriptLocked:
                return "The original meeting transcript cannot be replaced."
            case .io(let message):
                return message
            }
        }
    }

    public let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public static func live(
        fileManager: FileManager = .default,
        policy: BundleIdentifierPolicy
    ) throws -> MeetingStore {
        let root = try RuntimeIdentity.applicationSupportRoot(
            fileManager: fileManager,
            policy: policy
        )
        let directory = root.appendingPathComponent(
            "Meetings",
            isDirectory: true
        )
        let store = MeetingStore(
            directoryURL: directory,
            fileManager: fileManager
        )
        try store.ensureDirectory()
        return store
    }

    public static func hasRoom(availableBytes: Int64) -> Bool {
        availableBytes >= reservedAudioBytes
    }

    public static func displayedElapsed(
        accumulated: TimeInterval,
        runningSince: Date?,
        now: Date
    ) -> TimeInterval {
        let live = runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, accumulated) + live
    }

    public static func shouldStopAtCap(_ elapsed: TimeInterval) -> Bool {
        elapsed >= maximumDuration
    }

    public func youAudioURL(for id: UUID) -> URL {
        confinedURL(id: id, suffix: "you", ext: "wav")
    }

    public func themAudioURL(for id: UUID) -> URL {
        confinedURL(id: id, suffix: "them", ext: "wav")
    }

    public func sidecarURL(for id: UUID) -> URL {
        confinedURL(id: id, suffix: nil, ext: "json")
    }

    public func createRecording(
        now: Date = Date(),
        availableBytes: Int64? = nil
    ) throws -> Record {
        try ensureDirectory()
        let free = try availableBytes ?? volumeAvailableBytes()
        guard Self.hasRoom(availableBytes: free) else {
            throw StoreError.insufficientDisk
        }
        let record = Record(startedAt: now, status: .recording)
        try save(record)
        return record
    }

    public func save(_ record: Record) throws {
        try ensureDirectory()
        let url = sidecarURL(for: record.id)
        try confirmInsideDirectory(url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: url, options: .atomic)
    }

    public func load(id: UUID) throws -> Record {
        let url = sidecarURL(for: id)
        try confirmInsideDirectory(url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Record.self, from: Data(contentsOf: url))
    }

    public static func originalTranscriptContext(_ id: UUID) -> String {
        "meeting.original.\(id.uuidString.lowercased())"
    }

    public static func summaryContext(_ id: UUID) -> String {
        "meeting.summary.\(id.uuidString.lowercased())"
    }

    public func setOriginalTranscript(
        _ text: String,
        for id: UUID,
        engineID: String? = nil,
        keyProvider: VaultKeyProviding
    ) throws {
        var record = try load(id: id)
        guard record.originalTranscriptCiphertext == nil else {
            throw StoreError.originalTranscriptLocked
        }
        let cipher = try TranscriptCipher(keyProvider: keyProvider)
        record.originalTranscriptCiphertext = try cipher.seal(
            text,
            context: Self.originalTranscriptContext(id)
        )
        if let engineID {
            record.engineID = engineID
        }
        try save(record)
    }

    public func originalTranscript(
        for id: UUID,
        keyProvider: VaultKeyProviding
    ) throws -> String? {
        let record = try load(id: id)
        guard let data = record.originalTranscriptCiphertext else {
            return nil
        }
        let cipher = try TranscriptCipher(keyProvider: keyProvider)
        return try cipher.open(
            data,
            context: Self.originalTranscriptContext(id)
        )
    }

    public func setSummary(
        _ text: String,
        for id: UUID,
        keyProvider: VaultKeyProviding
    ) throws {
        var record = try load(id: id)
        guard record.originalTranscriptCiphertext != nil else {
            throw StoreError.io("Transcribe the meeting before summarizing it.")
        }
        let cipher = try TranscriptCipher(keyProvider: keyProvider)
        record.summaryCiphertext = try cipher.seal(
            text,
            context: Self.summaryContext(id)
        )
        try save(record)
    }

    public func summary(
        for id: UUID,
        keyProvider: VaultKeyProviding
    ) throws -> String? {
        let record = try load(id: id)
        guard let data = record.summaryCiphertext else {
            return nil
        }
        let cipher = try TranscriptCipher(keyProvider: keyProvider)
        return try cipher.open(
            data,
            context: Self.summaryContext(id)
        )
    }

    public func markIncompleteIfOpen() throws {
        for record in try all()
        where record.status == .recording
            || record.status == .paused
            || record.status == .transcribing {
            var closed = record
            closed.status = .incomplete
            try save(closed)
        }
    }

    public func all() throws -> [Record] {
        try ensureDirectory()
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Record? in
                try confirmInsideDirectory(url)
                return try decoder.decode(
                    Record.self,
                    from: Data(contentsOf: url)
                )
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func inventory() throws -> Inventory {
        let records = try all()
        var audioBytes: Int64 = 0
        for record in records {
            audioBytes += fileSize(youAudioURL(for: record.id))
            audioBytes += fileSize(themAudioURL(for: record.id))
        }
        return Inventory(meetingCount: records.count, audioBytes: audioBytes)
    }

    public func removeRecordingArtifacts(id: UUID) throws {
        for url in [
            youAudioURL(for: id),
            themAudioURL(for: id),
            sidecarURL(for: id)
        ] {
            try confirmInsideDirectory(url)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path),
              let size = try? fileManager.attributesOfItem(
                atPath: url.path
              )[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private func confinedURL(id: UUID, suffix: String?, ext: String) -> URL {
        let name = suffix.map {
            "\(id.uuidString.lowercased()).\($0)"
        } ?? id.uuidString.lowercased()
        return directoryURL
            .appendingPathComponent(name)
            .appendingPathExtension(ext)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let resolved = directoryURL.standardizedFileURL
            .resolvingSymlinksInPath()
        let parent = directoryURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(parent.path + "/") else {
            throw StoreError.escapedDirectory
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: resolved.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw StoreError.io("Meetings folder is missing.")
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: resolved.path
        )
    }

    private func confirmInsideDirectory(_ url: URL) throws {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let root = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw StoreError.escapedDirectory
        }
    }

    private func volumeAvailableBytes() throws -> Int64 {
        let values = try directoryURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let free = values.volumeAvailableCapacityForImportantUsage else {
            throw StoreError.io("Could not read free disk space.")
        }
        return free
    }
}
