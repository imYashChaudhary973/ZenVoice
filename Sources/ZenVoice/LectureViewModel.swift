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

import AppKit
import Combine
import Foundation
import ZenVoiceStorage

/// Long-session lecture capture. Own recorder — never the dictation hotkey.
@MainActor
final class LectureViewModel: ObservableObject {
    @Published private(set) var record: LectureStore.Record?
    @Published private(set) var lectures: [LectureStore.Record] = []
    @Published private(set) var lectureAudioBytes: Int64 = 0
    @Published private(set) var openedID: UUID?
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var originalTranscript: String?
    @Published private(set) var summary: String?
    @Published private(set) var isTranscribing = false
    @Published private(set) var isSummarizing = false
    @Published private(set) var errorMessage: String?

    private let store: LectureStore
    private let isDictationRecording: () -> Bool
    private let keyProvider: VaultKeyProviding?
    private let transcribeFile: ((URL) async throws -> (text: String, engineID: String))?
    private let summarizeTranscript: ((String) async throws -> String)?
    private let recorder = AudioRecorder()
    private var accumulatedSeconds: TimeInterval = 0
    private var runningSince: Date?
    private var tick: Timer?
    private var completionStatus: LectureStore.Status = .complete
    private var transcribeTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?

    var isSessionActive: Bool {
        switch record?.status {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }

    var isRecording: Bool {
        record?.status == .recording
    }

    var isPaused: Bool {
        record?.status == .paused
    }

    var canRetry: Bool {
        canRetry(record)
    }

    var canCopyOriginal: Bool {
        let text = originalTranscript?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false
    }

    var canSummarize: Bool {
        originalTranscript?.isEmpty == false
            && summary == nil
            && !isTranscribing
            && !isSummarizing
    }

    var elapsedLabel: String {
        Self.formatElapsed(elapsedSeconds)
    }

    var lectureAudioDisplayString: String {
        ByteCountFormatter.string(
            fromByteCount: lectureAudioBytes,
            countStyle: .binary
        )
    }

    var lectureCountDisplayString: String {
        "\(lectures.count) lecture\(lectures.count == 1 ? "" : "s")"
    }

    init(
        store: LectureStore,
        isDictationRecording: @escaping () -> Bool = { false },
        keyProvider: VaultKeyProviding? = nil,
        transcribeFile: ((URL) async throws -> (text: String, engineID: String))? = nil,
        summarizeTranscript: ((String) async throws -> String)? = nil
    ) {
        self.store = store
        self.isDictationRecording = isDictationRecording
        self.keyProvider = keyProvider
        self.transcribeFile = transcribeFile
        self.summarizeTranscript = summarizeTranscript
        try? store.markIncompleteIfOpen()
        refreshList()
        loadLatest()
    }

    func start() {
        errorMessage = nil
        guard !isSessionActive, !isTranscribing else { return }
        guard !isDictationRecording() else {
            errorMessage = "Stop dictation before starting a lecture."
            return
        }
        let created: LectureStore.Record
        do {
            created = try store.createRecording()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        do {
            try recorder.start(
                recordingURL: store.audioURL(for: created.id),
                capturesLiveSamples: false,
                levelChanged: { _ in }
            )
        } catch {
            try? store.removeRecordingArtifacts(id: created.id)
            errorMessage = error.localizedDescription
            return
        }
        record = created
        originalTranscript = nil
        summary = nil
        openedID = created.id
        accumulatedSeconds = 0
        runningSince = Date()
        refreshElapsed()
        startTick()
        refreshList()
    }

    func pause() {
        guard isRecording else { return }
        recorder.pause()
        accumulatedSeconds = currentElapsed()
        runningSince = nil
        stopTick()
        updateStatus(.paused, elapsed: accumulatedSeconds)
        refreshElapsed()
        refreshList()
    }

    func resume() {
        errorMessage = nil
        guard isPaused else { return }
        do {
            try recorder.resume()
            runningSince = Date()
            updateStatus(.recording, elapsed: accumulatedSeconds)
            startTick()
            refreshElapsed()
            refreshList()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        finish(status: .complete)
        beginTranscription()
    }

    func retry() {
        guard canRetry else { return }
        beginTranscription()
    }

    func retry(id: UUID) {
        open(id)
        retry()
    }

    func copyOriginal() {
        guard let text = originalTranscript,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func copyOriginal(id: UUID) {
        open(id)
        copyOriginal()
    }

    func summarize() {
        guard canSummarize,
              let originalTranscript,
              let summarizeTranscript,
              let keyProvider,
              let id = record?.id
        else { return }
        isSummarizing = true
        errorMessage = nil
        summaryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await summarizeTranscript(originalTranscript)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else {
                    throw LectureStore.StoreError.io(
                        "The provider returned an empty summary."
                    )
                }
                try self.store.setSummary(
                    value,
                    for: id,
                    keyProvider: keyProvider
                )
                self.record = try self.store.load(id: id)
                self.summary = value
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isSummarizing = false
            self.refreshList()
        }
    }

    func open(_ id: UUID) {
        guard let opened = try? store.load(id: id) else { return }
        openedID = id
        if !(isSessionActive && record?.id == id) {
            record = opened
            elapsedSeconds = opened.elapsedSeconds
        }
        if let keyProvider {
            originalTranscript = try? store.originalTranscript(
                for: id,
                keyProvider: keyProvider
            )
            summary = try? store.summary(
                for: id,
                keyProvider: keyProvider
            )
        }
        errorMessage = nil
    }

    func delete(_ id: UUID) {
        if isSessionActive && record?.id == id { return }
        if isTranscribing && record?.id == id { return }
        try? store.removeRecordingArtifacts(id: id)
        if openedID == id {
            openedID = nil
            if record?.id == id {
                record = nil
                originalTranscript = nil
                summary = nil
            }
        }
        refreshList()
    }

    func canRetry(_ item: LectureStore.Record?) -> Bool {
        guard let item else { return false }
        return !isSessionActive
            && !isTranscribing
            && item.originalTranscriptCiphertext == nil
            && item.status != .recording
            && item.status != .paused
    }

    func canDelete(_ item: LectureStore.Record) -> Bool {
        !(isSessionActive && record?.id == item.id)
            && !(isTranscribing && record?.id == item.id)
            && !(isSummarizing && record?.id == item.id)
    }
    func refreshList() {
        lectures = (try? store.all()) ?? []
        lectureAudioBytes = (try? store.inventory().audioBytes) ?? 0
    }

    /// Quit / crash path: keep the WAV, mark incomplete. Do not paste.
    func markIncompleteForTermination() {
        transcribeTask?.cancel()
        transcribeTask = nil
        summaryTask?.cancel()
        summaryTask = nil
        isSummarizing = false
        guard isSessionActive || isTranscribing else { return }
        finish(status: .incomplete)
        isTranscribing = false
        refreshList()
    }

    private func finish(status: LectureStore.Status) {
        if status == .complete || status == .completeAtCap {
            completionStatus = status
        }
        let measuredElapsed = currentElapsed()
        let recordedAudio = recorder.stop()
#if DEBUG
        let elapsed = recorder.usesDeterministicFixture
            ? recordedAudio?.durationSeconds ?? measuredElapsed
            : measuredElapsed
#else
        let elapsed = measuredElapsed
#endif
        stopTick()
        runningSince = nil
        accumulatedSeconds = elapsed
        updateStatus(status, elapsed: elapsed)
        refreshElapsed()
        refreshList()
    }

    private func beginTranscription() {
        guard let record else { return }
        guard originalTranscript == nil else { return }
        guard let transcribeFile, let keyProvider else {
            errorMessage = "No speech engine is available."
            updateStatus(.failed, elapsed: record.elapsedSeconds)
            refreshList()
            return
        }
        let audioURL = store.audioURL(for: record.id)
        let id = record.id
        isTranscribing = true
        errorMessage = nil
        updateStatus(.transcribing, elapsed: record.elapsedSeconds)
        refreshList()
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await transcribeFile(audioURL)
                try Task.checkCancellation()
                let trimmed = result.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !trimmed.isEmpty else {
                    throw LectureStore.StoreError.io(
                        "The lecture produced no text."
                    )
                }
                try self.store.setOriginalTranscript(
                    trimmed,
                    for: id,
                    engineID: result.engineID,
                    keyProvider: keyProvider
                )
                self.record = try self.store.load(id: id)
                self.originalTranscript = trimmed
                self.updateStatus(
                    self.completionStatus,
                    elapsed: self.record?.elapsedSeconds ?? self.elapsedSeconds
                )
            } catch is CancellationError {
                return
            } catch {
                if FileManager.default.fileExists(atPath: audioURL.path) {
                    self.updateStatus(
                        .failed,
                        elapsed: self.record?.elapsedSeconds ?? self.elapsedSeconds
                    )
                }
                self.errorMessage = error.localizedDescription
            }
            self.isTranscribing = false
            self.refreshList()
        }
    }

    private func loadLatest() {
        guard let latest = lectures.first ?? (try? store.all().first) else {
            return
        }
        open(latest.id)
    }

    private func updateStatus(
        _ status: LectureStore.Status,
        elapsed: TimeInterval
    ) {
        guard var current = record else { return }
        current.status = status
        current.elapsedSeconds = elapsed
        record = current
        try? store.save(current)
    }

    private func startTick() {
        stopTick()
        let timer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func stopTick() {
        tick?.invalidate()
        tick = nil
    }

    private func handleTick() {
        refreshElapsed()
        if LectureStore.shouldStopAtCap(elapsedSeconds) {
            finish(status: .completeAtCap)
            beginTranscription()
        }
    }

    private func refreshElapsed() {
        elapsedSeconds = currentElapsed()
    }

    private func currentElapsed() -> TimeInterval {
        LectureStore.displayedElapsed(
            accumulated: accumulatedSeconds,
            runningSince: runningSince,
            now: Date()
        )
    }

    static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
