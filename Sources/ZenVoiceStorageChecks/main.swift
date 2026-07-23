import Foundation
import SQLite3
import ZenVoiceStorage

private final class StaticKeyProvider: VaultKeyProviding {
    private var keyData: Data? = Data(repeating: 0x5A, count: 32)
    private var generation: UInt8 = 0x5A

    func loadOrCreateKeyData() throws -> Data {
        if let keyData {
            return keyData
        }
        generation &+= 1
        let replacement = Data(repeating: generation, count: 32)
        keyData = replacement
        return replacement
    }

    func deleteKey() throws {
        keyData = nil
    }
}

private struct VaultFixture {
    let directoryURL: URL
    let databaseURL: URL
    let keyProvider: StaticKeyProvider
    let vault: DictationVault

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        databaseURL = directoryURL.appendingPathComponent("test.sqlite")
        keyProvider = StaticKeyProvider()
        vault = try DictationVault(
            databaseURL: databaseURL,
            recoveryDirectoryURL: directoryURL
                .appendingPathComponent("Recovery", isDirectory: true),
            keyProvider: keyProvider
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private func require(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String
) throws {
    guard try condition() else {
        throw CheckError.failed(message)
    }
}

private enum CheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private func checkEncryptedStorage() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_000),
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: "com.apple.TextEdit",
            targetAppName: "TextEdit",
            category: .documents,
            recoveryAudioURL: audioURL
        )
    )
    try fixture.vault.markTranscribing(id: id, durationSeconds: 30)
    try fixture.vault.storeTranscript(
        id: id,
        rawTranscript: "hello local world",
        finalTranscript: "Hello local world.",
        completedAt: Date(timeIntervalSince1970: 1_030),
        correctionCount: 1
    )
    try fixture.vault.markInsertion(id: id, outcome: .inserted)

    guard let record = try fixture.vault.record(id: id) else {
        throw CheckError.failed("stored record is missing")
    }
    try require(record.finalTranscript == "Hello local world.", "final text")
    try require(record.rawTranscript == "hello local world", "raw text")
    try require(record.wordCount == 3, "word count")
    try require(record.wordsPerMinute == 6, "words per minute")
    try require(record.status == .inserted, "insertion status")
    try require(record.correctionCount == 1, "correction count")

    for suffix in ["", "-wal", "-shm"] {
        let fileURL = URL(fileURLWithPath: fixture.databaseURL.path + suffix)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            continue
        }
        let databaseData = try Data(contentsOf: fileURL)
        let databaseText = String(decoding: databaseData, as: UTF8.self)
        try require(
            !databaseText.contains("Hello local world"),
            "final transcript leaked into plaintext database\(suffix)"
        )
        try require(
            !databaseText.contains("hello local world"),
            "raw transcript leaked into plaintext database\(suffix)"
        )
    }
}

private func checkRecoveryExpiry() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let startedAt = Date(timeIntervalSince1970: 9_000)
    let audioURL = fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: id,
            startedAt: startedAt,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: audioURL
        )
    )

    let recoveryTime = Date(timeIntervalSince1970: 10_000)
    try require(
        try fixture.vault.recoverInterrupted(
            retainAudio: true,
            now: recoveryTime
        ) == 1,
        "interrupted record was not recovered"
    )
    guard let failed = try fixture.vault.record(id: id) else {
        throw CheckError.failed("failed record is missing")
    }
    try require(failed.status == .failed, "recovered status")
    try require(failed.recoveryAudioURL == audioURL, "recovery audio path")
    try require(
        failed.recoveryAudioExpiresAt
            == startedAt.addingTimeInterval(DictationVault.recoveryLifetime),
        "interrupted recovery expiry was extended from relaunch time"
    )
    try require(
        FileManager.default.fileExists(atPath: audioURL.path),
        "recovery audio was deleted too early"
    )

    try require(
        try fixture.vault.purgeExpiredRecoveryAudio(
            now: recoveryTime.addingTimeInterval(
                DictationVault.recoveryLifetime + 1
            )
        ) == 1,
        "expired audio was not purged"
    )
    try require(
        !FileManager.default.fileExists(atPath: audioURL.path),
        "expired audio remains on disk"
    )
    try require(
        try fixture.vault.record(id: id)?.recoveryAudioURL == nil,
        "expired audio path remains in database"
    )

    let staleID = UUID()
    let staleAudioURL = fixture.vault.recoveryAudioURL(for: staleID)
    try Data("stale audio".utf8).write(to: staleAudioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: staleID,
            startedAt: recoveryTime.addingTimeInterval(
                -(DictationVault.recoveryLifetime + 1)
            ),
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: staleAudioURL
        )
    )
    try require(
        try fixture.vault.recoverInterrupted(
            retainAudio: true,
            now: recoveryTime
        ) == 1,
        "stale interrupted record was not recovered"
    )
    try require(
        try fixture.vault.purgeExpiredRecoveryAudio(now: recoveryTime) == 1,
        "already-expired interrupted audio was retained"
    )
}

private func checkPrivacySuppressionAndRecoveryCleanup() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let privateID = UUID()
    let privateAudioURL = fixture.vault.recoveryAudioURL(for: privateID)
    try Data("private audio".utf8).write(to: privateAudioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: privateID,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: privateAudioURL
        )
    )
    try fixture.vault.suppressPersistence(id: privateID)
    try require(
        try fixture.vault.recoverInterrupted(retainAudio: true) == 1,
        "suppressed dictation was not handled during recovery"
    )
    try require(
        try fixture.vault.record(id: privateID) == nil,
        "suppressed dictation survived restart recovery"
    )
    try require(
        !FileManager.default.fileExists(atPath: privateAudioURL.path),
        "suppressed recovery audio survived restart recovery"
    )

    let firstID = UUID()
    let secondID = UUID()
    for id in [firstID, secondID] {
        let audioURL = fixture.vault.recoveryAudioURL(for: id)
        try Data("failed audio".utf8).write(to: audioURL)
        try fixture.vault.begin(
            DictationDraft(
                id: id,
                language: "en",
                modelID: "whisper-base.en",
                targetBundleID: nil,
                targetAppName: nil,
                recoveryAudioURL: audioURL
            )
        )
        try fixture.vault.markFailed(
            id: id,
            message: "test",
            retainAudio: true
        )
    }
    try require(
        try fixture.vault.deleteAllRecoveryAudio() == 2,
        "disabling recovery did not remove every retained recording"
    )
    for id in [firstID, secondID] {
        try require(
            try fixture.vault.record(id: id)?.recoveryAudioURL == nil,
            "disabled recovery left an audio path"
        )
    }
}

private func checkDiscard() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: id,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: audioURL
        )
    )
    try fixture.vault.discard(id: id)

    try require(try fixture.vault.record(id: id) == nil, "discarded record")
    try require(
        !FileManager.default.fileExists(atPath: audioURL.path),
        "discarded audio remains on disk"
    )
}

private func checkDeleteAllRotatesVault() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let firstID = UUID()
    let firstAudioURL = fixture.vault.recoveryAudioURL(for: firstID)
    try Data("audio".utf8).write(to: firstAudioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: firstID,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: firstAudioURL
        )
    )
    try fixture.vault.markTranscribing(
        id: firstID,
        durationSeconds: 10
    )
    try fixture.vault.storeTranscript(
        id: firstID,
        rawTranscript: "private history",
        finalTranscript: "Private history."
    )

    let originalKey = try fixture.keyProvider.loadOrCreateKeyData()
    try fixture.vault.deleteAll()
    let replacementKey = try fixture.keyProvider.loadOrCreateKeyData()

    try require(
        try fixture.vault.recent().isEmpty,
        "delete all left history records"
    )
    try require(
        !FileManager.default.fileExists(atPath: firstAudioURL.path),
        "delete all left recovery audio"
    )
    try require(
        originalKey != replacementKey,
        "delete all did not rotate the encryption key"
    )
}

private func checkHistoryPreferencesDefaults() throws {
    let suiteName = "ZenVoiceStorageChecks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw CheckError.failed("could not create isolated user defaults")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let preferences = HistoryPreferences(defaults: defaults)
    try require(preferences.hasMadeHistoryChoice, "history default not active")
    try require(preferences.isHistoryEnabled, "history disabled by default")
    try require(preferences.retainsFailedAudio, "failed audio default")

    preferences.isHistoryEnabled = true
    preferences.isPrivateModeEnabled = true
    try require(preferences.hasMadeHistoryChoice, "history choice not saved")
    try require(
        preferences.hasEverEnabledHistory,
        "history activation not recorded"
    )
    try require(preferences.isPrivateModeEnabled, "private mode not saved")

    preferences.isHistoryEnabled = false
    let reloaded = HistoryPreferences(defaults: defaults)
    try require(!reloaded.isHistoryEnabled, "explicit pause was not preserved")
}

private func executeSQL(_ sql: String, databaseURL: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
        throw CheckError.failed("could not open verification database")
    }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw CheckError.failed("verification SQL failed")
    }
}

private func checkVersionTwoMigration() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let recoveryURL = directoryURL
        .appendingPathComponent("Recovery", isDirectory: true)
    let databaseURL = directoryURL.appendingPathComponent("version2.sqlite")
    try FileManager.default.createDirectory(
        at: recoveryURL,
        withIntermediateDirectories: true
    )
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    try executeSQL(
        """
        CREATE TABLE dictations (
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
            status TEXT NOT NULL,
            recovery_audio_path TEXT,
            recovery_audio_expires_at REAL,
            error_message TEXT
        );
        PRAGMA user_version = 2;
        """,
        databaseURL: databaseURL
    )
    let vault = try DictationVault(
        databaseURL: databaseURL,
        recoveryDirectoryURL: recoveryURL,
        keyProvider: StaticKeyProvider()
    )
    let id = UUID()
    let audioURL = vault.recoveryAudioURL(for: id)
    try Data("private audio".utf8).write(to: audioURL)
    try vault.begin(
        DictationDraft(
            id: id,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: audioURL
        )
    )
    try vault.suppressPersistence(id: id)
    try require(
        try vault.recoverInterrupted(retainAudio: true) == 1,
        "version-two vault did not migrate privacy suppression"
    )
}

private func checkPartialAndCipherBinding() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: id,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: audioURL
        )
    )
    try fixture.vault.markTranscribing(id: id, durationSeconds: 10)
    try fixture.vault.storeTranscript(
        id: id,
        rawTranscript: "partial raw",
        finalTranscript: "Partial final",
        isPartial: true
    )
    try require(
        try fixture.vault.record(id: id)?.isPartial == true,
        "partial transcript flag was not stored"
    )

    try executeSQL(
        """
        UPDATE dictations
        SET raw_transcript = final_transcript,
            final_transcript = raw_transcript
        WHERE id = '\(id.uuidString)';
        """,
        databaseURL: fixture.databaseURL
    )
    do {
        _ = try fixture.vault.record(id: id)
        throw CheckError.failed("swapped ciphertext fields were accepted")
    } catch let checkError as CheckError {
        throw checkError
    } catch {
        // Expected: authenticated field context rejects the swap.
    }

    try fixture.vault.deleteAll()
    try require(
        try fixture.vault.recent().isEmpty,
        "corrupt ciphertext blocked delete all"
    )
}

private func checkRecoveryPathConfinement() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let outsideURL = fixture.directoryURL
        .appendingPathComponent("outside.wav")
    try Data("do not delete".utf8).write(to: outsideURL)
    do {
        try fixture.vault.begin(
            DictationDraft(
                id: id,
                language: "en",
                modelID: "whisper-base.en",
                targetBundleID: nil,
                targetAppName: nil,
                recoveryAudioURL: outsideURL
            )
        )
        throw CheckError.failed("external recovery path was accepted")
    } catch let checkError as CheckError {
        throw checkError
    } catch {
        // Expected: recovery files must use the vault-generated UUID path.
    }
    try require(
        FileManager.default.fileExists(atPath: outsideURL.path),
        "external file was modified"
    )
}

private func checkLocalInsights() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_721_865_600)
    let day = calendar.startOfDay(for: now)
    let events = [
        DictationInsightEvent(
            startedAt: day,
            durationSeconds: 60,
            wordCount: 10,
            correctionCount: 1,
            targetBundleID: "com.apple.TextEdit",
            targetAppName: "TextEdit",
            category: .documents
        ),
        DictationInsightEvent(
            startedAt: calendar.date(
                byAdding: .day,
                value: -1,
                to: day
            )!,
            durationSeconds: 120,
            wordCount: 20,
            correctionCount: 2,
            targetBundleID: "com.apple.TextEdit",
            targetAppName: "TextEdit",
            category: .documents
        ),
        DictationInsightEvent(
            startedAt: calendar.date(
                byAdding: .day,
                value: -2,
                to: day
            )!,
            durationSeconds: 30,
            wordCount: 8,
            correctionCount: 0,
            targetBundleID: "com.openai.chatgpt",
            targetAppName: "ChatGPT",
            category: .aiPrompts
        ),
        DictationInsightEvent(
            startedAt: calendar.date(
                byAdding: .day,
                value: -3,
                to: day
            )!,
            durationSeconds: 10,
            wordCount: 4,
            correctionCount: 0,
            targetBundleID: nil,
            targetAppName: nil,
            category: .other
        )
    ]
    let snapshot = LocalInsightsSnapshot.calculate(
        events: events,
        now: now,
        calendar: calendar
    )
    try require(snapshot.dictationCount == 4, "insight dictation count")
    try require(snapshot.totalWordCount == 42, "insight total words")
    try require(
        abs(snapshot.weightedWordsPerMinute - (42 / (220 / 60))) < 0.001,
        "weighted insight words per minute"
    )
    try require(snapshot.correctionCount == 3, "insight corrections")
    try require(snapshot.distinctApplicationCount == 2, "distinct apps")
    try require(snapshot.currentStreakDays == 3, "current streak")
    try require(snapshot.longestStreakDays == 3, "longest streak")
    try require(snapshot.recentActivity.count == 7, "seven-day activity")
    try require(
        snapshot.categories.first?.category == .documents,
        "category ranking"
    )
    try require(
        ApplicationCategoryClassifier.category(
            bundleIdentifier: "com.openai.chatgpt",
            appName: "ChatGPT"
        ) == .aiPrompts,
        "AI application classification"
    )
    try require(
        ApplicationCategoryClassifier.category(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        ) == .other,
        "unknown application classification"
    )
}

private func checkCategoryCorrection() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: id,
            language: "en",
            modelID: "whisper-base-en",
            targetBundleID: "com.apple.TextEdit",
            targetAppName: "TextEdit",
            category: .documents,
            recoveryAudioURL: audioURL
        )
    )
    try fixture.vault.markTranscribing(id: id, durationSeconds: 60)
    try fixture.vault.storeTranscript(
        id: id,
        rawTranscript: "one two three four five",
        finalTranscript: "One two three four five."
    )
    try fixture.vault.updateCategory(id: id, category: .workMessages)

    try require(
        try fixture.vault.record(id: id)?.category == .workMessages,
        "corrected category was not stored"
    )
    let snapshot = try fixture.vault.insights()
    try require(snapshot.totalWordCount == 5, "vault insight words")
    try require(
        snapshot.categories.first?.category == .workMessages,
        "vault insight did not use corrected category"
    )
}

do {
    try checkEncryptedStorage()
    try checkRecoveryExpiry()
    try checkDiscard()
    try checkDeleteAllRotatesVault()
    try checkHistoryPreferencesDefaults()
    try checkVersionTwoMigration()
    try checkPartialAndCipherBinding()
    try checkRecoveryPathConfinement()
    try checkPrivacySuppressionAndRecoveryCleanup()
    try checkLocalInsights()
    try checkCategoryCorrection()
    print("ZenVoiceStorageChecks: 11 checks passed")
} catch {
    FileHandle.standardError.write(
        Data("FAIL: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
