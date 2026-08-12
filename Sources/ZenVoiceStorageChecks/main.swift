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

    init() async throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        databaseURL = directoryURL.appendingPathComponent("test.sqlite")
        keyProvider = StaticKeyProvider()
        vault = try await DictationVault(
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
    _ condition: @autoclosure () async throws -> Bool,
    _ message: String
) async throws {
    guard try await condition() else {
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

private func checkEncryptedStorage() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = await fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try await fixture.vault.begin(
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
    try await fixture.vault.markTranscribing(id: id, durationSeconds: 30)
    try await fixture.vault.storeTranscript(
        id: id,
        rawTranscript: "hello local world",
        finalTranscript: "Hello local world.",
        completedAt: Date(timeIntervalSince1970: 1_030),
        correctionCount: 1
    )
    try await fixture.vault.markInsertion(id: id, outcome: .inserted)

    guard let record = try await fixture.vault.record(id: id) else {
        throw CheckError.failed("stored record is missing")
    }
    try await require(record.finalTranscript == "Hello local world.", "final text")
    try await require(record.rawTranscript == "hello local world", "raw text")
    try await require(record.wordCount == 3, "word count")
    try await require(record.wordsPerMinute == 6, "words per minute")
    try await require(record.status == .inserted, "insertion status")
    try await require(record.correctionCount == 1, "correction count")

    for suffix in ["", "-wal", "-shm"] {
        let fileURL = URL(fileURLWithPath: fixture.databaseURL.path + suffix)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            continue
        }
        let databaseData = try Data(contentsOf: fileURL)
        let databaseText = String(decoding: databaseData, as: UTF8.self)
        try await require(
            !databaseText.contains("Hello local world"),
            "final transcript leaked into plaintext database\(suffix)"
        )
        try await require(
            !databaseText.contains("hello local world"),
            "raw transcript leaked into plaintext database\(suffix)"
        )
    }
}

private func checkRecoveryExpiry() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let startedAt = Date(timeIntervalSince1970: 9_000)
    let audioURL = await fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try await fixture.vault.begin(
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
    try await require(
        try await fixture.vault.recoverInterrupted(
            retainAudio: true,
            now: recoveryTime
        ) == 1,
        "interrupted record was not recovered"
    )
    guard let failed = try await fixture.vault.record(id: id) else {
        throw CheckError.failed("failed record is missing")
    }
    try await require(failed.status == .failed, "recovered status")
    try await require(failed.recoveryAudioURL == audioURL, "recovery audio path")
    try await require(
        failed.recoveryAudioExpiresAt
            == startedAt.addingTimeInterval(DictationVault.recoveryLifetime),
        "interrupted recovery expiry was extended from relaunch time"
    )
    try await require(
        FileManager.default.fileExists(atPath: audioURL.path),
        "recovery audio was deleted too early"
    )

    try await require(
        try await fixture.vault.purgeExpiredRecoveryAudio(
            now: recoveryTime.addingTimeInterval(
                DictationVault.recoveryLifetime + 1
            )
        ) == 1,
        "expired audio was not purged"
    )
    try await require(
        !FileManager.default.fileExists(atPath: audioURL.path),
        "expired audio remains on disk"
    )
    try await require(
        try await fixture.vault.record(id: id)?.recoveryAudioURL == nil,
        "expired audio path remains in database"
    )

    // A dictation that fails normally must expire from the start of capture
    // too. Anchoring to the failure moment quietly granted the recording and
    // decode time on top of the 24 hours the privacy contract states.
    let failedID = UUID()
    let failedStartedAt = Date(timeIntervalSince1970: 50_000)
    let failedAudioURL = await fixture.vault.recoveryAudioURL(for: failedID)
    try Data("audio".utf8).write(to: failedAudioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: failedID,
            startedAt: failedStartedAt,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: failedAudioURL
        )
    )
    try await fixture.vault.markFailed(
        id: failedID,
        message: "test",
        retainAudio: true,
        now: failedStartedAt.addingTimeInterval(600)
    )
    try await require(
        try await fixture.vault.record(id: failedID)?.recoveryAudioExpiresAt
            == failedStartedAt.addingTimeInterval(
                DictationVault.recoveryLifetime
            ),
        "failed recovery expiry was anchored to failure instead of capture"
    )
    try await require(
        try await fixture.vault.purgeExpiredRecoveryAudio(
            now: failedStartedAt.addingTimeInterval(
                DictationVault.recoveryLifetime + 1
            )
        ) == 1,
        "failed recovery audio outlived its capture-anchored window"
    )

    // An explicit expiry must still win, and retainAudio: false must clear it.
    let explicitID = UUID()
    let explicitAudioURL = await fixture.vault.recoveryAudioURL(for: explicitID)
    try Data("audio".utf8).write(to: explicitAudioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: explicitID,
            startedAt: failedStartedAt,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: explicitAudioURL
        )
    )
    let explicitExpiry = Date(timeIntervalSince1970: 99_999)
    try await fixture.vault.markFailed(
        id: explicitID,
        message: "test",
        retainAudio: true,
        recoveryExpiresAt: explicitExpiry
    )
    try await require(
        try await fixture.vault.record(id: explicitID)?.recoveryAudioExpiresAt
            == explicitExpiry,
        "explicit recovery expiry was ignored"
    )
    try await fixture.vault.markFailed(
        id: explicitID,
        message: "test",
        retainAudio: false
    )
    try await require(
        try await fixture.vault.record(id: explicitID)?.recoveryAudioExpiresAt == nil,
        "declining audio retention left an expiry behind"
    )

    let staleID = UUID()
    let staleAudioURL = await fixture.vault.recoveryAudioURL(for: staleID)
    try Data("stale audio".utf8).write(to: staleAudioURL)
    try await fixture.vault.begin(
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
    try await require(
        try await fixture.vault.recoverInterrupted(
            retainAudio: true,
            now: recoveryTime
        ) == 1,
        "stale interrupted record was not recovered"
    )
    try await require(
        try await fixture.vault.purgeExpiredRecoveryAudio(now: recoveryTime) == 1,
        "already-expired interrupted audio was retained"
    )
}

private func checkPrivacySuppressionAndRecoveryCleanup() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let privateID = UUID()
    let privateAudioURL = await fixture.vault.recoveryAudioURL(for: privateID)
    try Data("private audio".utf8).write(to: privateAudioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: privateID,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: privateAudioURL
        )
    )
    try await fixture.vault.suppressPersistence(id: privateID)
    try await require(
        try await fixture.vault.recoverInterrupted(retainAudio: true) == 1,
        "suppressed dictation was not handled during recovery"
    )
    try await require(
        try await fixture.vault.record(id: privateID) == nil,
        "suppressed dictation survived restart recovery"
    )
    try await require(
        !FileManager.default.fileExists(atPath: privateAudioURL.path),
        "suppressed recovery audio survived restart recovery"
    )

    let firstID = UUID()
    let secondID = UUID()
    for id in [firstID, secondID] {
        let audioURL = await fixture.vault.recoveryAudioURL(for: id)
        try Data("failed audio".utf8).write(to: audioURL)
        try await fixture.vault.begin(
            DictationDraft(
                id: id,
                language: "en",
                modelID: "whisper-base.en",
                targetBundleID: nil,
                targetAppName: nil,
                recoveryAudioURL: audioURL
            )
        )
        try await fixture.vault.markFailed(
            id: id,
            message: "test",
            retainAudio: true
        )
    }
    try await require(
        try await fixture.vault.deleteAllRecoveryAudio() == 2,
        "disabling recovery did not remove every retained recording"
    )
    for id in [firstID, secondID] {
        try await require(
            try await fixture.vault.record(id: id)?.recoveryAudioURL == nil,
            "disabled recovery left an audio path"
        )
    }
}

private func checkDiscard() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = await fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: id,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: audioURL
        )
    )
    try await fixture.vault.discard(id: id)

    try await require(try await fixture.vault.record(id: id) == nil, "discarded record")
    try await require(
        !FileManager.default.fileExists(atPath: audioURL.path),
        "discarded audio remains on disk"
    )
}

private func checkDeleteAllRotatesVault() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let firstID = UUID()
    let firstAudioURL = await fixture.vault.recoveryAudioURL(for: firstID)
    try Data("audio".utf8).write(to: firstAudioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: firstID,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: firstAudioURL
        )
    )
    try await fixture.vault.markTranscribing(
        id: firstID,
        durationSeconds: 10
    )
    try await fixture.vault.storeTranscript(
        id: firstID,
        rawTranscript: "private history",
        finalTranscript: "Private history."
    )

    let originalKey = try fixture.keyProvider.loadOrCreateKeyData()
    try await fixture.vault.deleteAll()
    let replacementKey = try fixture.keyProvider.loadOrCreateKeyData()

    try await require(
        try await fixture.vault.recent().isEmpty,
        "delete all left history records"
    )
    try await require(
        !FileManager.default.fileExists(atPath: firstAudioURL.path),
        "delete all left recovery audio"
    )
    try await require(
        originalKey != replacementKey,
        "delete all did not rotate the encryption key"
    )
}

private func checkScopedHistoryDeletion() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let savedID = UUID()
    let savedAudioURL = await fixture.vault.recoveryAudioURL(for: savedID)
    try Data("saved audio".utf8).write(to: savedAudioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: savedID,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: "Notes",
            recoveryAudioURL: savedAudioURL
        )
    )
    try await fixture.vault.storeTranscript(
        id: savedID,
        rawTranscript: "saved dictation",
        finalTranscript: "Saved dictation."
    )
    try await fixture.vault.markInsertion(id: savedID, outcome: .inserted)

    let recoveryID = UUID()
    let recoveryAudioURL = await fixture.vault.recoveryAudioURL(for: recoveryID)
    try Data("recovery audio".utf8).write(to: recoveryAudioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: recoveryID,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: "Mail",
            recoveryAudioURL: recoveryAudioURL
        )
    )
    try await fixture.vault.markFailed(
        id: recoveryID,
        message: "Interrupted",
        retainAudio: true
    )

    try await require(
        try await fixture.vault.deleteRecords(ids: [savedID]) == 1,
        "scoped deletion did not remove the saved dictation"
    )
    try await require(
        try await fixture.vault.record(id: savedID) == nil,
        "scoped deletion retained the saved dictation"
    )
    try await require(
        try await fixture.vault.record(id: recoveryID) != nil,
        "saved-dictation deletion removed Recovery Inbox data"
    )
    try await require(
        FileManager.default.fileExists(atPath: recoveryAudioURL.path),
        "saved-dictation deletion removed recovery audio"
    )

    try await require(
        try await fixture.vault.deleteRecords(ids: [recoveryID]) == 1,
        "scoped deletion did not remove the Recovery Inbox item"
    )
    try await require(
        try await fixture.vault.record(id: recoveryID) == nil,
        "scoped deletion retained the Recovery Inbox item"
    )
    try await require(
        !FileManager.default.fileExists(atPath: recoveryAudioURL.path),
        "Recovery Inbox deletion retained recovery audio"
    )
}

private func checkHistoryPreferencesDefaults() async throws {
    let suiteName = "ZenVoiceStorageChecks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw CheckError.failed("could not create isolated user defaults")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let preferences = HistoryPreferences(defaults: defaults)
    try await require(preferences.hasMadeHistoryChoice, "history default not active")
    try await require(preferences.isHistoryEnabled, "history disabled by default")
    try await require(preferences.retainsFailedAudio, "failed audio default")

    preferences.isHistoryEnabled = true
    preferences.isPrivateModeEnabled = true
    try await require(preferences.hasMadeHistoryChoice, "history choice not saved")
    try await require(
        preferences.hasEverEnabledHistory,
        "history activation not recorded"
    )
    try await require(preferences.isPrivateModeEnabled, "private mode not saved")

    preferences.isHistoryEnabled = false
    let reloaded = HistoryPreferences(defaults: defaults)
    try await require(!reloaded.isHistoryEnabled, "explicit pause was not preserved")
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

private func checkVersionTwoMigration() async throws {
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
    let vault = try await DictationVault(
        databaseURL: databaseURL,
        recoveryDirectoryURL: recoveryURL,
        keyProvider: StaticKeyProvider()
    )
    let id = UUID()
    let audioURL = await vault.recoveryAudioURL(for: id)
    try Data("private audio".utf8).write(to: audioURL)
    try await vault.begin(
        DictationDraft(
            id: id,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: audioURL
        )
    )
    try await vault.suppressPersistence(id: id)
    try await require(
        try await vault.recoverInterrupted(retainAudio: true) == 1,
        "version-two vault did not migrate privacy suppression"
    )
    try await vault.addCorrectionRule(
        source: "bild",
        replacement: "build",
        languageScope: .hinglish
    )
    try await require(
        try await vault.correctionRules().first?.languageScope == .hinglish,
        "version-two vault did not migrate correction scope"
    )
}

private func checkVersionFourCorrectionMigration() async throws {
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
    let vault = try await DictationVault(
        databaseURL: databaseURL,
        recoveryDirectoryURL: recoveryURL,
        keyProvider: StaticKeyProvider()
    )
    try await vault.addCorrectionRule(
        source: "bild",
        replacement: "build",
        languageScope: .hinglish
    )
    try await require(
        try await vault.correctionRules().first?.languageScope == .hinglish,
        "version-four correction scope migration failed"
    )
}

private func checkPartialAndCipherBinding() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = await fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: id,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: nil,
            targetAppName: nil,
            recoveryAudioURL: audioURL
        )
    )
    try await fixture.vault.markTranscribing(id: id, durationSeconds: 10)
    try await fixture.vault.storeTranscript(
        id: id,
        rawTranscript: "partial raw",
        finalTranscript: "Partial final",
        isPartial: true
    )
    try await require(
        try await fixture.vault.record(id: id)?.isPartial == true,
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
        _ = try await fixture.vault.record(id: id)
        throw CheckError.failed("swapped ciphertext fields were accepted")
    } catch let checkError as CheckError {
        throw checkError
    } catch {
        // Expected: authenticated field context rejects the swap.
    }

    try await fixture.vault.deleteAll()
    try await require(
        try await fixture.vault.recent().isEmpty,
        "corrupt ciphertext blocked delete all"
    )
}

private func checkRecoveryPathConfinement() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let outsideURL = fixture.directoryURL
        .appendingPathComponent("outside.wav")
    try Data("do not delete".utf8).write(to: outsideURL)
    do {
        try await fixture.vault.begin(
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
    try await require(
        FileManager.default.fileExists(atPath: outsideURL.path),
        "external file was modified"
    )
}

private func checkLocalInsights() async throws {
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
    try await require(snapshot.dictationCount == 4, "insight dictation count")
    try await require(snapshot.totalWordCount == 42, "insight total words")
    try await require(
        abs(snapshot.weightedWordsPerMinute - (42 / (220 / 60))) < 0.001,
        "weighted insight words per minute"
    )
    try await require(snapshot.correctionCount == 3, "insight corrections")
    try await require(snapshot.distinctApplicationCount == 2, "distinct apps")
    try await require(snapshot.currentStreakDays == 3, "current streak")
    try await require(snapshot.longestStreakDays == 3, "longest streak")
    try await require(snapshot.recentActivity.count == 7, "seven-day activity")
    try await require(
        snapshot.categories.first?.category == .documents,
        "category ranking"
    )
    try await require(
        ApplicationCategoryClassifier.category(
            bundleIdentifier: "com.openai.chatgpt",
            appName: "ChatGPT"
        ) == .aiPrompts,
        "AI application classification"
    )
    try await require(
        ApplicationCategoryClassifier.category(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        ) == .other,
        "unknown application classification"
    )
}

private func checkCategoryCorrection() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = await fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try await fixture.vault.begin(
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
    try await fixture.vault.markTranscribing(id: id, durationSeconds: 60)
    try await fixture.vault.storeTranscript(
        id: id,
        rawTranscript: "one two three four five",
        finalTranscript: "One two three four five."
    )
    try await fixture.vault.updateCategory(id: id, category: .workMessages)

    try await require(
        try await fixture.vault.record(id: id)?.category == .workMessages,
        "corrected category was not stored"
    )
    let snapshot = try await fixture.vault.insights()
    try await require(snapshot.totalWordCount == 5, "vault insight words")
    try await require(
        snapshot.categories.first?.category == .workMessages,
        "vault insight did not use corrected category"
    )

    // Insights promise *completed* dictations. A force-quit dictation keeps its
    // live-preview partial and is marked failed on relaunch with duration 0, so
    // counting it inflates words, application counts, streak days, and weighted
    // WPM — and the share card exports those same numbers.
    let abandonedID = UUID()
    let abandonedAudioURL = await fixture.vault.recoveryAudioURL(for: abandonedID)
    try Data("audio".utf8).write(to: abandonedAudioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: abandonedID,
            language: "en",
            modelID: "whisper-base-en",
            targetBundleID: "com.tinyspeck.slackmacgap",
            targetAppName: "Slack",
            category: .workMessages,
            recoveryAudioURL: abandonedAudioURL
        )
    )
    try await fixture.vault.storePartialTranscript(
        id: abandonedID,
        rawTranscript: "one two three four five six seven eight",
        finalTranscript: "One two three four five six seven eight."
    )
    try await fixture.vault.recoverInterrupted(retainAudio: true)
    try await require(
        try await fixture.vault.record(id: abandonedID)?.status == .failed,
        "interrupted dictation was not marked failed"
    )
    let afterAbandon = try await fixture.vault.insights()
    try await require(
        afterAbandon.totalWordCount == 5,
        "an interrupted dictation's partial was counted in insights"
    )
    try await require(
        afterAbandon.distinctApplicationCount == 1,
        "an interrupted dictation added an application to insights"
    )
    try await require(
        afterAbandon.dictationCount == 1,
        "an interrupted dictation was counted as a completed dictation"
    )
    try await require(
        afterAbandon.currentStreakDays == snapshot.currentStreakDays,
        "an interrupted dictation changed the streak"
    )
}

private func checkCorrectionEngine() async throws {
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
    try await require(
        application.text
            == "Use ZenPense with GitHub, not a zen pencil.",
        "whole-phrase corrections"
    )
    try await require(application.correctionCount == 2, "correction count")
    try await require(
        Set(application.usages.map(\.ruleID)) == [firstID, secondID],
        "correction rule usage"
    )

    let hinglish = TranscriptCorrectionEngine.apply(
        "kal bild deploy karo aur serer check karo",
        rules: rules,
        activeScope: .hinglish
    )
    try await require(
        hinglish.text == "kal build deploy karo aur server check karo",
        "scoped exact or conservative fuzzy correction"
    )
    try await require(
        Set(hinglish.usages.map(\.ruleID)) == [scopedID, fuzzyID],
        "scoped correction usage"
    )
    let nonHinglish = TranscriptCorrectionEngine.apply(
        "bild guild servr",
        rules: rules,
        activeScope: .all
    )
    try await require(
        nonHinglish.text == "bild guild servr",
        "Hinglish rule leaked into another language"
    )
    let controls = TranscriptCorrectionEngine.apply(
        "the severe guild server remains unchanged",
        rules: rules,
        activeScope: .hinglish
    )
    try await require(
        controls.text == "the severe guild server remains unchanged",
        "fuzzy correction changed an unrelated word"
    )
    let commonExact = TranscriptCorrectionEngine.apply(
        "muje",
        rules: rules,
        activeScope: .hinglish
    )
    try await require(
        commonExact.text == "mujhe",
        "approved common-word rules should still apply exactly"
    )
    let commonFuzzyControl = TranscriptCorrectionEngine.apply(
        "mujha",
        rules: rules,
        activeScope: .hinglish
    )
    try await require(
        commonFuzzyControl.text == "mujha",
        "common Romanized Hindi words must not be fuzzy-corrected"
    )
    let suggestions = TranscriptCorrectionEngine.suggestions(
        in: "Ask Choudhary before release",
        rules: rules,
        activeScope: .hinglish
    )
    try await require(
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
    try await require(
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

private func checkEncryptedVoiceProfile() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let ruleID = UUID()
    try await fixture.vault.addCorrectionRule(
        source: "zen pens",
        replacement: "ZenPense",
        id: ruleID,
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    try await fixture.vault.addCorrectionRule(
        source: "bild",
        replacement: "build",
        languageScope: .hinglish,
        createdAt: Date(timeIntervalSince1970: 1_001)
    )

    let application = try await fixture.vault.applyCorrections(
        to: "zen pens and zen pens"
    )
    try await require(
        application.text == "ZenPense and ZenPense",
        "vault correction application"
    )
    try await fixture.vault.recordCorrectionUsage(application.usages)
    try await require(
        try await fixture.vault.correctionRules().first?.usageCount == 2,
        "correction usage was not recorded"
    )
    try await require(
        try await fixture.vault.applyCorrections(
            to: "bild",
            activeScope: .all
        ).text == "bild",
        "vault ignored correction language scope"
    )
    try await require(
        try await fixture.vault.applyCorrections(
            to: "bild",
            activeScope: .hinglish
        ).text == "build",
        "vault did not apply Hinglish correction"
    )
    let allVocabulary = try await fixture.vault.preferredVocabulary(
        activeScope: .all
    )
    let hinglishVocabulary = try await fixture.vault.preferredVocabulary(
        activeScope: .hinglish
    )
    try await require(
        allVocabulary == ["ZenPense"],
        "global vocabulary included a scoped term"
    )
    try await require(
        Set(hinglishVocabulary) == ["ZenPense", "build"],
        "Hinglish vocabulary omitted an approved term"
    )

    for (offset, transcript) in [
        "Zen voice makes local voice useful",
        "Zen voice keeps local voice private"
    ].enumerated() {
        let id = UUID()
        let audioURL = await fixture.vault.recoveryAudioURL(for: id)
        try Data("audio".utf8).write(to: audioURL)
        try await fixture.vault.begin(
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
        try await fixture.vault.markTranscribing(
            id: id,
            durationSeconds: 30
        )
        try await fixture.vault.storeTranscript(
            id: id,
            rawTranscript: transcript.lowercased(),
            finalTranscript: transcript
        )
    }

    let profile = try await fixture.vault.voiceProfile()
    try await require(
        profile.analyzedDictationCount == 2,
        "voice profile dictation count"
    )
    try await require(
        profile.topWords.first?.text == "voice"
            && profile.topWords.first?.count == 4,
        "voice profile top words"
    )
    try await require(
        profile.catchPhrases.contains {
            $0.text == "zen voice" && $0.count == 2
        },
        "voice profile recurring phrases"
    )
    try await require(
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
        try await require(
            !text.contains("zen pens")
                && !text.contains("ZenPense")
                && !text.contains("bild"),
            "correction rule leaked into plaintext database\(suffix)"
        )
    }

    try await fixture.vault.deleteAllCorrectionRules()
    try await require(
        try await fixture.vault.correctionRules().isEmpty,
        "dedicated correction deletion retained rules"
    )
    try await require(
        try await fixture.vault.recent().count == 2,
        "dedicated correction deletion removed transcripts"
    )
    try await fixture.vault.deleteAll()
}

private func checkLocalLearningPreferences() async throws {
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
    try await require(
        preferences.appliesCorrectionRules,
        "correction rules did not default on"
    )
    try await require(
        preferences.analyzesHistory,
        "history analysis did not default on"
    )
    preferences.appliesCorrectionRules = false
    preferences.analyzesHistory = false
    try await require(
        !preferences.appliesCorrectionRules
            && !preferences.analyzesHistory,
        "learning preferences did not persist"
    )
}

private func checkLivePartialRecovery() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let id = UUID()
    let audioURL = await fixture.vault.recoveryAudioURL(for: id)
    try Data("audio".utf8).write(to: audioURL)
    try await fixture.vault.begin(
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
    try await fixture.vault.storePartialTranscript(
        id: id,
        rawTranscript: "build the local",
        finalTranscript: "Build the local app",
        correctionCount: 1
    )

    guard let partial = try await fixture.vault.record(id: id) else {
        throw CheckError.failed("live partial record is missing")
    }
    try await require(partial.status == .recording, "live partial changed status")
    try await require(partial.isPartial, "live partial flag")
    try await require(
        partial.finalTranscript == "Build the local app",
        "live partial final text"
    )
    try await require(partial.correctionCount == 1, "live partial corrections")

    try await require(
        try await fixture.vault.recoverInterrupted(
            retainAudio: true,
            now: Date(timeIntervalSince1970: 12_030)
        ) == 1,
        "live partial interruption was not recovered"
    )
    guard let recovered = try await fixture.vault.record(id: id) else {
        throw CheckError.failed("recovered live partial is missing")
    }
    try await require(recovered.status == .failed, "live partial recovery status")
    try await require(
        recovered.finalTranscript == "Build the local app",
        "live partial was lost during recovery"
    )
}

/// Archives a dictation and returns its archive ID.
private func archiveFixtureRecording(
    fixture: VaultFixture,
    startedAt: Date,
    audioBytes: Int,
    appName: String = "TextEdit"
) async throws -> UUID {
    let id = UUID()
    let archiveID = UUID()
    let audioURL = await fixture.vault.recoveryAudioURL(for: id)
    try Data(repeating: 0x41, count: audioBytes).write(to: audioURL)
    try await fixture.vault.begin(
        DictationDraft(
            id: id,
            startedAt: startedAt,
            language: "en",
            modelID: "whisper-base.en",
            targetBundleID: "com.apple.TextEdit",
            targetAppName: appName,
            recoveryAudioURL: audioURL
        )
    )
    try await fixture.vault.storeTranscript(
        id: id,
        rawTranscript: "raw text",
        finalTranscript: "final text",
        correctionCount: 0,
        isPartial: false
    )
    try await fixture.vault.archiveRecording(id: id, archiveID: archiveID)
    return archiveID
}

private func checkAudioArchiveLifecycle() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let archiveID = try await archiveFixtureRecording(
        fixture: fixture,
        startedAt: Date(timeIntervalSince1970: 100_000),
        audioBytes: 2_048
    )

    try await require(
        try await fixture.vault.audioArchiveCount() == 1,
        "archive row was not written"
    )
    try await require(
        try await fixture.vault.audioArchiveTotalSize() == 2_048,
        "archive size was not recorded"
    )

    guard let record = try await fixture.vault.audioArchive(id: archiveID) else {
        throw CheckError.failed("archived record could not be read back")
    }
    try await require(
        record.targetAppName == "TextEdit",
        "archive metadata was not carried over from the dictation"
    )
    try await require(
        FileManager.default.fileExists(atPath: record.audioURL.path),
        "archived audio file is missing"
    )

    // The archive copies the audio; the recovery file stays put until the
    // caller deletes it.
    try await fixture.vault.deleteAudioArchive(id: archiveID)
    try await require(
        try await fixture.vault.audioArchiveCount() == 0,
        "archive row survived deletion"
    )
    try await require(
        !FileManager.default.fileExists(atPath: record.audioURL.path),
        "archived audio file survived deletion"
    )
}

private func checkAudioArchiveBudgets() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    let now = Date(timeIntervalSince1970: 1_000_000)
    let old = now.addingTimeInterval(-60 * 24 * 60 * 60)

    _ = try await archiveFixtureRecording(
        fixture: fixture,
        startedAt: old,
        audioBytes: 1_024
    )
    let recentID = try await archiveFixtureRecording(
        fixture: fixture,
        startedAt: now,
        audioBytes: 1_024
    )

    let purged = try await fixture.vault.purgeAudioArchive(
        olderThan: now.addingTimeInterval(-30 * 24 * 60 * 60)
    )
    try await require(purged == 1, "age purge removed the wrong number of archives")
    try await require(
        try await fixture.vault.audioArchive(id: recentID) != nil,
        "age purge deleted a recording inside the window"
    )

    // Two 1 KiB recordings against a 1.5 KiB budget: the oldest goes.
    _ = try await archiveFixtureRecording(
        fixture: fixture,
        startedAt: now.addingTimeInterval(60),
        audioBytes: 1_024
    )
    let evicted = try await fixture.vault.enforceAudioArchiveSizeBudget(1_536)
    try await require(evicted == 1, "size budget evicted the wrong count")
    try await require(
        try await fixture.vault.audioArchiveTotalSize() <= 1_536,
        "archive stayed over its size budget"
    )

    let deletedAll = try await fixture.vault.deleteAllAudioArchives()
    try await require(deletedAll == 1, "delete-all returned the wrong count")
    try await require(
        try await fixture.vault.audioArchiveCount() == 0,
        "archives survived delete-all"
    )
}

/// Extracts `manifest.json` from an export ZIP using the system `unzip`, so the
/// assertions run against what a user would actually find in the file.
private func unzippedManifest(from archiveURL: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = [
        "-p",
        archiveURL.path,
        "ZenVoiceAudioHistory/manifest.json"
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0, !data.isEmpty else {
        throw CheckError.failed(
            "manifest.json could not be read from the export"
        )
    }
    return String(decoding: data, as: UTF8.self)
}

private func checkAudioArchiveExport() async throws {
    let fixture = try await VaultFixture()
    defer { fixture.cleanup() }

    _ = try await archiveFixtureRecording(
        fixture: fixture,
        startedAt: Date(timeIntervalSince1970: 500_000),
        audioBytes: 512
    )
    let records = try await fixture.vault.audioArchiveRecent()
    try await require(records.count == 1, "expected one archived record")

    let destination = fixture.directoryURL
        .appendingPathComponent("export.zip")
    try AudioArchiveExporter.export(
        records: records,
        to: destination,
        transcriptProvider: { _ in "secret transcript" }
    )
    try await require(
        FileManager.default.fileExists(atPath: destination.path),
        "export archive was not written"
    )

    // Transcripts are opt-in. Read the manifest back out of the ZIP rather
    // than scanning the compressed bytes, which would pass even on a leak.
    let defaultManifest = try unzippedManifest(from: destination)
    try await require(
        defaultManifest.contains("\"includesTranscripts\" : false"),
        "default export did not record that transcripts were excluded"
    )
    try await require(
        !defaultManifest.contains("secret transcript"),
        "transcript text leaked into a default export"
    )
    try await require(
        defaultManifest.contains("\"language\" : \"en\""),
        "export manifest is missing capture metadata"
    )

    let withTranscripts = fixture.directoryURL
        .appendingPathComponent("export-transcripts.zip")
    try AudioArchiveExporter.export(
        records: records,
        options: AudioArchiveExportOptions(includeTranscripts: true),
        to: withTranscripts,
        transcriptProvider: { _ in "secret transcript" }
    )
    let optedInManifest = try unzippedManifest(from: withTranscripts)
    try await require(
        optedInManifest.contains("secret transcript"),
        "opt-in export did not include the transcript"
    )

    // An empty selection is refused rather than producing an empty archive.
    do {
        try AudioArchiveExporter.export(
            records: [],
            to: fixture.directoryURL.appendingPathComponent("empty.zip")
        )
        throw CheckError.failed("empty export was accepted")
    } catch let checkError as CheckError {
        throw checkError
    } catch {
        // Expected.
    }
}

private func checkAudioHistoryPreferenceDefaults() async throws {
    let suiteName = "ZenVoiceChecks.audioHistory.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw CheckError.failed("could not create a defaults suite")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let preferences = AudioHistoryPreferences(defaults: defaults)
    try await require(!preferences.isEnabled, "audio history was not off by default")
    try await require(
        !preferences.hasMadeChoice,
        "audio history claimed a choice had been made"
    )
    try await require(
        preferences.maxSizeBytes
            == AudioHistoryPreferences.defaultMaxSizeBytes,
        "default size cap is wrong"
    )
    try await require(
        preferences.maxAgeDays == AudioHistoryPreferences.defaultMaxAgeDays,
        "default age cap is wrong"
    )

    // The size cap is clamped so the archive cannot be set to a useless size.
    preferences.maxSizeBytes = 1
    try await require(
        preferences.maxSizeBytes
            == AudioHistoryPreferences.minimumMaxSizeBytes,
        "size cap was not clamped to the minimum"
    )
    preferences.maxAgeDays = 0
    try await require(preferences.maxAgeDays == 1, "age cap was not clamped")

    preferences.isEnabled = true
    try await require(
        preferences.hasMadeChoice,
        "enabling audio history did not record an explicit choice"
    )
}

private func checkTodayUsageInsight() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_721_865_600)
    let today = calendar.startOfDay(for: now)
    let yesterday = today.addingTimeInterval(-24 * 60 * 60)

    let events = [
        DictationInsightEvent(
            startedAt: today,
            durationSeconds: 30,
            wordCount: 40,
            correctionCount: 0,
            targetBundleID: "com.apple.Notes",
            targetAppName: "Notes",
            category: .notes
        ),
        DictationInsightEvent(
            startedAt: today.addingTimeInterval(600),
            durationSeconds: 30,
            wordCount: 10,
            correctionCount: 0,
            targetBundleID: "com.apple.TextEdit",
            targetAppName: "TextEdit",
            category: .documents
        ),
        DictationInsightEvent(
            startedAt: yesterday,
            durationSeconds: 120,
            wordCount: 500,
            correctionCount: 0,
            targetBundleID: "com.apple.Notes",
            targetAppName: "Notes",
            category: .notes
        )
    ]

    let snapshot = LocalInsightsSnapshot.calculate(
        events: events,
        now: now,
        calendar: calendar
    )
    try await require(
        snapshot.today.dictationCount == 2,
        "today counted dictations from other days"
    )
    try await require(snapshot.today.wordCount == 50, "today word count is wrong")
    try await require(
        snapshot.today.durationSeconds == 60,
        "today duration is wrong"
    )
    try await require(
        snapshot.today.topApplicationName == "Notes",
        "today top app is wrong"
    )
    try await require(
        snapshot.today.pillSummary == "50 words today",
        "today pill summary is wrong"
    )

    let empty = LocalInsightsSnapshot.calculate(
        events: [],
        now: now,
        calendar: calendar
    )
    try await require(
        !empty.today.hasActivity,
        "an empty day reported activity"
    )
}

do {
    try await checkEncryptedStorage()
    try await checkRecoveryExpiry()
    try await checkDiscard()
    try await checkDeleteAllRotatesVault()
    try await checkScopedHistoryDeletion()
    try await checkHistoryPreferencesDefaults()
    try await checkVersionTwoMigration()
    try await checkVersionFourCorrectionMigration()
    try await checkPartialAndCipherBinding()
    try await checkRecoveryPathConfinement()
    try await checkPrivacySuppressionAndRecoveryCleanup()
    try await checkLocalInsights()
    try await checkCategoryCorrection()
    try await checkCorrectionEngine()
    try await checkEncryptedVoiceProfile()
    try await checkLocalLearningPreferences()
    try await checkLivePartialRecovery()
    try await checkAudioArchiveLifecycle()
    try await checkAudioArchiveBudgets()
    try await checkAudioArchiveExport()
    try await checkAudioHistoryPreferenceDefaults()
    try await checkTodayUsageInsight()
    print("ZenVoiceStorageChecks: 22 checks passed")
} catch {
    FileHandle.standardError.write(
        Data("FAIL: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
