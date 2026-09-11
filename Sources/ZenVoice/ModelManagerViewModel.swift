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

import Combine
import Foundation
import ZenVoiceCore
import ZenVoiceRuntime

enum VerifiedModelDownloadError: LocalizedError {
    case invalidSource
    case invalidResponse
    case unexpectedSize
    case rangeUnsupported
    case checksumMismatch
    case modelNotInstalled

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            "ZenVoice blocked an unapproved model source."
        case .invalidResponse:
            "The approved model server returned an invalid response."
        case .unexpectedSize:
            "The downloaded model has an unexpected file size."
        case .rangeUnsupported:
            "The download source ignored range requests; retrying."
        case .checksumMismatch:
            "The downloaded model failed SHA-256 verification."
        case .modelNotInstalled:
            "Download and verify this model before selecting it."
        }
    }
}

enum VerifiedModelDownloadPhase: Sendable {
    case downloading(Double)
    case verifying
}

private final class MultiPartDownloadHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [URLSessionDownloadTask] = []
    private var wasCancelled = false
    private var exceededExpectedSize = false
    private var finished = false
    var expectedTotalBytes: Int64 = 0

    func finish() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished || wasCancelled || exceededExpectedSize
    }

    var activeTasks: [URLSessionDownloadTask] {
        lock.lock()
        defer { lock.unlock() }
        return tasks.filter { $0.state == .running }
    }

    func setExpectedTotalBytes(_ bytes: Int64) {
        lock.lock()
        expectedTotalBytes = bytes
        lock.unlock()
    }

    func install(_ task: URLSessionDownloadTask) {
        lock.lock()
        if wasCancelled {
            lock.unlock()
            task.cancel()
            return
        }
        tasks.append(task)
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let tasks = tasks
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    func cancelForUnexpectedSize() {
        lock.lock()
        exceededExpectedSize = true
        let tasks = tasks
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    var wasCancelledForUnexpectedSize: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exceededExpectedSize
    }
}

struct VerifiedModelDownloader {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func download(
        _ model: VerifiedModel,
        progress:
            AsyncStream<VerifiedModelDownloadPhase>.Continuation
    ) async throws -> URL {
        let directory = try VerifiedModelCatalog.modelsDirectory(
            fileManager: fileManager
        )
        return try await download(
            sourceURL: model.downloadURL,
            sourceRevision: model.sourceRevision,
            filename: model.filename,
            expectedSize: model.fileSizeBytes,
            expectedSHA256: model.sha256,
            destinationDirectory: directory,
            progress: progress
        )
    }

    fileprivate func download(
        sourceURL: URL,
        sourceRevision: String,
        filename: String,
        expectedSize: Int64,
        expectedSHA256: String,
        destinationDirectory: URL,
        progress:
            AsyncStream<VerifiedModelDownloadPhase>.Continuation
    ) async throws -> URL {
        guard sourceURL.scheme == "https",
              sourceURL.host == "huggingface.co",
              sourceURL.path.contains(sourceRevision),
              sourceURL.lastPathComponent == filename else {
            throw VerifiedModelDownloadError.invalidSource
        }

        var request = URLRequest(url: sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60 * 60
        let (temporaryURL, response) = try await download(
            request,
            expectedSize: expectedSize,
            progress: progress
        )
        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode),
              response.url?.scheme == "https" else {
            throw VerifiedModelDownloadError.invalidResponse
        }

        progress.yield(.verifying)
        let values = try temporaryURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              Int64(values.fileSize ?? -1) == expectedSize else {
            throw VerifiedModelDownloadError.unexpectedSize
        }
        guard try VerifiedModelCatalog.sha256Hex(of: temporaryURL)
                == expectedSHA256 else {
            throw VerifiedModelDownloadError.checksumMismatch
        }

        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: destinationDirectory.path
        )

        let stagingURL = destinationDirectory
            .appendingPathComponent(".\(filename).\(UUID().uuidString)")
        let destinationURL =
            destinationDirectory.appendingPathComponent(filename)
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: stagingURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stagingURL.path
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        }
        return destinationURL
    }

    private func download(
        _ request: URLRequest,
        expectedSize: Int64,
        progress:
            AsyncStream<VerifiedModelDownloadPhase>.Continuation
    ) async throws -> (URL, URLResponse) {
        // HuggingFace's CDN throttles per connection, so large files are
        // fetched as concurrent byte ranges. Small files keep one stream.
        guard expectedSize >= 16 * 1_048_576 else {
            return try await downloadSingle(
                request,
                expectedSize: expectedSize,
                progress: progress
            )
        }
        let handle = MultiPartDownloadHandle()
        defer { handle.finish() }
        let partSize = Int64((Double(expectedSize) / 4).rounded(.up))
        var ranges: [Range<Int64>] = []
        var start: Int64 = 0
        while start < expectedSize {
            let end = min(start + partSize, expectedSize)
            ranges.append(start..<end)
            start = end
        }

        let poller = Task.detached(priority: .utility) {
            while !handle.isFinished {
                let received = handle.activeTasks.reduce(Int64(0)) {
                    $0 + max(0, $1.countOfBytesReceived)
                }
                if received > expectedSize {
                    handle.cancelForUnexpectedSize()
                    return
                }
                let fraction = min(
                    1,
                    Double(received) / Double(max(1, expectedSize))
                )
                progress.yield(.downloading(fraction))
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { poller.cancel() }

        return try await withTaskCancellationHandler {
            // Probe with the first range. A 200 means the server ignored
            // Range and sent the whole file — exactly the single-stream
            // result, so reuse it.
            let first = try await downloadPart(
                request: request,
                byteRange: ranges[0],
                handle: handle
            )
            guard let httpResponse = first.response as? HTTPURLResponse,
                  httpResponse.statusCode == 206 else {
                return (first.url, first.response)
            }
            var byIndex = [URL?](repeating: nil, count: ranges.count)
            byIndex[0] = first.url
            try await withThrowingTaskGroup(of: (Int, URL).self) { group in
                for (index, range) in ranges.enumerated().dropFirst() {
                    group.addTask {
                        let part = try await self.downloadPart(
                            request: request,
                            byteRange: range,
                            handle: handle
                        )
                        guard let response = part.response as? HTTPURLResponse,
                              response.statusCode == 206 else {
                            throw VerifiedModelDownloadError.rangeUnsupported
                        }
                        let values = try part.url.resourceValues(forKeys: [
                            .fileSizeKey
                        ])
                        guard Int64(values.fileSize ?? -1)
                            == range.upperBound - range.lowerBound else {
                            throw VerifiedModelDownloadError.unexpectedSize
                        }
                        return (index, part.url)
                    }
                }
                for try await (index, url) in group {
                    byIndex[index] = url
                }
            }
            let partURLs = try byIndex.map { url in
                guard let url else {
                    throw VerifiedModelDownloadError.invalidResponse
                }
                return url
            }
            let assembledURL = try assemble(partURLs)
            return (assembledURL, first.response)
        } onCancel: {
            handle.cancel()
        }
    }

    private func downloadPart(
        request: URLRequest,
        byteRange: Range<Int64>,
        handle: MultiPartDownloadHandle
    ) async throws -> (url: URL, response: URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var partRequest = request
                partRequest.setValue(
                    "bytes=\(byteRange.lowerBound)-\(byteRange.upperBound - 1)",
                    forHTTPHeaderField: "Range"
                )
                let task = URLSession.shared.downloadTask(
                    with: partRequest
                ) { temporaryURL, response, error in
                    if handle.wasCancelledForUnexpectedSize {
                        continuation.resume(
                            throwing:
                                VerifiedModelDownloadError.unexpectedSize
                        )
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else if let temporaryURL, let response {
                        do {
                            let retainedURL =
                                FileManager.default.temporaryDirectory
                                .appendingPathComponent(
                                    "ZenVoice-\(UUID().uuidString).part"
                                )
                            try FileManager.default.moveItem(
                                at: temporaryURL,
                                to: retainedURL
                            )
                            continuation.resume(
                                returning: (retainedURL, response)
                            )
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    } else {
                        continuation.resume(
                            throwing:
                                VerifiedModelDownloadError.invalidResponse
                        )
                    }
                }
                handle.install(task)
                task.resume()
            }
        } onCancel: {
            handle.cancel()
        }
    }

    private func assemble(_ partURLs: [URL]) throws -> URL {
        // The first part is renamed into place; the rest append in order
        // and are deleted as they are consumed, so peak disk use stays
        // close to one copy of the file.
        let assembledURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZenVoice-\(UUID().uuidString).download")
        try FileManager.default.moveItem(at: partURLs[0], to: assembledURL)
        let destination = try FileHandle(forWritingTo: assembledURL)
        // FileHandle(forWritingTo:) opens at position 0; without this seek
        // the first appended part overwrites part 0 instead of extending.
        try destination.seekToEnd()
        defer { try? destination.close() }
        for part in partURLs.dropFirst() {
            let source = try FileHandle(forReadingFrom: part)
            do {
                while let chunk = try source.read(upToCount: 1_048_576),
                      !chunk.isEmpty {
                    try destination.write(contentsOf: chunk)
                }
                try? source.close()
                try FileManager.default.removeItem(at: part)
            } catch {
                try? source.close()
                throw error
            }
        }
        return assembledURL
    }

    private func downloadSingle(
        _ request: URLRequest,
        expectedSize: Int64,
        progress:
            AsyncStream<VerifiedModelDownloadPhase>.Continuation
    ) async throws -> (URL, URLResponse) {
        let handle = MultiPartDownloadHandle()
        handle.setExpectedTotalBytes(expectedSize)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.downloadTask(
                    with: request
                ) { temporaryURL, response, error in
                    if handle.wasCancelledForUnexpectedSize {
                        continuation.resume(
                            throwing:
                                VerifiedModelDownloadError.unexpectedSize
                        )
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else if let temporaryURL, let response {
                        do {
                            let retainedURL =
                                FileManager.default.temporaryDirectory
                                .appendingPathComponent(
                                    "ZenVoice-\(UUID().uuidString).download"
                                )
                            try FileManager.default.moveItem(
                                at: temporaryURL,
                                to: retainedURL
                            )
                            continuation.resume(
                                returning: (retainedURL, response)
                            )
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    } else {
                        continuation.resume(
                            throwing:
                                VerifiedModelDownloadError.invalidResponse
                        )
                    }
                }
                handle.install(task)
                task.resume()

                Task.detached(priority: .utility) {
                    while task.state == .running {
                        let received = max(0, task.countOfBytesReceived)
                        let announced =
                            task.countOfBytesExpectedToReceive
                        if received > handle.expectedTotalBytes
                            || announced > handle.expectedTotalBytes {
                            handle.cancelForUnexpectedSize()
                            return
                        }
                        let fraction = min(
                            1,
                            Double(received) / Double(max(1, handle.expectedTotalBytes))
                        )
                        progress.yield(.downloading(fraction))
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                }
            }
        } onCancel: {
            handle.cancel()
        }
    }
}

@MainActor
final class ModelManagerViewModel: ObservableObject {
    let models = VerifiedModelCatalog.models
    let engines = VerifiedEngineCatalog.engines
    let hardwareProfile: HardwareProfile

    @Published private(set) var installedModelIDs: Set<String> = []
    @Published private(set) var selectedModelID: String?
    @Published private(set) var downloadingModelID: String?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var isVerifyingDownload = false
    @Published private(set) var isVerifying = false
    @Published private(set) var benchmarkSummaries:
        [String: ModelBenchmarkSummary] = [:]
    @Published private(set) var selectedEngineID: String?
    @Published private(set) var engineAvailabilities: [EngineAvailability] = []
    @Published private(set) var installedEngineIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published var openAISpeechKeyDraft = ""
    @Published var geminiSpeechKeyDraft = ""
    @Published var elevenLabsSpeechKeyDraft = ""
    @Published private(set) var hasOpenAISpeechKey = false
    @Published private(set) var hasGeminiSpeechKey = false
    @Published private(set) var hasElevenLabsSpeechKey = false

    private let downloader: VerifiedModelDownloader
    private let fileManager: FileManager
    private let applySelection:
        (VerifiedModel, LanguageProfile) -> Result<Void, Error>
    private let selectionInvalidated: () -> Void
    private let engineRegistryProvider: () -> EngineRegistry?
    private let openAISpeechKeyStore: any CloudAIKeyStoring
    private let geminiSpeechKeyStore: any CloudAIKeyStoring
    private let elevenLabsSpeechKeyStore: any CloudAIKeyStoring
    private var downloadTask: Task<Void, Never>?
    private var activeDownloadID: UUID?
    private var verificationTask: Task<Void, Never>?
    private var enginePrepareTask: Task<Void, Never>?
    private var engineDownloadTasks: [String: Task<Void, Never>] = [:]

    init(
        downloader: VerifiedModelDownloader = VerifiedModelDownloader(),
        fileManager: FileManager = .default,
        applySelection: @escaping
            (VerifiedModel, LanguageProfile) -> Result<Void, Error>,
        selectionInvalidated: @escaping () -> Void,
        engineRegistryProvider: @escaping () -> EngineRegistry? = { nil },
        openAISpeechKeyStore: any CloudAIKeyStoring = InMemoryCloudAIKeyStore(),
        geminiSpeechKeyStore: any CloudAIKeyStoring = InMemoryCloudAIKeyStore(),
        elevenLabsSpeechKeyStore: any CloudAIKeyStoring = InMemoryCloudAIKeyStore()
    ) {
        self.downloader = downloader
        self.fileManager = fileManager
        self.applySelection = applySelection
        self.selectionInvalidated = selectionInvalidated
        self.engineRegistryProvider = engineRegistryProvider
        self.openAISpeechKeyStore = openAISpeechKeyStore
        self.geminiSpeechKeyStore = geminiSpeechKeyStore
        self.elevenLabsSpeechKeyStore = elevenLabsSpeechKeyStore
        hardwareProfile = HardwareProfile.current(fileManager: fileManager)
        selectedModelID = ModelSelectionPreferences.load()?.id
        refreshCloudSpeechKeys()
        refreshBenchmarks()
        refreshEngineSelection()
        refresh()
    }

    func refreshCloudSpeechKeys() {
        hasOpenAISpeechKey = hasKey(openAISpeechKeyStore)
        hasGeminiSpeechKey = hasKey(geminiSpeechKeyStore)
        hasElevenLabsSpeechKey = hasKey(elevenLabsSpeechKeyStore)
    }

    func saveOpenAISpeechKey() {
        saveKey(
            openAISpeechKeyDraft,
            store: openAISpeechKeyStore,
            clearDraft: { openAISpeechKeyDraft = "" }
        )
    }

    func saveGeminiSpeechKey() {
        saveKey(
            geminiSpeechKeyDraft,
            store: geminiSpeechKeyStore,
            clearDraft: { geminiSpeechKeyDraft = "" }
        )
    }

    func deleteOpenAISpeechKey() {
        deleteKey(store: openAISpeechKeyStore)
    }

    func deleteGeminiSpeechKey() {
        deleteKey(store: geminiSpeechKeyStore)
    }

    func saveElevenLabsSpeechKey() {
        saveKey(
            elevenLabsSpeechKeyDraft,
            store: elevenLabsSpeechKeyStore,
            clearDraft: { elevenLabsSpeechKeyDraft = "" }
        )
    }

    func deleteElevenLabsSpeechKey() {
        deleteKey(store: elevenLabsSpeechKeyStore)
    }

    private func hasKey(_ store: any CloudAIKeyStoring) -> Bool {
        let key = (try? store.loadKey()) ?? nil
        return !(key?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ?? true)
    }

    private func saveKey(
        _ draft: String,
        store: any CloudAIKeyStoring,
        clearDraft: () -> Void
    ) {
        let trimmed = draft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        do {
            try store.saveKey(trimmed)
            clearDraft()
            refreshCloudSpeechKeys()
            refreshEngineSelection()
            selectionInvalidated()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteKey(store: any CloudAIKeyStoring) {
        do {
            try store.deleteKey()
            refreshCloudSpeechKeys()
            refreshEngineSelection()
            selectionInvalidated()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() {
        verificationTask?.cancel()
        refreshBenchmarks()
        refreshEngineInstallStatus()
        isVerifying = true
        // Retired models are hidden from the catalogue, not invalidated.
        // Verify them too so an existing selection keeps working until the
        // user explicitly moves to an offered model.
        let models = VerifiedModelCatalog.allModels
        let fileManager = fileManager
        verificationTask = Task { [weak self] in
            let installed = await Task.detached(priority: .utility) {
                var result = Set<String>()
                for model in models {
                    guard !Task.isCancelled,
                          let url = try? VerifiedModelCatalog.installedURL(
                            for: model,
                            fileManager: fileManager
                          ),
                          // Listing variant: this runs over every catalogue
                          // entry each time the window opens. Nothing is
                          // loaded on its answer — `ZenVoiceConfiguration`
                          // hashes for real before a model is used.
                          (try? VerifiedModelCatalog.verifyForListing(
                            url,
                            for: model,
                            fileManager: fileManager
                          )) == true else {
                        continue
                    }
                    result.insert(model.id)
                }
                return result
            }.value
            guard !Task.isCancelled else {
                return
            }
            self?.installedModelIDs = installed
            if let selected = ModelSelectionPreferences.load(),
               !installed.contains(selected.id) {
                ModelSelectionPreferences.clear()
                self?.selectedModelID = nil
                self?.errorMessage =
                    "The selected model could not be verified and was disabled."
                self?.selectionInvalidated()
            } else {
                self?.selectedModelID = ModelSelectionPreferences.load()?.id
            }
            self?.refreshEngineInstallStatus()
            self?.isVerifying = false
        }
    }

    func refreshEngineInstallStatus() {
        var installed: Set<String> = []
        let modelsDirectory = try? VerifiedModelCatalog.modelsDirectory(
            fileManager: fileManager
        )
        for engine in engines {
            let id = EngineIdentifiers.canonical(engine.descriptor.id)
            let filename = engine.downloadFilename
                ?? VerifiedModelCatalog.model(id: id)?.filename
            if let filename, let modelsDirectory {
                let modelURL = modelsDirectory.appendingPathComponent(
                    filename,
                    isDirectory: false
                )
                if fileManager.fileExists(atPath: modelURL.path) {
                    installed.insert(id)
                }
            } else if engine.descriptor.requiresDownload == false {
                installed.insert(id)
            }
        }
        installedEngineIDs = installed
    }

    func refreshEngineSelection() {
        let profile = LanguagePreferences.load()
        if let selected = SelectedEnginePreferences.load(for: profile) {
            if !EngineIdentifiers.isKnown(selected) {
                SelectedEnginePreferences.clear(for: profile)
                selectedEngineID = nil
            } else {
                let canonical = EngineIdentifiers.canonical(selected)
                if canonical != selected {
                    SelectedEnginePreferences.save(canonical, for: profile)
                }
                selectedEngineID = canonical
            }
        } else {
            selectedEngineID = nil
        }
        let active =
            engineRegistryProvider()?.availability(for: profile) ?? []
        var merged = active
        let activeIDs = Set(active.map(\.engine.id))
        merged.append(
            contentsOf: engines.compactMap { engine in
                let id = EngineIdentifiers.canonical(engine.descriptor.id)
                guard !activeIDs.contains(id) else {
                    return nil
                }
                let installed = installedEngineIDs.contains(id)
                return EngineAvailability(
                    engine: engine.descriptor,
                    isAvailable: installed,
                    reason: installed
                        ? nil
                        : (engine.descriptor.requiresDownload
                            ? .requiresDownload
                            : .runtimeNotReady(id))
                )
            }
        )
        engineAvailabilities = merged
    }

    func engineRecommendation() -> EngineRecommendation? {
        guard let registry = engineRegistryProvider() else {
            return nil
        }
        return EngineRecommendationEngine.recommendation(
            for: LanguagePreferences.load(),
            hardware: hardwareProfile,
            registry: registry
        )
    }

    func isRecommendedEngine(_ engineID: String) -> Bool {
        engineRecommendation()?.preferredEngineID
            == EngineIdentifiers.canonical(engineID)
    }

    func recommendedEngineRationale() -> String? {
        engineRecommendation()?.rationale
    }

    func selectEngine(_ engineID: String) {
        let id = EngineIdentifiers.canonical(engineID)
        let profile = LanguagePreferences.load()
        if let availability = engineAvailabilities.first(where: {
            $0.engine.id == id
        }), !availability.isAvailable,
           availability.reason != nil,
           availability.reason != .requiresDownload {
            errorMessage = unavailabilityLabel(for: availability)
            return
        }
        if let engine = engines.first(where: { $0.descriptor.id == id }),
           engine.descriptor.requiresDownload,
           !installedEngineIDs.contains(id) {
            downloadEngine(engine, thenSelect: true)
            return
        }
        if let model = VerifiedModelCatalog.model(id: id) {
            guard case .success = apply(model: model, profile: profile) else {
                return
            }
        }
        SelectedEnginePreferences.save(id, for: profile)
        selectedEngineID = id
        enginePrepareTask?.cancel()
        enginePrepareTask = Task { [weak self] in
            do {
                try await self?.engineRegistryProvider()?.prepare(
                    for: profile,
                    selectedID: id
                )
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
        selectionInvalidated()
    }

    var activeEngineID: String? {
        let profile = LanguagePreferences.load()
        return engineRegistryProvider()?.resolve(
            for: profile,
            selectedID: SelectedEnginePreferences.load(for: profile)
        )?.descriptor.id
    }

    var activeEngineDisplayName: String {
        let profile = LanguagePreferences.load()
        guard let engine = engineRegistryProvider()?.resolve(
            for: profile,
            selectedID: SelectedEnginePreferences.load(for: profile)
        ) else {
            return "Not installed"
        }
        return engine.descriptor.displayName
    }

    func isSelectedEngine(_ engineID: String) -> Bool {
        activeEngineID == EngineIdentifiers.canonical(engineID)
    }

    private func unavailabilityLabel(for availability: EngineAvailability)
        -> String {
        guard let reason = availability.reason else {
            return "\(availability.engine.displayName) is not available."
        }
        let engineName = availability.engine.displayName
        switch reason {
        case .unsupportedLanguage(let language):
            return "\(engineName) does not support \(language)."
        case .requiresDownload:
            return "\(engineName) needs its model downloaded first."
        case .requiresInternet:
            return "\(engineName) needs an internet connection."
        case .requiresAPIKey:
            return "Add an API key below to use \(engineName)."
        case .runtimeNotReady:
            return "\(engineName) is not ready on this Mac."
        case .platformNotSupported:
            return "\(engineName) is not supported on this Mac."
        }
    }

    func download(_ model: VerifiedModel) {
        guard downloadTask == nil,
              engineDownloadTasks.isEmpty else {
            return
        }
        errorMessage = nil
        let downloadID = UUID()
        activeDownloadID = downloadID
        downloadingModelID = model.id
        downloadProgress = 0
        isVerifyingDownload = false
        let downloader = downloader
        let (progressStream, progressContinuation) =
            AsyncStream<VerifiedModelDownloadPhase>.makeStream()
        let progressTask = Task { [weak self] in
            for await phase in progressStream {
                guard self?.activeDownloadID == downloadID else {
                    return
                }
                switch phase {
                case .downloading(let fraction):
                    self?.downloadProgress = fraction
                    self?.isVerifyingDownload = false
                case .verifying:
                    self?.downloadProgress = 1
                    self?.isVerifyingDownload = true
                }
            }
        }
        downloadTask = Task { [weak self] in
            defer {
                progressContinuation.finish()
                progressTask.cancel()
            }
            do {
                _ = try await downloader.download(
                    model,
                    progress: progressContinuation
                )
                guard !Task.isCancelled else {
                    return
                }
                guard let self else {
                    return
                }
                installedModelIDs.insert(model.id)
                select(model)
            } catch is CancellationError {
                // Cancellation is an explicit user action.
            } catch {
                guard let self,
                      self.activeDownloadID == downloadID else {
                    return
                }
                self.errorMessage = error.localizedDescription
            }
            guard let self,
                  self.activeDownloadID == downloadID else {
                return
            }
            self.activeDownloadID = nil
            self.downloadingModelID = nil
            self.downloadProgress = nil
            self.isVerifyingDownload = false
            self.downloadTask = nil
        }
    }

    func cancelDownload() {
        activeDownloadID = nil
        downloadTask?.cancel()
        downloadTask = nil
        for task in engineDownloadTasks.values {
            task.cancel()
        }
        engineDownloadTasks.removeAll()
        downloadingModelID = nil
        downloadProgress = nil
        isVerifyingDownload = false
    }

    func select(_ model: VerifiedModel) {
        guard installedModelIDs.contains(model.id) else {
            errorMessage =
                VerifiedModelDownloadError.modelNotInstalled.localizedDescription
            return
        }
        let currentProfile = LanguagePreferences.load()
        guard let targetProfile =
                ModelProfileTransition.profileForSelecting(
                    model: model,
                    currentProfile: currentProfile
                ) else {
            errorMessage =
                ModelProfileTransition.incompatibleSelectionMessage(
                    model: model,
                    currentProfile: currentProfile
                )
            return
        }
        guard case .success = apply(model: model, profile: targetProfile) else {
            return
        }
        refreshEngineSelection()
        selectEngine(model.id)
    }

    @discardableResult
    func selectProfile(
        _ profile: LanguageProfile
    ) -> Result<Void, Error> {
        let currentModel = ModelSelectionPreferences.load()
        let installed = VerifiedModelCatalog.allModels.filter {
            installedModelIDs.contains($0.id)
        }
        let recommendedID = ModelRecommendationEngine.recommendedModel(
            for: hardwareProfile,
            language: profile
        )?.id
        guard let model = ModelProfileTransition.modelForSelecting(
            profile: profile,
            currentModel: currentModel,
            installedModels: installed,
            recommendedModelID: recommendedID
        ) else {
            let error = ZenVoiceConfiguration.ConfigurationError
                .incompatibleProfile(
                    ModelProfileTransition.unavailableMessage(for: profile)
                )
            errorMessage = error.localizedDescription
            return .failure(error)
        }
        return apply(model: model, profile: profile)
    }

    var selectedLegacyModel: VerifiedModel? {
        guard let selectedModelID,
              installedModelIDs.contains(selectedModelID),
              let selected = VerifiedModelCatalog.model(id: selectedModelID),
              VerifiedModelCatalog.isRetired(selected) else {
            return nil
        }
        return selected
    }

    /// Retired models sitting on disk that nothing is using.
    ///
    /// ``selectedLegacyModel`` only surfaces a retired model while it is the
    /// selected one, which leaves every *other* retired install invisible and
    /// undeletable. That was a rounding error when one model was retired; after
    /// the catalogue was cut from ten offered models to five it can be several
    /// gigabytes — Whisper Medium English alone is 1.5 GB — with no screen in
    /// the app admitting the files exist.
    var reclaimableModels: [VerifiedModel] {
        VerifiedModelCatalog.retiredModels.filter {
            installedModelIDs.contains($0.id) && $0.id != selectedModelID
        }
    }

    var reclaimableBytes: Int64 {
        reclaimableModels.reduce(0) { $0 + $1.fileSizeBytes }
    }

    var recommendedInstalledModel: VerifiedModel? {
        let profile = LanguagePreferences.load()
        let recommendedID = ModelRecommendationEngine.recommendedModel(
            for: hardwareProfile,
            language: profile
        )?.id
        let installed = models.filter {
            installedModelIDs.contains($0.id)
                && profile.isCompatible(with: $0.languageCapability)
        }
        return installed.first { $0.id == recommendedID }
            ?? installed.first
    }

    func switchFromLegacyModel() {
        guard let recommendedInstalledModel else {
            errorMessage =
                "Download a current compatible model before switching."
            return
        }
        select(recommendedInstalledModel)
    }

    func remove(_ model: VerifiedModel) {
        guard downloadingModelID != model.id else {
            return
        }
        do {
            let url = try VerifiedModelCatalog.installedURL(
                for: model,
                fileManager: fileManager
            )
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            installedModelIDs.remove(model.id)
            if selectedModelID == model.id {
                ModelSelectionPreferences.clear()
                selectedModelID = nil
                selectionInvalidated()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isInstalled(_ model: VerifiedModel) -> Bool {
        installedModelIDs.contains(model.id)
    }

    func isSelected(_ model: VerifiedModel) -> Bool {
        activeEngineID == EngineIdentifiers.whisper
            && selectedModelID == model.id
    }

    func isLanguageCompatible(_ model: VerifiedModel) -> Bool {
        LanguagePreferences.load().isCompatible(
            with: model.languageCapability
        )
    }

    func selectionProfile(for model: VerifiedModel) -> LanguageProfile? {
        ModelProfileTransition.profileForSelecting(
            model: model,
            currentProfile: LanguagePreferences.load()
        )
    }

    func recommendation(for model: VerifiedModel) -> ModelRecommendation {
        // The user's language decides this as much as their hardware does.
        // Recommending on hardware alone pointed every Hinglish user at a
        // general model, which preserves none of the English half of a
        // code-switched sentence.
        ModelRecommendationEngine.recommendation(
            for: model,
            profile: hardwareProfile,
            language: LanguagePreferences.load()
        )
    }

    func benchmarkSummary(
        for model: VerifiedModel
    ) -> ModelBenchmarkSummary? {
        benchmarkSummaries[model.id]
    }

    func refreshBenchmarks() {
        benchmarkSummaries = Dictionary(
            uniqueKeysWithValues: models.compactMap { model in
                ModelBenchmarkStore.summary(for: model.id).map {
                    (model.id, $0)
                }
            }
        )
    }

    func isEngineDownloading(_ engine: VerifiedEngine) -> Bool {
        engineDownloadTasks[engine.descriptor.id]?.isCancelled == false
    }

    func downloadEngine(_ engine: VerifiedEngine, thenSelect: Bool = false) {
        let id = EngineIdentifiers.canonical(engine.descriptor.id)
        guard engineDownloadTasks[id] == nil,
              downloadTask == nil else {
            return
        }
        errorMessage = nil
        downloadingModelID = id
        downloadProgress = 0
        isVerifyingDownload = false
        engineDownloadTasks[id] = Task { [weak self] in
            defer {
                self?.engineDownloadTasks.removeValue(forKey: id)
                self?.downloadingModelID = nil
                self?.downloadProgress = nil
                self?.isVerifyingDownload = false
                self?.refreshEngineInstallStatus()
                self?.refreshEngineSelection()
            }
            do {
                guard let filename = engine.downloadFilename
                    ?? VerifiedModelCatalog.model(id: id)?.filename
                else {
                    throw VerifiedModelDownloadError.invalidSource
                }
                try await self?.downloadEngineModel(
                    engineID: id,
                    filename: filename
                )
                await MainActor.run {
                    self?.refreshEngineInstallStatus()
                    if let model = VerifiedModelCatalog.model(id: id) {
                        self?.installedModelIDs.insert(model.id)
                    }
                    if thenSelect {
                        self?.selectEngine(id)
                    } else {
                        self?.selectionInvalidated()
                    }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func downloadEngineModel(
        engineID: String,
        filename: String
    ) async throws {
        guard let engine = VerifiedEngineCatalog.engine(id: engineID),
              let sourceURL = engine.downloadURL,
              let sha256 = engine.sha256,
              let fileSize = engine.fileSizeBytes,
              let sourceRevision = engine.sourceRevision
        else {
            throw VerifiedModelDownloadError.invalidSource
        }
        let directory = try VerifiedModelCatalog.modelsDirectory(
            fileManager: fileManager
        )
        let (stream, progress) =
            AsyncStream<VerifiedModelDownloadPhase>.makeStream()
        let reporter = Task { [weak self] in
            for await phase in stream {
                guard let self else { return }
                switch phase {
                case .downloading(let fraction):
                    self.downloadProgress = fraction
                    self.isVerifyingDownload = false
                case .verifying:
                    self.downloadProgress = 1
                    self.isVerifyingDownload = true
                }
            }
        }
        defer {
            progress.finish()
            reporter.cancel()
        }
        _ = try await downloader.download(
            sourceURL: sourceURL,
            sourceRevision: sourceRevision,
            filename: filename,
            expectedSize: fileSize,
            expectedSHA256: sha256,
            destinationDirectory: directory,
            progress: progress
        )
    }

    deinit {
        downloadTask?.cancel()
        verificationTask?.cancel()
        engineDownloadTasks.values.forEach { $0.cancel() }
    }

    @discardableResult
    private func apply(
        model: VerifiedModel,
        profile: LanguageProfile
    ) -> Result<Void, Error> {
        switch applySelection(model, profile) {
        case .success:
            selectedModelID = model.id
            errorMessage = nil
            return .success(())
        case .failure(let error):
            errorMessage = error.localizedDescription
            return .failure(error)
        }
    }
}
