import Foundation
import ZenVoiceStorage

private final class StaticKeyProvider: VaultKeyProviding {
    private var keyData = Data(repeating: 0x5A, count: 32)

    func loadOrCreateKeyData() throws -> Data {
        keyData
    }

    func deleteKey() throws {
        keyData = Data(repeating: 0, count: 32)
    }
}

private struct VaultFixture {
    let directoryURL: URL
    let databaseURL: URL
    let vault: DictationVault

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        databaseURL = directoryURL.appendingPathComponent("test.sqlite")
        vault = try DictationVault(
            databaseURL: databaseURL,
            recoveryDirectoryURL: directoryURL
                .appendingPathComponent("Recovery", isDirectory: true),
            keyProvider: StaticKeyProvider()
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

do {
    try checkEncryptedStorage()
    try checkRecoveryExpiry()
    try checkDiscard()
    print("ZenVoiceStorageChecks: 3 checks passed")
} catch {
    FileHandle.standardError.write(
        Data("FAIL: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
