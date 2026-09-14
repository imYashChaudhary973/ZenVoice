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
import NaturalLanguage
import SQLite3

public enum MeetingIndexError: LocalizedError {
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .database(let message):
            return "Meeting index failed: \(message)"
        }
    }
}

/// FTS5 search index for meeting transcripts. Lives at `Meetings/index.sqlite`.
public actor MeetingIndex {
    private var database: OpaquePointer?

    public init(directoryURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let databaseURL = directoryURL.appendingPathComponent("index.sqlite")
        let status = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK else {
            throw MeetingIndexError.database(databaseMessage)
        }
        sqlite3_busy_timeout(database, 5000)
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA secure_delete = ON;")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS meetings (
                id TEXT PRIMARY KEY NOT NULL,
                original TEXT NOT NULL,
                recap TEXT NOT NULL,
                embedding BLOB
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS meetings_fts USING fts5(
                id UNINDEXED,
                original,
                recap
            );
            """
        )
        // Existing indexes stored live transcripts in sqlite. Blank them.
        try execute("UPDATE meetings SET original = '', recap = '';")
        try execute("DELETE FROM meetings_fts;")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: databaseURL.path
        )
    }

    deinit {
        sqlite3_close_v2(database)
    }

    public func upsert(id: UUID, original: String, recap: String) throws {
        let key = id.uuidString
        try transaction {
            try run(
                """
                INSERT INTO meetings(id, original, recap, embedding)
                VALUES (?, '', '', ?)
                ON CONFLICT(id) DO UPDATE SET
                    original = '',
                    recap = '',
                    embedding = excluded.embedding;
                """
            ) { statement in
                bind(key, at: 1, in: statement)
                if let blob = Self.sentenceEmbeddingBlob(
                    original: original,
                    recap: recap
                ) {
                    bind(blob, at: 2, in: statement)
                } else {
                    sqlite3_bind_null(statement, 2)
                }
            }
        }
    }

    public func search(
        query: String,
        limit: Int
    ) throws -> [(id: UUID, snippet: String)] {
        guard limit > 0, let match = Self.ftsQuery(query) else { return [] }
        let statement = try prepare(
            """
            SELECT id, snippet(meetings_fts, 1, '', '', '…', 16)
            FROM meetings_fts
            WHERE meetings_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(match, at: 1, in: statement)
        sqlite3_bind_int64(statement, 2, Int64(limit))

        var hits: [(id: UUID, snippet: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = text(at: 0, in: statement),
                  let id = UUID(uuidString: idText)
            else { continue }
            hits.append((id, text(at: 1, in: statement) ?? ""))
        }
        return hits
    }

    public func delete(id: UUID) throws {
        let key = id.uuidString
        try transaction {
            try run("DELETE FROM meetings_fts WHERE id = ?;") { statement in
                bind(key, at: 1, in: statement)
            }
            try run("DELETE FROM meetings WHERE id = ?;") { statement in
                bind(key, at: 1, in: statement)
            }
        }
    }

    private static func ftsQuery(_ raw: String) -> String? {
        let terms = raw.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        // ponytail: alphanumeric tokens only; quoted phrase AND if operators needed
        return terms.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }
            .joined(separator: " AND ")
    }

    private static func sentenceEmbeddingBlob(
        original: String,
        recap: String
    ) -> Data? {
        let text = [original, recap]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        guard #available(macOS 14.0, *) else { return nil }
        let language = NLLanguageRecognizer.dominantLanguage(for: text) ?? .english
        guard let model = NLEmbedding.sentenceEmbedding(for: language)
            ?? NLEmbedding.sentenceEmbedding(for: .english),
            let vector = model.vector(for: text)
        else { return nil }
        let floats = vector.map { Float32($0) }
        return floats.withUnsafeBytes { Data($0) }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func run(
        _ sql: String,
        bind bindings: (OpaquePointer?) -> Void
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw MeetingIndexError.database(databaseMessage)
        }
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &error)
        guard status == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? databaseMessage
            sqlite3_free(error)
            throw MeetingIndexError.database(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK
        else {
            throw MeetingIndexError.database(databaseMessage)
        }
        return statement
    }

    private func bind(
        _ value: String,
        at index: Int32,
        in statement: OpaquePointer?
    ) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bind(
        _ value: Data,
        at index: Int32,
        in statement: OpaquePointer?
    ) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                index,
                bytes.baseAddress,
                Int32(bytes.count),
                sqliteTransient
            )
        }
    }

    private func text(
        at index: Int32,
        in statement: OpaquePointer?
    ) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: pointer)
    }

    private var databaseMessage: String {
        database.map { String(cString: sqlite3_errmsg($0)) }
            ?? "Unknown SQLite error"
    }
}

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
