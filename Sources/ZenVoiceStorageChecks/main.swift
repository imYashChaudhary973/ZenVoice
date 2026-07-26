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

private func checkScopedHistoryDeletion() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let savedID = UUID()
    let savedAudioURL = fixture.vault.recoveryAudioURL(for: savedID)
    try Data("saved audio".utf8).write(to: savedAudioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: savedID,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: "Notes",
            recoveryAudioURL: savedAudioURL
        )
    )
    try fixture.vault.storeTranscript(
        id: savedID,
        rawTranscript: "saved dictation",
        finalTranscript: "Saved dictation."
    )
    try fixture.vault.markInsertion(id: savedID, outcome: .inserted)

    let recoveryID = UUID()
    let recoveryAudioURL = fixture.vault.recoveryAudioURL(for: recoveryID)
    try Data("recovery audio".utf8).write(to: recoveryAudioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: recoveryID,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: "Mail",
            recoveryAudioURL: recoveryAudioURL
        )
    )
    try fixture.vault.markFailed(
        id: recoveryID,
        message: "Interrupted",
        retainAudio: true
    )

    try require(
        try fixture.vault.deleteRecords(ids: [savedID]) == 1,
        "scoped deletion did not remove the saved dictation"
    )
    try require(
        try fixture.vault.record(id: savedID) == nil,
        "scoped deletion retained the saved dictation"
    )
    try require(
        try fixture.vault.record(id: recoveryID) != nil,
        "saved-dictation deletion removed Recovery Inbox data"
    )
    try require(
        FileManager.default.fileExists(atPath: recoveryAudioURL.path),
        "saved-dictation deletion removed recovery audio"
    )

    try require(
        try fixture.vault.deleteRecords(ids: [recoveryID]) == 1,
        "scoped deletion did not remove the Recovery Inbox item"
    )
    try require(
        try fixture.vault.record(id: recoveryID) == nil,
        "scoped deletion retained the Recovery Inbox item"
    )
    try require(
        !FileManager.default.fileExists(atPath: recoveryAudioURL.path),
        "Recovery Inbox deletion retained recovery audio"
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
    try vault.addCorrectionRule(
        source: "bild",
        replacement: "build",
        languageScope: .hinglish
    )
    try require(
        try vault.correctionRules().first?.languageScope == .hinglish,
        "version-two vault did not migrate correction scope"
    )
}

private func checkVersionFourCorrectionMigration() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let recoveryURL = directoryURL
        .appendingPathComponent("Recovery", isDirectory: true)
    let databaseURL = directoryURL.appendingPathComponent("version4.sqlite")
    try FileManager.default.createDirectory(
        at: recoveryURL,
        withIntermediateDirectories: true
    )
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    try executeSQL(
        """
        CREATE TABLE correction_rules (
            id TEXT PRIMARY KEY NOT NULL,
            source_text BLOB NOT NULL,
            replacement_text BLOB NOT NULL,
            usage_count INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        PRAGMA user_version = 4;
        """,
        databaseURL: databaseURL
    )
    let vault = try DictationVault(
        databaseURL: databaseURL,
        recoveryDirectoryURL: recoveryURL,
        keyProvider: StaticKeyProvider()
    )
    try vault.addCorrectionRule(
        source: "bild",
        replacement: "build",
        languageScope: .hinglish
    )
    try require(
        try vault.correctionRules().first?.languageScope == .hinglish,
        "version-four correction scope migration failed"
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

private func checkCorrectionEngine() throws {
    let firstID = UUID()
    let secondID = UUID()
    let scopedID = UUID()
    let fuzzyID = UUID()
    let commonID = UUID()
    let suggestionID = UUID()
    let rules = [
        CorrectionRule(
            id: firstID,
            source: "zen pens",
            replacement: "ZenPense"
        ),
        CorrectionRule(
            id: secondID,
            source: "git hub",
            replacement: "GitHub"
        ),
        CorrectionRule(
            id: scopedID,
            source: "bild",
            replacement: "build",
            languageScope: .hinglish
        ),
        CorrectionRule(
            id: fuzzyID,
            source: "servr",
            replacement: "server",
            languageScope: .hinglish
        ),
        CorrectionRule(
            id: commonID,
            source: "muje",
            replacement: "mujhe",
            languageScope: .hinglish
        ),
        CorrectionRule(
            id: suggestionID,
            source: "Chowdhury",
            replacement: "Chaudhary",
            languageScope: .hinglish
        )
    ]
    let application = TranscriptCorrectionEngine.apply(
        "Use zen pens with git hub, not a zen pencil.",
        rules: rules
    )
    try require(
        application.text
            == "Use ZenPense with GitHub, not a zen pencil.",
        "whole-phrase corrections"
    )
    try require(application.correctionCount == 2, "correction count")
    try require(
        Set(application.usages.map(\.ruleID)) == [firstID, secondID],
        "correction rule usage"
    )

    let hinglish = TranscriptCorrectionEngine.apply(
        "kal bild deploy karo aur serer check karo",
        rules: rules,
        activeScope: .hinglish
    )
    try require(
        hinglish.text == "kal build deploy karo aur server check karo",
        "scoped exact or conservative fuzzy correction"
    )
    try require(
        Set(hinglish.usages.map(\.ruleID)) == [scopedID, fuzzyID],
        "scoped correction usage"
    )
    let nonHinglish = TranscriptCorrectionEngine.apply(
        "bild guild servr",
        rules: rules,
        activeScope: .all
    )
    try require(
        nonHinglish.text == "bild guild servr",
        "Hinglish rule leaked into another language"
    )
    let controls = TranscriptCorrectionEngine.apply(
        "the severe guild server remains unchanged",
        rules: rules,
        activeScope: .hinglish
    )
    try require(
        controls.text == "the severe guild server remains unchanged",
        "fuzzy correction changed an unrelated word"
    )
    let commonExact = TranscriptCorrectionEngine.apply(
        "muje",
        rules: rules,
        activeScope: .hinglish
    )
    try require(
        commonExact.text == "mujhe",
        "approved common-word rules should still apply exactly"
    )
    let commonFuzzyControl = TranscriptCorrectionEngine.apply(
        "mujha",
        rules: rules,
        activeScope: .hinglish
    )
    try require(
        commonFuzzyControl.text == "mujha",
        "common Romanized Hindi words must not be fuzzy-corrected"
    )
    let suggestions = TranscriptCorrectionEngine.suggestions(
        in: "Ask Choudhary before release",
        rules: rules,
        activeScope: .hinglish
    )
    try require(
        suggestions == [
            CorrectionSuggestion(
                ruleID: suggestionID,
                source: "Choudhary",
                replacement: "Chaudhary",
                languageScope: .hinglish
            )
        ],
        "uncertain spelling suggestion was not surfaced"
    )

    var correctionLatencies: [Double] = []
    correctionLatencies.reserveCapacity(500)
    for _ in 0..<500 {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        _ = TranscriptCorrectionEngine.apply(
            "kal bild deploy karo aur serer check karo",
            rules: rules,
            activeScope: .hinglish
        )
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        correctionLatencies.append(Double(elapsed) / 1_000_000)
    }
    correctionLatencies.sort()
    let p50 = correctionLatencies[
        Int(Double(correctionLatencies.count - 1) * 0.50)
    ]
    let p95 = correctionLatencies[
        Int(Double(correctionLatencies.count - 1) * 0.95)
    ]
    try require(
        p95 < 10,
        "personal correction p95 exceeded 10 ms: \(p95) ms"
    )
    print(
        String(
            format:
                "ZenVoiceStorageChecks: personal corrections p50 %.3f ms, p95 %.3f ms",
            p50,
            p95
        )
    )
}

private func checkEncryptedVoiceProfile() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let ruleID = UUID()
    try fixture.vault.addCorrectionRule(
        source: "zen pens",
        replacement: "ZenPense",
        id: ruleID,
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    try fixture.vault.addCorrectionRule(
        source: "bild",
        replacement: "build",
        languageScope: .hinglish,
        createdAt: Date(timeIntervalSince1970: 1_001)
    )

    let application = try fixture.vault.applyCorrections(
        to: "zen pens and zen pens"
    )
    try require(
        application.text == "ZenPense and ZenPense",
        "vault correction application"
    )
    try fixture.vault.recordCorrectionUsage(application.usages)
    try require(
        try fixture.vault.correctionRules().first?.usageCount == 2,
        "correction usage was not recorded"
    )
    try require(
        try fixture.vault.applyCorrections(
            to: "bild",
            activeScope: .all
        ).text == "bild",
        "vault ignored correction language scope"
    )
    try require(
        try fixture.vault.applyCorrections(
            to: "bild",
            activeScope: .hinglish
        ).text == "build",
        "vault did not apply Hinglish correction"
    )
    let allVocabulary = try fixture.vault.preferredVocabulary(
        activeScope: .all
    )
    let hinglishVocabulary = try fixture.vault.preferredVocabulary(
        activeScope: .hinglish
    )
    try require(
        allVocabulary == ["ZenPense"],
        "global vocabulary included a scoped term"
    )
    try require(
        Set(hinglishVocabulary) == ["ZenPense", "build"],
        "Hinglish vocabulary omitted an approved term"
    )

    for (offset, transcript) in [
        "Zen voice makes local voice useful",
        "Zen voice keeps local voice private"
    ].enumerated() {
        let id = UUID()
        let audioURL = fixture.vault.recoveryAudioURL(for: id)
        try Data("audio".utf8).write(to: audioURL)
        try fixture.vault.begin(
            DictationDraft(
                id: id,
                startedAt: Date(
                    timeIntervalSince1970:
                        2_000 + TimeInterval(offset * 60)
                ),
                language: "en",
                modelID: "whisper-base-en",
                targetBundleID: "com.openai.codex",
                targetAppName: "ChatGPT",
                category: .aiPrompts,
                recoveryAudioURL: audioURL
            )
        )
        try fixture.vault.markTranscribing(
            id: id,
            durationSeconds: 30
        )
        try fixture.vault.storeTranscript(
            id: id,
            rawTranscript: transcript.lowercased(),
            finalTranscript: transcript
        )
    }

    let profile = try fixture.vault.voiceProfile()
    try require(
        profile.analyzedDictationCount == 2,
        "voice profile dictation count"
    )
    try require(
        profile.topWords.first?.text == "voice"
            && profile.topWords.first?.count == 4,
        "voice profile top words"
    )
    try require(
        profile.catchPhrases.contains {
            $0.text == "zen voice" && $0.count == 2
        },
        "voice profile recurring phrases"
    )
    try require(
        profile.correctionRules.first?.usageCount == 2,
        "voice profile correction ranking"
    )

    for suffix in ["", "-wal", "-shm"] {
        let fileURL = URL(fileURLWithPath: fixture.databaseURL.path + suffix)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            continue
        }
        let text = String(
            decoding: try Data(contentsOf: fileURL),
            as: UTF8.self
        )
        try require(
            !text.contains("zen pens")
                && !text.contains("ZenPense")
                && !text.contains("bild"),
            "correction rule leaked into plaintext database\(suffix)"
        )
    }

    try fixture.vault.deleteAllCorrectionRules()
    try require(
        try fixture.vault.correctionRules().isEmpty,
        "dedicated correction deletion retained rules"
    )
    try require(
        try fixture.vault.recent().count == 2,
        "dedicated correction deletion removed transcripts"
    )
    try fixture.vault.deleteAll()
}

private func checkLocalLearningPreferences() throws {
    let suite =
        "ZenVoiceStorageChecks.Learning.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        throw CheckError.failed(
            "could not create learning preference fixture"
        )
    }
    defer {
        defaults.removePersistentDomain(forName: suite)
    }
    let preferences = LocalLearningPreferences(defaults: defaults)
    try require(
        preferences.appliesCorrectionRules,
        "correction rules did not default on"
    )
    try require(
        preferences.analyzesHistory,
        "history analysis did not default on"
    )
    preferences.appliesCorrectionRules = false
    preferences.analyzesHistory = false
    try require(
        !preferences.appliesCorrectionRules
            && !preferences.analyzesHistory,
        "learning preferences did not persist"
    )
}

private func checkLivePartialRecovery() throws {
    let fixture = try VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try fixture.vault.begin(
        DictationDraft(
            id: id,
            startedAt: Date(timeIntervalSince1970: 12_000),
            language: "en",
            modelID: "whisper-base-en",
            targetBundleID: "com.openai.codex",
            targetAppName: "ChatGPT",
            category: .aiPrompts,
            recoveryAudioURL: audioURL
        )
    )
    try fixture.vault.storePartialTranscript(
        id: id,
        rawTranscript: "build the local",
        finalTranscript: "Build the local app",
        correctionCount: 1
    )

    guard let partial = try fixture.vault.record(id: id) else {
        throw CheckError.failed("live partial record is missing")
    }
    try require(partial.status == .recording, "live partial changed status")
    try require(partial.isPartial, "live partial flag")
    try require(
        partial.finalTranscript == "Build the local app",
        "live partial final text"
    )
    try require(partial.correctionCount == 1, "live partial corrections")

    try require(
        try fixture.vault.recoverInterrupted(
            retainAudio: true,
            now: Date(timeIntervalSince1970: 12_030)
        ) == 1,
        "live partial interruption was not recovered"
    )
    guard let recovered = try fixture.vault.record(id: id) else {
        throw CheckError.failed("recovered live partial is missing")
    }
    try require(recovered.status == .failed, "live partial recovery status")
    try require(
        recovered.finalTranscript == "Build the local app",
        "live partial was lost during recovery"
    )
}

do {
    try checkEncryptedStorage()
    try checkRecoveryExpiry()
    try checkDiscard()
    try checkDeleteAllRotatesVault()
    try checkScopedHistoryDeletion()
    try checkHistoryPreferencesDefaults()
    try checkVersionTwoMigration()
    try checkVersionFourCorrectionMigration()
    try checkPartialAndCipherBinding()
    try checkRecoveryPathConfinement()
    try checkPrivacySuppressionAndRecoveryCleanup()
    try checkLocalInsights()
    try checkCategoryCorrection()
    try checkCorrectionEngine()
    try checkEncryptedVoiceProfile()
    try checkLocalLearningPreferences()
    try checkLivePartialRecovery()
    print("ZenVoiceStorageChecks: 17 checks passed")
} catch {
    FileHandle.standardError.write(
        Data("FAIL: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
