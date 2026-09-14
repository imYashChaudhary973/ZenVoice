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
import EventKit
import Foundation
import ZenVoiceCore
import ZenVoiceStorage

/// Long-session meeting capture. Own recorders — never the dictation hotkey.
@MainActor
final class MeetingViewModel: ObservableObject {
    @Published private(set) var record: MeetingStore.Record?
    @Published private(set) var meetings: [MeetingStore.Record] = []
    @Published private(set) var meetingAudioBytes: Int64 = 0
    @Published private(set) var openedID: UUID?
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var originalTranscript: String?
    @Published private(set) var summary: String?
    @Published private(set) var isTranscribing = false
    @Published private(set) var isSummarizing = false
    @Published private(set) var themCaptureFailed = false
    @Published private(set) var errorMessage: String?
    @Published var youName = ""
    @Published var themName = ""
    @Published var searchQuery = ""
    @Published var joinURL = ""
    @Published var gmailToken = ""
    @Published var slackToken = ""
    @Published private(set) var searchHits: [(id: UUID, snippet: String)] = []
    @Published private(set) var contextHits: [ConnectorHit] = []
    @Published private(set) var pendingDetection: MeetingWatcher.Detection?
    @Published var autoRecordEnabled: Bool {
        didSet {
            RuntimeIdentity.userDefaults().set(
                autoRecordEnabled,
                forKey: Self.autoRecordKey
            )
        }
    }

    private static let autoRecordKey = "ZenVoice.meetingAutoRecord"
    private let store: MeetingStore
    private let isDictationRecording: () -> Bool
    private let keyProvider: VaultKeyProviding?
    private let transcribeFile:
        ((URL) async throws -> TranscriptionResult)?
    private let summarizeTranscript: ((String) async throws -> String)?
    private let recorder = AudioRecorder()
    private let systemAudio = MeetingSystemAudio()
    private var index: MeetingIndex?
    private var botJob: MeetingBotClient.Job?
    private var accumulatedSeconds: TimeInterval = 0
    private var runningSince: Date?
    private var tick: Timer?
    private var completionStatus: MeetingStore.Status = .complete
    private var transcribeTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var systemAudioTask: Task<Void, Never>?

    var isSessionActive: Bool {
        switch record?.status {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }

    var isRecording: Bool { record?.status == .recording }
    var isPaused: Bool { record?.status == .paused }

    var canCopyOriginal: Bool {
        let text = originalTranscript?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
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

    var meetingCountDisplayString: String {
        "\(meetings.count) meeting\(meetings.count == 1 ? "" : "s")"
    }

    var meetingAudioDisplayString: String {
        ByteCountFormatter.string(
            fromByteCount: meetingAudioBytes,
            countStyle: .binary
        )
    }

    init(
        store: MeetingStore,
        isDictationRecording: @escaping () -> Bool = { false },
        keyProvider: VaultKeyProviding? = nil,
        transcribeFile: ((URL) async throws -> TranscriptionResult)? = nil,
        summarizeTranscript: ((String) async throws -> String)? = nil
    ) {
        self.store = store
        self.isDictationRecording = isDictationRecording
        self.keyProvider = keyProvider
        self.transcribeFile = transcribeFile
        self.summarizeTranscript = summarizeTranscript
        autoRecordEnabled = RuntimeIdentity.userDefaults().bool(
            forKey: Self.autoRecordKey
        )
        try? store.markIncompleteIfOpen()
        refreshList()
        loadLatest()
        loadConnectorTokens()
        Task { [weak self] in
            self?.index = try? await MeetingIndex(
                directoryURL: store.directoryURL
            )
        }
    }

    var displayedTranscript: String? {
        guard let originalTranscript else { return nil }
        return SpeakerLabeling.applying(
            SpeakerNameMap(
                you: youName.isEmpty ? nil : youName,
                them: themName.isEmpty ? nil : themName
            ),
            to: originalTranscript
        )
    }

    func handleDetection(_ detection: MeetingWatcher.Detection) {
        pendingDetection = detection
        guard autoRecordEnabled else { return }
        if case .calendar(_, let url?) = detection.kind, !url.isEmpty {
            joinURL = url
            joinAndRecord()
        } else {
            start(title: detection.title)
        }
    }

    func saveSpeakerNames() {
        guard var current = record else { return }
        current.youName = youName.isEmpty ? nil : youName
        current.themName = themName.isEmpty ? nil : themName
        record = current
        try? store.save(current)
    }

    func searchMeetings() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { [weak self] in
            guard let self else { return }
            self.searchHits = self.searchSidecars(query: query, limit: 8)
        }
    }

    private func searchSidecars(
        query: String,
        limit: Int
    ) -> [(id: UUID, snippet: String)] {
        let terms = query.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard limit > 0, !terms.isEmpty else { return [] }
        let records = (try? store.all()) ?? []
        var hits: [(id: UUID, snippet: String)] = []
        for record in records {
            var haystack = record.displayTitle
            if let keyProvider {
                haystack += "\n"
                    + ((try? store.originalTranscript(
                        for: record.id,
                        keyProvider: keyProvider
                    )) ?? "")
                haystack += "\n"
                    + ((try? store.summary(
                        for: record.id,
                        keyProvider: keyProvider
                    )) ?? "")
            }
            let hayLower = haystack.lowercased()
            guard terms.allSatisfy({
                hayLower.contains($0.lowercased())
            }) else { continue }
            hits.append((record.id, Self.snippet(haystack, around: terms[0])))
            if hits.count == limit { break }
        }
        return hits
    }

    private static func snippet(_ text: String, around term: String) -> String {
        let folded = text.lowercased()
        let needle = term.lowercased()
        let match = folded.range(of: needle) ?? text.startIndex..<text.startIndex
        let start = text.index(
            match.lowerBound,
            offsetBy: -20,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let end = text.index(
            match.upperBound,
            offsetBy: 40,
            limitedBy: text.endIndex
        ) ?? text.endIndex
        return String(text[start..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }


    func joinAndRecord() {
        let raw = joinURL
        Task { [weak self] in
            guard let self else { return }
            do {
                self.botJob = try await MeetingBotClient.join(raw)
                self.start(title: raw, source: "bot")
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func enrollMe() {
        guard let id = record?.id, let keyProvider else {
            errorMessage = "Open a meeting with You audio first."
            return
        }
        let youURL = store.youAudioURL(for: id)
        do {
            let embedding = try SpeakerFingerprint.embedding(fromWav: youURL)
            let speakers = store.directoryURL
                .deletingLastPathComponent()
                .appendingPathComponent("Speakers", isDirectory: true)
            let registry = SpeakerRegistry(
                directoryURL: speakers,
                keyProvider: keyProvider
            )
            let name = youName.isEmpty ? "Me" : youName
            _ = try registry.enroll(name: name, embedding: embedding)
            errorMessage = nil
            youName = name
            saveSpeakerNames()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveConnectorTokens() {
        guard let policy = try? RuntimeIdentity.policy() else { return }
        try? CloudAIKeychainKeyStore(policy: policy, account: "gmail-oauth-token")
            .saveKey(gmailToken)
        try? CloudAIKeychainKeyStore(policy: policy, account: "slack-oauth-token")
            .saveKey(slackToken)
    }

    func loadConnectorTokens() {
        guard let policy = try? RuntimeIdentity.policy() else { return }
        gmailToken = (try? CloudAIKeychainKeyStore(
            policy: policy,
            account: "gmail-oauth-token"
        ).loadKey()) ?? ""
        slackToken = (try? CloudAIKeychainKeyStore(
            policy: policy,
            account: "slack-oauth-token"
        ).loadKey()) ?? ""
    }

    func loadContext() {
        saveConnectorTokens()
        let query = MeetingContextQuery(
            attendeeEmails: [],
            windowStart: record?.startedAt ?? Date().addingTimeInterval(-3600),
            windowEnd: Date(),
            title: record?.displayTitle ?? ""
        )
        Task { [weak self] in
            guard let self else { return }
            var hits: [ConnectorHit] = []
            if !self.gmailToken.isEmpty {
                hits += (try? await MailConnector(
                    bearerToken: self.gmailToken
                ).search(query)) ?? []
            }
            if !self.slackToken.isEmpty {
                hits += (try? await SlackConnector(
                    bearerToken: self.slackToken
                ).search(query)) ?? []
            }
            self.contextHits = hits
        }
    }

    func emailRecap() {
        let body = [displayedTranscript, summary]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [
            URLQueryItem(name: "subject", value: record?.displayTitle ?? "Meeting recap"),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    func slackPost() {
        saveConnectorTokens()
        let text = summary ?? displayedTranscript ?? ""
        guard !slackToken.isEmpty, !text.isEmpty else {
            errorMessage = "Save a Slack token and recap first."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            var request = URLRequest(
                url: URL(string: "https://slack.com/api/chat.postMessage")!
            )
            request.httpMethod = "POST"
            request.setValue(
                "Bearer \(self.slackToken)",
                forHTTPHeaderField: "Authorization"
            )
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = try? JSONSerialization.data(
                withJSONObject: [
                    "channel": "general",
                    "text": text
                ]
            )
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let object = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
                if object?["ok"] as? Bool != true {
                    self.errorMessage = object?["error"] as? String
                        ?? "Slack post failed."
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func createCalendarEvent() {
        let store = EKEventStore()
        Task { [weak self] in
            guard let self else { return }
            _ = try? await store.requestFullAccessToEvents()
            let event = EKEvent(eventStore: store)
            event.title = self.record?.displayTitle ?? "Meeting follow-up"
            event.notes = self.summary ?? self.displayedTranscript
            event.startDate = Date().addingTimeInterval(86400)
            event.endDate = event.startDate.addingTimeInterval(1800)
            event.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(event, span: .thisEvent)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }


    func start(title: String? = nil, source: String = "local") {
        errorMessage = nil
        themCaptureFailed = false
        guard !isSessionActive, !isTranscribing else { return }
        guard !isDictationRecording() else {
            errorMessage = "Stop dictation before starting a meeting."
            return
        }
        var created: MeetingStore.Record
        do {
            created = try store.createRecording()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if let title, !title.isEmpty {
            created.title = title
        }
        created.captureSource = source
        try? store.save(created)
        pendingDetection = nil
        do {
            try recorder.start(
                recordingURL: store.youAudioURL(for: created.id),
                capturesLiveSamples: false,
                levelChanged: { _, _ in }
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
        let themURL = store.themAudioURL(for: created.id)
        systemAudioTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.systemAudio.start(writingTo: themURL)
            } catch {
                if Task.isCancelled { return }
                self.themCaptureFailed = true
            }
        }
    }

    func pause() {
        guard isRecording else { return }
        recorder.pause()
        systemAudioTask?.cancel()
        systemAudioTask = Task { [weak self] in
            await self?.systemAudio.pause()
        }
        accumulatedSeconds = currentElapsed()
        runningSince = nil
        stopTick()
        updateStatus(.paused, elapsed: accumulatedSeconds)
        refreshElapsed()
        refreshList()
    }

    func resume() {
        errorMessage = nil
        guard isPaused, let id = record?.id else { return }
        do {
            try recorder.resume()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let themURL = store.themAudioURL(for: id)
        systemAudioTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.systemAudio.resume(writingTo: themURL)
            } catch {
                if Task.isCancelled { return }
                self.themCaptureFailed = true
            }
        }
        runningSince = Date()
        updateStatus(.recording, elapsed: accumulatedSeconds)
        startTick()
        refreshElapsed()
        refreshList()
    }

    func stop() {
        finish(status: .complete)
        beginTranscription()
    }

    func retry() {
        guard canRetry(record) else { return }
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
                    throw MeetingStore.StoreError.io(
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
                self.indexMeeting(
                    id: id,
                    original: originalTranscript,
                    recap: value
                )
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
        youName = opened.youName ?? ""
        themName = opened.themName ?? ""
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
        Task { try? await index?.delete(id: id) }
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

    func canRetry(_ item: MeetingStore.Record?) -> Bool {
        guard let item else { return false }
        return !isSessionActive
            && !isTranscribing
            && item.originalTranscriptCiphertext == nil
            && item.status != .recording
            && item.status != .paused
    }

    func canDelete(_ item: MeetingStore.Record) -> Bool {
        !(isSessionActive && record?.id == item.id)
            && !(isTranscribing && record?.id == item.id)
            && !(isSummarizing && record?.id == item.id)
    }

    func refreshList() {
        meetings = (try? store.all()) ?? []
        meetingAudioBytes = (try? store.inventory().audioBytes) ?? 0
    }

    func markIncompleteForTermination() {
        transcribeTask?.cancel()
        transcribeTask = nil
        summaryTask?.cancel()
        summaryTask = nil
        systemAudioTask?.cancel()
        isSummarizing = false
        guard isSessionActive || isTranscribing else { return }
        finish(status: .incomplete)
        isTranscribing = false
        refreshList()
    }

    private func finish(status: MeetingStore.Status) {
        if status == .complete || status == .completeAtCap {
            completionStatus = status
        }
        systemAudioTask?.cancel()
        systemAudioTask = nil
        if let botJob {
            let job = botJob
            self.botJob = nil
            Task { await MeetingBotClient.leave(job) }
        }
        let measuredElapsed = currentElapsed()
        let recordedAudio = recorder.stop()
        Task { try? await systemAudio.stop() }
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
        let youURL = store.youAudioURL(for: record.id)
        let themURL = store.themAudioURL(for: record.id)
        let id = record.id
        isTranscribing = true
        errorMessage = nil
        updateStatus(.transcribing, elapsed: record.elapsedSeconds)
        refreshList()
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let you = try await transcribeFile(youURL)
                try Task.checkCancellation()
                var them: TranscriptionResult?
                if Self.isUsableAudio(themURL) {
                    them = try await transcribeFile(themURL)
                    try Task.checkCancellation()
                }
                let merged = MeetingTranscript.merging(you: you, them: them)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !merged.isEmpty else {
                    throw MeetingStore.StoreError.io(
                        "The meeting produced no text."
                    )
                }
                try self.store.setOriginalTranscript(
                    merged,
                    for: id,
                    engineID: you.modelID,
                    keyProvider: keyProvider
                )
                self.record = try self.store.load(id: id)
                self.originalTranscript = merged
                self.indexMeeting(id: id, original: merged, recap: "")
                self.updateStatus(
                    self.completionStatus,
                    elapsed: self.record?.elapsedSeconds ?? self.elapsedSeconds
                )
            } catch is CancellationError {
                return
            } catch {
                if FileManager.default.fileExists(atPath: youURL.path) {
                    self.updateStatus(
                        .failed,
                        elapsed: self.record?.elapsedSeconds
                            ?? self.elapsedSeconds
                    )
                }
                self.errorMessage = error.localizedDescription
            }
            self.isTranscribing = false
            self.refreshList()
        }
    }

    private func indexMeeting(id: UUID, original: String, recap: String) {
        Task { [weak self] in
            try? await self?.index?.upsert(
                id: id,
                original: original,
                recap: recap
            )
        }
    }

    private func loadLatest() {
        guard let latest = meetings.first else { return }
        open(latest.id)
    }

    private func updateStatus(
        _ status: MeetingStore.Status,
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
        if MeetingStore.shouldStopAtCap(elapsedSeconds) {
            finish(status: .completeAtCap)
            beginTranscription()
        }
    }

    private func refreshElapsed() {
        elapsedSeconds = currentElapsed()
    }

    private func currentElapsed() -> TimeInterval {
        MeetingStore.displayedElapsed(
            accumulated: accumulatedSeconds,
            runningSince: runningSince,
            now: Date()
        )
    }

    private static func isUsableAudio(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let size = try? FileManager.default.attributesOfItem(
                atPath: url.path
              )[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 44
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
