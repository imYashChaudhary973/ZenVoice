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

public enum AudioArchiveExportError: LocalizedError {
    case noRecords
    case missingAudio(UUID)
    case archiveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noRecords:
            return "Select at least one recording to export."
        case .missingAudio:
            return "A selected recording's audio file is missing."
        case .archiveFailed(let message):
            return "The export could not be written: \(message)"
        }
    }
}

/// Exports selected Audio History records as a ZIP file.
///
/// The export is metadata-first: the manifest carries capture facts only —
/// timestamp, duration, language, model, target app. Transcript text is a
/// separate privacy surface and is included only when the caller explicitly
/// opts in through ``AudioArchiveExportOptions``.
///
/// Zipping uses `NSFileCoordinator`'s `.forUploading` option, which produces a
/// ZIP from a directory without pulling in a third-party archiver.
public enum AudioArchiveExporter {
    /// A single entry in the export manifest.
    private struct ManifestEntry: Encodable {
        let fileName: String
        let startedAt: String
        let durationSeconds: TimeInterval
        let fileSizeBytes: Int64
        let language: String
        let modelID: String
        let targetAppName: String?
        let category: String
        let transcript: String?
    }

    private struct Manifest: Encodable {
        let generatedAt: String
        let recordingCount: Int
        let includesTranscripts: Bool
        let recordings: [ManifestEntry]
    }

    /// Writes the selected records to `destinationURL` as a ZIP file.
    ///
    /// - Parameters:
    ///   - records: The archive records to include.
    ///   - options: Whether transcripts are included.
    ///   - destinationURL: Where to write the `.zip`. Overwritten if present.
    ///   - transcriptProvider: Resolves a dictation ID to its final transcript.
    ///     Consulted only when `options.includeTranscripts` is true.
    public static func export(
        records: [AudioArchiveRecord],
        options: AudioArchiveExportOptions = AudioArchiveExportOptions(),
        to destinationURL: URL,
        fileManager: FileManager = .default,
        transcriptProvider: ((UUID) -> String?)? = nil
    ) throws {
        guard !records.isEmpty else {
            throw AudioArchiveExportError.noRecords
        }

        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "ZenVoiceAudioExport-\(UUID().uuidString)",
                isDirectory: true
            )
        let payloadDirectory = stagingRoot
            .appendingPathComponent("ZenVoiceAudioHistory", isDirectory: true)
        try fileManager.createDirectory(
            at: payloadDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let entries = try stage(
            records: records,
            options: options,
            into: payloadDirectory,
            fileManager: fileManager,
            transcriptProvider: transcriptProvider
        )

        try writeManifest(
            entries: entries,
            options: options,
            into: payloadDirectory
        )

        try zip(
            payloadDirectory,
            to: destinationURL,
            fileManager: fileManager
        )
    }

    /// Copies each record's audio into the staging directory and builds the
    /// matching manifest entries.
    private static func stage(
        records: [AudioArchiveRecord],
        options: AudioArchiveExportOptions,
        into payloadDirectory: URL,
        fileManager: FileManager,
        transcriptProvider: ((UUID) -> String?)?
    ) throws -> [ManifestEntry] {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        stamp.timeZone = TimeZone.current

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var entries: [ManifestEntry] = []
        var usedNames: Set<String> = []

        for record in records {
            guard fileManager.fileExists(atPath: record.audioURL.path) else {
                throw AudioArchiveExportError.missingAudio(record.id)
            }

            // Readable, sortable, collision-free file names.
            var fileName = "\(stamp.string(from: record.startedAt)).wav"
            if usedNames.contains(fileName) {
                let suffix = record.id.uuidString.prefix(8).lowercased()
                fileName = "\(stamp.string(from: record.startedAt))"
                    + "-\(suffix).wav"
            }
            usedNames.insert(fileName)

            try fileManager.copyItem(
                at: record.audioURL,
                to: payloadDirectory.appendingPathComponent(fileName)
            )

            let transcript = options.includeTranscripts
                ? transcriptProvider?(record.dictationID)
                : nil

            entries.append(
                ManifestEntry(
                    fileName: fileName,
                    startedAt: iso.string(from: record.startedAt),
                    durationSeconds: record.durationSeconds,
                    fileSizeBytes: record.fileSize,
                    language: record.language,
                    modelID: record.modelID,
                    targetAppName: record.targetAppName,
                    category: record.category.rawValue,
                    transcript: transcript
                )
            )
        }

        return entries
    }

    private static func writeManifest(
        entries: [ManifestEntry],
        options: AudioArchiveExportOptions,
        into payloadDirectory: URL
    ) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let manifest = Manifest(
            generatedAt: iso.string(from: Date()),
            recordingCount: entries.count,
            includesTranscripts: options.includeTranscripts,
            recordings: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(
            to: payloadDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    /// Zips `directory` to `destinationURL`, replacing any existing file.
    private static func zip(
        _ directory: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        var coordinatorError: NSError?
        var copyError: Error?

        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: [.forUploading],
            error: &coordinatorError
        ) { zippedURL in
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: zippedURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let coordinatorError {
            throw AudioArchiveExportError.archiveFailed(
                coordinatorError.localizedDescription
            )
        }
        if let copyError {
            throw AudioArchiveExportError.archiveFailed(
                copyError.localizedDescription
            )
        }
    }
}
