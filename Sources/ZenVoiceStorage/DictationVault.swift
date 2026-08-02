import Foundation
import SQLite3

public enum DictationVaultError: LocalizedError {
    case database(String)
    case missingRecord
    case invalidRecord

    public var errorDescription: String? {
        switch self {
        case .database(let message):
            return "ZenVoice history database failed: \(message)"
        case .missingRecord:
            return "The ZenVoice history record no longer exists."
        case .invalidRecord:
            return "ZenVoice found an invalid history record."
        }
    }
}

public final class DictationVault: @unchecked Sendable {
    public static let recoveryLifetime: TimeInterval = 24 * 60 * 60

    private let databaseURL: URL
    private let recoveryDirectoryURL: URL
    private let keyProvider: VaultKeyProviding
    private var cipher: TranscriptCipher
    private let queue = DispatchQueue(label: "dev.yashchaudhary.ZenVoice.vault")
    private var database: OpaquePointer?

    public static func live(
        fileManager: FileManager = .default,
        keyProvider: VaultKeyProviding = KeychainVaultKeyProvider()
    ) throws -> DictationVault {
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("ZenVoice", isDirectory: true)
        let dataDirectory = supportDirectory
            .appendingPathComponent("Data", isDirectory: true)
        let recoveryDirectory = supportDirectory
            .appendingPathComponent("Recovery", isDirectory: true)

        try Self.createPrivateDirectory(dataDirectory, fileManager: fileManager)
        try Self.createPrivateDirectory(
            recoveryDirectory,
            fileManager: fileManager
        )

        return try DictationVault(
            databaseURL: dataDirectory.appendingPathComponent("ZenVoice.sqlite"),
            recoveryDirectoryURL: recoveryDirectory,
            keyProvider: keyProvider
        )
    }

    public init(
        databaseURL: URL,
        recoveryDirectoryURL: URL,
        keyProvider: VaultKeyProviding
    ) throws {
        self.databaseURL = databaseURL
        self.recoveryDirectoryURL = recoveryDirectoryURL
        self.keyProvider = keyProvider
        cipher = try TranscriptCipher(keyProvider: keyProvider)

        try Self.createPrivateDirectory(
            databaseURL.deletingLastPathComponent(),
            fileManager: .default
        )
        try Self.createPrivateDirectory(
            recoveryDirectoryURL,
            fileManager: .default
        )
        try openDatabase()
        try migrate()
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: databaseURL.path
        )
    }

    deinit {
        sqlite3_close(database)
    }

    public func recoveryAudioURL(for id: UUID) -> URL {
        recoveryDirectoryURL
            .appendingPathComponent(id.uuidString.lowercased())
            .appendingPathExtension("wav")
    }

    public func begin(_ draft: DictationDraft) throws {
        guard validatedRecoveryAudioURL(
            path: draft.recoveryAudioURL.path,
            id: draft.id
        ) != nil else {
            throw DictationVaultError.invalidRecord
        }
        try queue.sync {
            let sql = """
                INSERT INTO dictations (
                    id, started_at, language, model_id, target_bundle_id,
                    target_app_name, category, status, recovery_audio_path
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            bind(draft.id.uuidString, at: 1, in: statement)
            sqlite3_bind_double(
                statement,
                2,
                draft.startedAt.timeIntervalSince1970
            )
            bind(draft.language, at: 3, in: statement)
            bind(draft.modelID, at: 4, in: statement)
            bind(draft.targetBundleID, at: 5, in: statement)
            bind(draft.targetAppName, at: 6, in: statement)
            bind(draft.category.rawValue, at: 7, in: statement)
            bind(DictationStatus.recording.rawValue, at: 8, in: statement)
            bind(draft.recoveryAudioURL.path, at: 9, in: statement)
            try stepDone(statement)
        }
    }

    public func markTranscribing(
        id: UUID,
        durationSeconds: TimeInterval
    ) throws {
        try update(
            """
            UPDATE dictations
            SET status = ?, duration_seconds = ?
            WHERE id = ?;
            """,
            bindings: { statement in
                bind(DictationStatus.transcribing.rawValue, at: 1, in: statement)
                sqlite3_bind_double(statement, 2, durationSeconds)
                bind(id.uuidString, at: 3, in: statement)
            }
        )
    }

    public func storePartialTranscript(
        id: UUID,
        rawTranscript: String,
        finalTranscript: String,
        correctionCount: Int = 0
    ) throws {
        let wordCount = DictationMetrics.wordCount(in: finalTranscript)
        try queue.sync {
            let encryptedRaw = try cipher.seal(
                rawTranscript,
                context: encryptionContext(id: id, field: "raw")
            )
            let encryptedFinal = try cipher.seal(
                finalTranscript,
                context: encryptionContext(id: id, field: "final")
            )
            let statement = try prepare(
                """
                UPDATE dictations
                SET raw_transcript = ?, final_transcript = ?,
                    word_count = ?, correction_count = ?,
                    is_partial = 1
                WHERE id = ?;
                """
            )
            defer { sqlite3_finalize(statement) }

            bind(encryptedRaw, at: 1, in: statement)
            bind(encryptedFinal, at: 2, in: statement)
            sqlite3_bind_int64(statement, 3, Int64(wordCount))
            sqlite3_bind_int64(statement, 4, Int64(correctionCount))
            bind(id.uuidString, at: 5, in: statement)
            try stepDone(statement)
            try requireChangedRow()
        }
    }

    public func storeTranscript(
        id: UUID,
        rawTranscript: String,
        finalTranscript: String,
        completedAt: Date = Date(),
        correctionCount: Int = 0,
        isPartial: Bool = false
    ) throws {
        let wordCount = DictationMetrics.wordCount(in: finalTranscript)

        try queue.sync {
            let encryptedRaw = try cipher.seal(
                rawTranscript,
                context: encryptionContext(id: id, field: "raw")
            )
            let encryptedFinal = try cipher.seal(
                finalTranscript,
                context: encryptionContext(id: id, field: "final")
            )
            let duration = try durationSeconds(for: id)
            let wordsPerMinute = DictationMetrics.wordsPerMinute(
                wordCount: wordCount,
                durationSeconds: duration
            )
            let statement = try prepare(
                """
                UPDATE dictations
                SET completed_at = ?, raw_transcript = ?,
                    final_transcript = ?, word_count = ?,
                    words_per_minute = ?, correction_count = ?,
                    is_partial = ?, status = ?,
                    error_message = NULL
                WHERE id = ?;
                """
            )
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(
                statement,
                1,
                completedAt.timeIntervalSince1970
            )
            bind(encryptedRaw, at: 2, in: statement)
            bind(encryptedFinal, at: 3, in: statement)
            sqlite3_bind_int64(statement, 4, Int64(wordCount))
            sqlite3_bind_double(statement, 5, wordsPerMinute)
            sqlite3_bind_int64(statement, 6, Int64(correctionCount))
            sqlite3_bind_int(statement, 7, isPartial ? 1 : 0)
            bind(DictationStatus.ready.rawValue, at: 8, in: statement)
            bind(id.uuidString, at: 9, in: statement)
            try stepDone(statement)
            try requireChangedRow()
        }
    }

    public func markInsertion(
        id: UUID,
        outcome: DictationStatus
    ) throws {
        guard outcome == .inserted || outcome == .copiedOnly else {
            throw DictationVaultError.invalidRecord
        }
        try update(
            """
            UPDATE dictations
            SET status = ?, insertion_outcome = ?
            WHERE id = ?;
            """,
            bindings: { statement in
                bind(outcome.rawValue, at: 1, in: statement)
                bind(outcome.rawValue, at: 2, in: statement)
                bind(id.uuidString, at: 3, in: statement)
            }
        )
    }

    public func clearRecoveryAudio(id: UUID) throws {
        try update(
            """
            UPDATE dictations
            SET recovery_audio_path = NULL, recovery_audio_expires_at = NULL
            WHERE id = ?;
            """,
            bindings: { statement in
                bind(id.uuidString, at: 1, in: statement)
            }
        )
    }

    public func deleteRecoveryAudio(id: UUID) throws {
        try deleteRecoveryAudioAndClear(id: id)
    }

    public func suppressPersistence(id: UUID) throws {
        try update(
            """
            UPDATE dictations
            SET persistence_suppressed = 1
            WHERE id = ?;
            """,
            bindings: { statement in
                bind(id.uuidString, at: 1, in: statement)
            }
        )
    }

    public func markFailed(
        id: UUID,
        message: String,
        retainAudio: Bool,
        now: Date = Date(),
        recoveryExpiresAt: Date? = nil
    ) throws {
        // The published promise is 24 hours from the *start of capture*, so the
        // fallback is anchored to the row's own started_at rather than to the
        // failure moment. Anchoring to failure silently added the recording and
        // decode time on top of the stated window.
        try update(
            """
            UPDATE dictations
            SET status = ?, completed_at = ?, error_message = ?,
                recovery_audio_expires_at = CASE
                    WHEN ?5 = 0 THEN NULL
                    WHEN ?6 IS NOT NULL THEN ?6
                    ELSE started_at + ?7
                END
            WHERE id = ?8;
            """,
            bindings: { statement in
                bind(DictationStatus.failed.rawValue, at: 1, in: statement)
                sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
                bind(message, at: 3, in: statement)
                sqlite3_bind_int(statement, 5, retainAudio ? 1 : 0)
                if let recoveryExpiresAt {
                    sqlite3_bind_double(
                        statement,
                        6,
                        recoveryExpiresAt.timeIntervalSince1970
                    )
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                sqlite3_bind_double(statement, 7, Self.recoveryLifetime)
                bind(id.uuidString, at: 8, in: statement)
            }
        )

        if !retainAudio {
            try deleteRecoveryAudioAndClear(id: id)
        }
    }

    public func discard(id: UUID) throws {
        try deleteRecoveryAudioAndClear(id: id)
        try queue.sync {
            let statement = try prepare(
                "DELETE FROM dictations WHERE id = ?;"
            )
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    public func deleteRecord(id: UUID) throws {
        try discard(id: id)
    }

    @discardableResult
    public func deleteRecords(ids: [UUID]) throws -> Int {
        var deletedCount = 0
        for id in Set(ids) {
            guard try record(id: id) != nil else {
                continue
            }
            try discard(id: id)
            deletedCount += 1
        }
        return deletedCount
    }

    public func deleteAll() throws {
        let existingRecovery = try recoveryEntries(whereClause: "1 = 1")
        for entry in existingRecovery {
            if let audioURL = validatedRecoveryAudioURL(
                path: entry.path,
                id: entry.id
            ),
               FileManager.default.fileExists(atPath: audioURL.path) {
                try FileManager.default.removeItem(at: audioURL)
            }
        }

        try queue.sync {
            try execute("DELETE FROM dictations;")
            try execute("DELETE FROM correction_rules;")
            try execute("PRAGMA wal_checkpoint(TRUNCATE);")
            try execute("VACUUM;")
            try keyProvider.deleteKey()
            cipher = try TranscriptCipher(keyProvider: keyProvider)
        }
    }

    @discardableResult
    public func purgeRecords(startedBefore cutoff: Date) throws -> Int {
        let expiredIDs = try recordIDs(
            whereClause: "started_at < ?",
            bindWhere: { statement in
                sqlite3_bind_double(
                    statement,
                    1,
                    cutoff.timeIntervalSince1970
                )
            }
        )
        for id in expiredIDs {
            try discard(id: id)
        }
        return expiredIDs.count
    }

    @discardableResult
    public func recoverInterrupted(
        retainAudio: Bool,
        now: Date = Date()
    ) throws -> Int {
        let interrupted = try interruptedEntries()
        for entry in interrupted {
            if entry.persistenceSuppressed {
                try discard(id: entry.id)
                continue
            }
            try markFailed(
                id: entry.id,
                message: "ZenVoice closed before this dictation completed.",
                retainAudio: retainAudio,
                now: now,
                recoveryExpiresAt:
                    entry.startedAt.addingTimeInterval(Self.recoveryLifetime)
            )
        }
        return interrupted.count
    }

    @discardableResult
    public func purgeExpiredRecoveryAudio(
        now: Date = Date()
    ) throws -> Int {
        let expired = try recoveryEntries(
            whereClause:
                "recovery_audio_expires_at IS NOT NULL AND recovery_audio_expires_at <= ?",
            bindWhere: { statement in
                sqlite3_bind_double(
                    statement,
                    1,
                    now.timeIntervalSince1970
                )
            }
        )
        for entry in expired {
            try deleteRecoveryAudioAndClear(id: entry.id)
        }
        return expired.count
    }

    public func nextRecoveryExpiry() throws -> Date? {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT MIN(recovery_audio_expires_at)
                FROM dictations
                WHERE recovery_audio_expires_at IS NOT NULL;
                """
            )
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return optionalDate(at: 0, in: statement)
        }
    }

    @discardableResult
    public func deleteAllRecoveryAudio() throws -> Int {
        let entries = try recoveryEntries(whereClause: "1 = 1")
        for entry in entries {
            try deleteRecoveryAudioAndClear(id: entry.id)
        }
        return entries.count
    }

    public func recent(limit: Int = 100) throws -> [DictationRecord] {
        try queue.sync {
            try records(
                whereClause: "1 = 1",
                orderAndLimit: "ORDER BY started_at DESC LIMIT ?",
                bindWhere: { statement in
                    sqlite3_bind_int64(statement, 1, Int64(max(1, limit)))
                }
            )
        }
    }

    public func record(id: UUID) throws -> DictationRecord? {
        try queue.sync {
            try records(
                whereClause: "id = ?",
                orderAndLimit: "LIMIT 1",
                bindWhere: { statement in
                    self.bind(id.uuidString, at: 1, in: statement)
                }
            ).first
        }
    }

    public func updateCategory(
        id: UUID,
        category: DictationCategory
    ) throws {
        try update(
            "UPDATE dictations SET category = ? WHERE id = ?;",
            bindings: { statement in
                bind(category.rawValue, at: 1, in: statement)
                bind(id.uuidString, at: 2, in: statement)
            }
        )
    }

    public func insights(
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> LocalInsightsSnapshot {
        let events: [DictationInsightEvent] = try queue.sync {
            let statement = try prepare(
                """
                SELECT started_at, duration_seconds, word_count,
                    correction_count, target_bundle_id, target_app_name,
                    category
                FROM dictations
                WHERE final_transcript IS NOT NULL
                    AND persistence_suppressed = 0
                    AND is_partial = 0
                    AND status IN (?, ?, ?);
                """
            )
            defer { sqlite3_finalize(statement) }
            // "Completed" is the promise Insights makes. A force-quit
            // dictation keeps its live-preview partial and is later marked
            // failed with duration 0, so counting it inflated word totals,
            // streaks, and weighted WPM — and the share card carries those.
            bind(DictationStatus.ready.rawValue, at: 1, in: statement)
            bind(DictationStatus.inserted.rawValue, at: 2, in: statement)
            bind(DictationStatus.copiedOnly.rawValue, at: 3, in: statement)
            var values: [DictationInsightEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let categoryValue = text(at: 6, in: statement),
                      let category = DictationCategory(
                        rawValue: categoryValue
                      ) else {
                    throw DictationVaultError.invalidRecord
                }
                values.append(
                    DictationInsightEvent(
                        startedAt: Date(
                            timeIntervalSince1970:
                                sqlite3_column_double(statement, 0)
                        ),
                        durationSeconds:
                            sqlite3_column_double(statement, 1),
                        wordCount:
                            Int(sqlite3_column_int64(statement, 2)),
                        correctionCount:
                            Int(sqlite3_column_int64(statement, 3)),
                        targetBundleID: text(at: 4, in: statement),
                        targetAppName: text(at: 5, in: statement),
                        category: category
                    )
                )
            }
            return values
        }
        return LocalInsightsSnapshot.calculate(
            events: events,
            now: now,
            calendar: calendar
        )
    }

    public func addCorrectionRule(
        source: String,
        replacement: String,
        languageScope: CorrectionLanguageScope = .all,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) throws {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacement.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !source.isEmpty,
              !replacement.isEmpty,
              source.count <= 120,
              replacement.count <= 120,
              source.caseInsensitiveCompare(replacement) != .orderedSame else {
            throw DictationVaultError.invalidRecord
        }
        try queue.sync {
            let existing = try correctionRulesLocked()
            guard !existing.contains(where: {
                $0.source.caseInsensitiveCompare(source) == .orderedSame
                    && $0.languageScope == languageScope
            }) else {
                throw DictationVaultError.invalidRecord
            }
            let statement = try prepare(
                """
                INSERT INTO correction_rules (
                    id, source_text, replacement_text, language_scope,
                    usage_count, created_at
                ) VALUES (?, ?, ?, ?, 0, ?);
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, at: 1, in: statement)
            bind(
                try cipher.seal(
                    source,
                    context: correctionContext(id: id, field: "source")
                ),
                at: 2,
                in: statement
            )
            bind(
                try cipher.seal(
                    replacement,
                    context: correctionContext(
                        id: id,
                        field: "replacement"
                    )
                ),
                at: 3,
                in: statement
            )
            bind(languageScope.rawValue, at: 4, in: statement)
            sqlite3_bind_double(
                statement,
                5,
                createdAt.timeIntervalSince1970
            )
            try stepDone(statement)
        }
    }

    public func correctionRules() throws -> [CorrectionRule] {
        try queue.sync {
            try correctionRulesLocked()
        }
    }

    public func correctionRules(
        applicableTo activeScope: CorrectionLanguageScope
    ) throws -> [CorrectionRule] {
        try correctionRules().filter {
            $0.languageScope.applies(to: activeScope)
        }
    }

    public func deleteCorrectionRule(id: UUID) throws {
        try queue.sync {
            let statement = try prepare(
                "DELETE FROM correction_rules WHERE id = ?;"
            )
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, at: 1, in: statement)
            try stepDone(statement)
            try requireChangedRow()
        }
    }

    public func deleteAllCorrectionRules() throws {
        try queue.sync {
            try execute("DELETE FROM correction_rules;")
            try execute("PRAGMA wal_checkpoint(TRUNCATE);")
        }
    }

    public func applyCorrections(
        to text: String,
        activeScope: CorrectionLanguageScope = .all
    ) throws -> CorrectionApplication {
        TranscriptCorrectionEngine.apply(
            text,
            rules: try correctionRules(),
            activeScope: activeScope
        )
    }

    public func correctionSuggestions(
        in text: String,
        activeScope: CorrectionLanguageScope
    ) throws -> [CorrectionSuggestion] {
        TranscriptCorrectionEngine.suggestions(
            in: text,
            rules: try correctionRules(),
            activeScope: activeScope
        )
    }

    public func preferredVocabulary(
        activeScope: CorrectionLanguageScope,
        limit: Int = 12
    ) throws -> [String] {
        guard limit > 0 else {
            return []
        }
        var seen = Set<String>()
        return try correctionRules(applicableTo: activeScope)
            .compactMap { rule in
                let term = rule.replacement.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !term.isEmpty,
                      term.count <= 120,
                      seen.insert(term.lowercased()).inserted else {
                    return nil
                }
                return term
            }
            .prefix(limit)
            .map(\.self)
    }

    public func recordCorrectionUsage(
        _ usages: [CorrectionUsage]
    ) throws {
        guard !usages.isEmpty else {
            return
        }
        try queue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            do {
                for usage in usages where usage.count > 0 {
                    let statement = try prepare(
                        """
                        UPDATE correction_rules
                        SET usage_count = usage_count + ?
                        WHERE id = ?;
                        """
                    )
                    defer { sqlite3_finalize(statement) }
                    sqlite3_bind_int64(
                        statement,
                        1,
                        Int64(usage.count)
                    )
                    bind(usage.ruleID.uuidString, at: 2, in: statement)
                    try stepDone(statement)
                }
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
        }
    }

    public func voiceProfile(
        limit: Int = 500,
        calendar: Calendar = .current
    ) throws -> VoiceProfileSnapshot {
        let records = try recent(limit: limit).filter {
            $0.finalTranscript != nil
        }
        return VoiceProfileSnapshot.calculate(
            records: records,
            correctionRules: try correctionRules(),
            calendar: calendar
        )
    }

    private func openDatabase() throws {
        let status = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK else {
            throw DictationVaultError.database(databaseMessage)
        }
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA secure_delete = ON;")
    }

    private func migrate() throws {
        let version = try userVersion()
        try execute(
            """
            CREATE TABLE IF NOT EXISTS dictations (
                id TEXT PRIMARY KEY NOT NULL,
                started_at REAL NOT NULL,
                completed_at REAL,
                duration_seconds REAL NOT NULL DEFAULT 0,
                raw_transcript BLOB,
                final_transcript BLOB,
                word_count INTEGER NOT NULL DEFAULT 0,
                words_per_minute REAL NOT NULL DEFAULT 0,
                language TEXT NOT NULL,
                model_id TEXT NOT NULL,
                target_bundle_id TEXT,
                target_app_name TEXT,
                category TEXT NOT NULL DEFAULT 'other',
                insertion_outcome TEXT,
                correction_count INTEGER NOT NULL DEFAULT 0,
                is_partial INTEGER NOT NULL DEFAULT 0,
                persistence_suppressed INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL,
                recovery_audio_path TEXT,
                recovery_audio_expires_at REAL,
                error_message TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_dictations_started_at
                ON dictations(started_at DESC);
            CREATE INDEX IF NOT EXISTS idx_dictations_status
                ON dictations(status);
            CREATE TABLE IF NOT EXISTS correction_rules (
                id TEXT PRIMARY KEY NOT NULL,
                source_text BLOB NOT NULL,
                replacement_text BLOB NOT NULL,
                usage_count INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            """
        )
        if version == 1 {
            try execute(
                "ALTER TABLE dictations ADD COLUMN is_partial INTEGER NOT NULL DEFAULT 0;"
            )
        }
        if version == 1 || version == 2 {
            try execute(
                "ALTER TABLE dictations ADD COLUMN persistence_suppressed INTEGER NOT NULL DEFAULT 0;"
            )
        }
        if version < 5 {
            if try !correctionRulesHaveLanguageScope() {
                try execute(
                    "ALTER TABLE correction_rules ADD COLUMN language_scope TEXT NOT NULL DEFAULT 'all';"
                )
            }
            try execute("PRAGMA user_version = 5;")
        }
    }

    private func records(
        whereClause: String,
        orderAndLimit: String,
        bindWhere: ((OpaquePointer?) -> Void)? = nil
    ) throws -> [DictationRecord] {
        let statement = try prepare(
            """
            SELECT id, started_at, completed_at, duration_seconds,
                raw_transcript, final_transcript, word_count,
                words_per_minute, language, model_id, target_bundle_id,
                target_app_name, category, insertion_outcome,
                correction_count, is_partial, status, recovery_audio_path,
                recovery_audio_expires_at, error_message
            FROM dictations
            WHERE \(whereClause)
            \(orderAndLimit);
            """
        )
        defer { sqlite3_finalize(statement) }
        bindWhere?(statement)

        var result: [DictationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try decodeRecord(statement))
        }
        return result
    }

    private func decodeRecord(
        _ statement: OpaquePointer?
    ) throws -> DictationRecord {
        guard let idString = text(at: 0, in: statement),
              let id = UUID(uuidString: idString),
              let language = text(at: 8, in: statement),
              let modelID = text(at: 9, in: statement),
              let categoryRaw = text(at: 12, in: statement),
              let category = DictationCategory(rawValue: categoryRaw),
              let statusRaw = text(at: 16, in: statement),
              let status = DictationStatus(rawValue: statusRaw) else {
            throw DictationVaultError.invalidRecord
        }

        let rawTranscript = try encryptedText(
            at: 4,
            in: statement,
            context: encryptionContext(id: id, field: "raw")
        )
        let finalTranscript = try encryptedText(
            at: 5,
            in: statement,
            context: encryptionContext(id: id, field: "final")
        )
        let insertionOutcome = text(at: 13, in: statement)
            .flatMap(DictationStatus.init(rawValue:))
        let recoveryPath = text(at: 17, in: statement)

        return DictationRecord(
            id: id,
            startedAt: Date(
                timeIntervalSince1970: sqlite3_column_double(statement, 1)
            ),
            completedAt: optionalDate(at: 2, in: statement),
            durationSeconds: sqlite3_column_double(statement, 3),
            rawTranscript: rawTranscript,
            finalTranscript: finalTranscript,
            wordCount: Int(sqlite3_column_int64(statement, 6)),
            wordsPerMinute: sqlite3_column_double(statement, 7),
            language: language,
            modelID: modelID,
            targetBundleID: text(at: 10, in: statement),
            targetAppName: text(at: 11, in: statement),
            category: category,
            insertionOutcome: insertionOutcome,
            correctionCount: Int(sqlite3_column_int64(statement, 14)),
            isPartial: sqlite3_column_int(statement, 15) == 1,
            status: status,
            recoveryAudioURL: recoveryPath.flatMap {
                validatedRecoveryAudioURL(path: $0, id: id)
            },
            recoveryAudioExpiresAt: optionalDate(at: 18, in: statement),
            errorMessage: text(at: 19, in: statement)
        )
    }

    private func encryptedText(
        at index: Int32,
        in statement: OpaquePointer?,
        context: String
    ) throws -> String? {
        guard let data = data(at: index, in: statement) else {
            return nil
        }
        return try cipher.open(data, context: context)
    }

    private func durationSeconds(for id: UUID) throws -> TimeInterval {
        let statement = try prepare(
            "SELECT duration_seconds FROM dictations WHERE id = ?;"
        )
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DictationVaultError.missingRecord
        }
        return sqlite3_column_double(statement, 0)
    }

    private func deleteRecoveryAudioAndClear(id: UUID) throws {
        let path = try recoveryEntries(
            whereClause: "id = ?",
            bindWhere: { statement in
                self.bind(id.uuidString, at: 1, in: statement)
            }
        ).first?.path
        if let path,
           let url = validatedRecoveryAudioURL(path: path, id: id),
           FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try clearRecoveryAudio(id: id)
    }

    private func recordIDs(
        whereClause: String,
        bindWhere: ((OpaquePointer?) -> Void)? = nil
    ) throws -> [UUID] {
        try queue.sync {
            let statement = try prepare(
                "SELECT id FROM dictations WHERE \(whereClause);"
            )
            defer { sqlite3_finalize(statement) }
            bindWhere?(statement)
            var ids: [UUID] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let value = text(at: 0, in: statement),
                   let id = UUID(uuidString: value) {
                    ids.append(id)
                }
            }
            return ids
        }
    }

    private func recoveryEntries(
        whereClause: String,
        bindWhere: ((OpaquePointer?) -> Void)? = nil
    ) throws -> [(id: UUID, path: String)] {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT id, recovery_audio_path
                FROM dictations
                WHERE \(whereClause) AND recovery_audio_path IS NOT NULL;
                """
            )
            defer { sqlite3_finalize(statement) }
            bindWhere?(statement)
            var entries: [(UUID, String)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let idValue = text(at: 0, in: statement),
                   let id = UUID(uuidString: idValue),
                   let path = text(at: 1, in: statement) {
                    entries.append((id, path))
                }
            }
            return entries
        }
    }

    private func interruptedEntries() throws -> [
        (id: UUID, startedAt: Date, persistenceSuppressed: Bool)
    ] {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT id, started_at, persistence_suppressed
                FROM dictations
                WHERE status IN ('recording', 'transcribing');
                """
            )
            defer { sqlite3_finalize(statement) }
            var entries: [(UUID, Date, Bool)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let idValue = text(at: 0, in: statement),
                   let id = UUID(uuidString: idValue) {
                    entries.append(
                        (
                            id,
                            Date(
                                timeIntervalSince1970:
                                    sqlite3_column_double(statement, 1)
                            ),
                            sqlite3_column_int(statement, 2) == 1
                        )
                    )
                }
            }
            return entries
        }
    }

    private func validatedRecoveryAudioURL(path: String, id: UUID) -> URL? {
        let supplied = URL(fileURLWithPath: path).standardizedFileURL
        let expected = recoveryAudioURL(for: id).standardizedFileURL
        guard supplied.path == expected.path,
              supplied.deletingLastPathComponent().path
                == recoveryDirectoryURL.standardizedFileURL.path else {
            return nil
        }
        return expected
    }

    private func encryptionContext(id: UUID, field: String) -> String {
        "ZenVoice.dictation.v2|\(id.uuidString.lowercased())|\(field)"
    }

    private func correctionContext(id: UUID, field: String) -> String {
        "ZenVoice.correction.v1|\(id.uuidString.lowercased())|\(field)"
    }

    private func correctionRulesLocked() throws -> [CorrectionRule] {
        let statement = try prepare(
            """
            SELECT id, source_text, replacement_text, language_scope,
                   usage_count, created_at
            FROM correction_rules
            ORDER BY usage_count DESC, created_at ASC;
            """
        )
        defer { sqlite3_finalize(statement) }
        var rules: [CorrectionRule] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idValue = text(at: 0, in: statement),
                  let id = UUID(uuidString: idValue),
                  let sourceData = data(at: 1, in: statement),
                  let replacementData = data(at: 2, in: statement),
                  let languageScopeValue = text(at: 3, in: statement),
                  let languageScope = CorrectionLanguageScope(
                      rawValue: languageScopeValue
                  ) else {
                throw DictationVaultError.invalidRecord
            }
            rules.append(
                CorrectionRule(
                    id: id,
                    source: try cipher.open(
                        sourceData,
                        context: correctionContext(
                            id: id,
                            field: "source"
                        )
                    ),
                    replacement: try cipher.open(
                        replacementData,
                        context: correctionContext(
                            id: id,
                            field: "replacement"
                        )
                    ),
                    languageScope: languageScope,
                    usageCount:
                        Int(sqlite3_column_int64(statement, 4)),
                    createdAt: Date(
                        timeIntervalSince1970:
                            sqlite3_column_double(statement, 5)
                    )
                )
            )
        }
        return rules
    }

    private func userVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DictationVaultError.database(databaseMessage)
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func correctionRulesHaveLanguageScope() throws -> Bool {
        let statement = try prepare("PRAGMA table_info(correction_rules);")
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if text(at: 1, in: statement) == "language_scope" {
                return true
            }
        }
        return false
    }

    private func update(
        _ sql: String,
        bindings: (OpaquePointer?) -> Void
    ) throws {
        try queue.sync {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bindings(statement)
            try stepDone(statement)
            try requireChangedRow()
        }
    }

    private func requireChangedRow() throws {
        guard sqlite3_changes(database) > 0 else {
            throw DictationVaultError.missingRecord
        }
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &error)
        guard status == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? databaseMessage
            sqlite3_free(error)
            throw DictationVaultError.database(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK
        else {
            throw DictationVaultError.database(databaseMessage)
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DictationVaultError.database(databaseMessage)
        }
    }

    private func bind(
        _ value: String?,
        at index: Int32,
        in statement: OpaquePointer?
    ) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
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
              let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func data(
        at index: Int32,
        in statement: OpaquePointer?
    ) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        return Data(
            bytes: bytes,
            count: Int(sqlite3_column_bytes(statement, index))
        )
    }

    private func optionalDate(
        at index: Int32,
        in statement: OpaquePointer?
    ) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Date(
            timeIntervalSince1970: sqlite3_column_double(statement, index)
        )
    }

    private var databaseMessage: String {
        database.map { String(cString: sqlite3_errmsg($0)) }
            ?? "Unknown SQLite error"
    }

    private static func createPrivateDirectory(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }
}

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
