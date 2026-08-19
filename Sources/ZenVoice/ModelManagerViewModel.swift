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

private final class DownloadTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var wasCancelled = false
    private var exceededExpectedSize = false

    func install(_ task: URLSessionDownloadTask) {
        lock.lock()
        self.task = task
        let shouldCancel = wasCancelled
        lock.unlock()
        if shouldCancel {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func cancelForUnexpectedSize() {
        lock.lock()
        exceededExpectedSize = true
        let task = task
        lock.unlock()
        task?.cancel()
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
        let handle = DownloadTaskHandle()
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
                        if received > expectedSize
                            || announced > expectedSize {
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
    @Published private(set) var nemotronMode: NemotronPreferences.Mode =
        NemotronPreferences.load()
    @Published var errorMessage: String?

    private let downloader: VerifiedModelDownloader
    private let fileManager: FileManager
    private let applySelection:
        (VerifiedModel, LanguageProfile) -> Result<Void, Error>
    private let selectionInvalidated: () -> Void
    private let engineRegistryProvider: () -> EngineRegistry?
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
        engineRegistryProvider: @escaping () -> EngineRegistry? = { nil }
    ) {
        self.downloader = downloader
        self.fileManager = fileManager
        self.applySelection = applySelection
        self.selectionInvalidated = selectionInvalidated
        self.engineRegistryProvider = engineRegistryProvider
        hardwareProfile = HardwareProfile.current(fileManager: fileManager)
        selectedModelID = ModelSelectionPreferences.load()?.id
        refreshBenchmarks()
        refreshEngineSelection()
        refresh()
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
        for engine in engines {
            let isInstalled: Bool
            switch engine.descriptor.id {
            case EngineIdentifiers.parakeetTDTv3:
                let modelsDirectory = try? VerifiedModelCatalog.modelsDirectory(
                    fileManager: fileManager
                )
                let modelURL = modelsDirectory?
                    .appendingPathComponent(
                        ParakeetTDTEngine.Configuration.v3.modelFilename,
                        isDirectory: false
                    )
                isInstalled = modelURL.map {
                    fileManager.fileExists(atPath: $0.path)
                } ?? false
            case EngineIdentifiers.cohereTranscribe:
                let modelsDirectory = try? VerifiedModelCatalog.modelsDirectory(
                    fileManager: fileManager
                )
                let engine = modelsDirectory.map {
                    CohereTranscribeEngine(modelsDirectory: $0)
                }
                isInstalled = engine?.isAvailable ?? false
            default:
                isInstalled = engine.descriptor.requiresDownload == false
            }
            if isInstalled {
                installed.insert(engine.descriptor.id)
            }
        }
        installedEngineIDs = installed
    }

    func refreshEngineSelection() {
        let profile = LanguagePreferences.load()
        if let selected = SelectedEnginePreferences.load(for: profile),
           EngineIdentifiers.isPreviewOnly(selected) {
            SelectedEnginePreferences.clear(for: profile)
            selectedEngineID = nil
        } else {
            selectedEngineID = SelectedEnginePreferences.load(for: profile)
        }
        engineAvailabilities =
            engineRegistryProvider()?.availability(for: profile) ?? []
        nemotronMode = NemotronPreferences.load()
    }

    func setNemotronMode(_ mode: NemotronPreferences.Mode) {
        NemotronPreferences.save(mode)
        nemotronMode = mode
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
        engineRecommendation()?.preferredEngineID == engineID
    }

    func selectEngine(_ engineID: String) {
        if EngineIdentifiers.isPreviewOnly(engineID) {
            errorMessage =
                "Preview only — final insert uses Parakeet TDT v3 or Whisper Turbo."
            return
        }
        let profile = LanguagePreferences.load()
        guard let availability = engineAvailabilities.first(
            where: { $0.engine.id == engineID }
        ) else {
            return
        }
        guard availability.isAvailable else {
            errorMessage = unavailabilityLabel(for: availability)
            return
        }
        SelectedEnginePreferences.save(engineID, for: profile)
        selectedEngineID = engineID
        enginePrepareTask?.cancel()
        enginePrepareTask = Task { [weak self] in
            do {
                try await self?.engineRegistryProvider()?.prepare(
                    for: profile,
                    selectedID: engineID
                )
            } catch is CancellationError {
                // User moved on before preparation finished.
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func isSelectedEngine(_ engineID: String) -> Bool {
        selectedEngineID == engineID
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
        case .runtimeNotReady:
            return "\(engineName) is not ready on this Mac."
        case .platformNotSupported:
            return "\(engineName) is not supported on this Mac."
        }
    }

    func download(_ model: VerifiedModel) {
        guard downloadTask == nil else {
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
        apply(model: model, profile: targetProfile)
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
        selectedModelID == model.id
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

    func downloadEngine(_ engine: VerifiedEngine) {
        guard engineDownloadTasks[engine.descriptor.id] == nil else {
            return
        }
        errorMessage = nil
        engineDownloadTasks[engine.descriptor.id] = Task { [weak self] in
            defer {
                self?.engineDownloadTasks.removeValue(
                    forKey: engine.descriptor.id
                )
                self?.refreshEngineInstallStatus()
                self?.refreshEngineSelection()
            }
            do {
                switch engine.descriptor.id {
                case EngineIdentifiers.parakeetFlash:
                    try await self?.downloadParakeetFlash()
                case EngineIdentifiers.parakeetTDTv2:
                    try await self?.downloadParakeetTDTv2()
                case EngineIdentifiers.parakeetTDTv3:
                    try await self?.downloadParakeetTDTv3()
                case EngineIdentifiers.nemotronSpeechUltraFast,
                     EngineIdentifiers.nemotronSpeechMultilingual:
                    try await self?.downloadNemotronModel()
                case EngineIdentifiers.cohereTranscribe:
                    try await self?.downloadCohereModel()
                default:
                    break
                }
            } catch is CancellationError {
                // Explicit user cancellation is handled by the UI.
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func downloadParakeetFlash() async throws {
        try await downloadEngineModel(
            engineID: EngineIdentifiers.parakeetFlash,
            filename: ParakeetFlashEngine.modelFilename
        )
    }

    private func downloadParakeetTDTv2() async throws {
        try await downloadEngineModel(
            engineID: EngineIdentifiers.parakeetTDTv2,
            filename: ParakeetTDTEngine.Configuration.v2.modelFilename
        )
    }

    private func downloadParakeetTDTv3() async throws {
        try await downloadEngineModel(
            engineID: EngineIdentifiers.parakeetTDTv3,
            filename: ParakeetTDTEngine.Configuration.v3.modelFilename
        )
    }

    private func downloadNemotronModel() async throws {
        try await downloadEngineModel(
            engineID: EngineIdentifiers.nemotronSpeechMultilingual,
            filename: NemotronEngineConstants.modelFilename
        )
    }

    private func downloadCohereModel() async throws {
        let base =
            "https://huggingface.co/cstr/cohere-transcribe-onnx-int8/resolve/main/"
        let engine = VerifiedEngineCatalog.engine(
            id: EngineIdentifiers.cohereTranscribe
        )
        guard let sourceRevision = engine?.sourceRevision else {
            throw VerifiedModelDownloadError.invalidSource
        }
        let directory = try VerifiedModelCatalog.modelsDirectory(
            fileManager: fileManager
        )
        try await downloadCohereFile(
            filename: VerifiedEngineCatalog.cohereEncoderFilename,
            sourceURL: URL(string: base + "cohere-encoder.int8.onnx?download=true")!,
            expectedSize: VerifiedEngineCatalog.cohereEncoderSizeBytes,
            expectedSHA256: VerifiedEngineCatalog.cohereEncoderSHA256,
            sourceRevision: sourceRevision,
            destinationDirectory: directory
        )
        try await downloadCohereFile(
            filename: VerifiedEngineCatalog.cohereDecoderFilename,
            sourceURL: URL(string: base + "cohere-decoder.int8.onnx?download=true")!,
            expectedSize: VerifiedEngineCatalog.cohereDecoderSizeBytes,
            expectedSHA256: VerifiedEngineCatalog.cohereDecoderSHA256,
            sourceRevision: sourceRevision,
            destinationDirectory: directory
        )
        try await downloadCohereFile(
            filename: VerifiedEngineCatalog.cohereTokenizerFilename,
            sourceURL: URL(string: base + "tokens.txt?download=true")!,
            expectedSize: VerifiedEngineCatalog.cohereTokenizerSizeBytes,
            expectedSHA256: VerifiedEngineCatalog.cohereTokenizerSHA256,
            sourceRevision: sourceRevision,
            destinationDirectory: directory
        )
        try await downloadCohereFile(
            filename: VerifiedEngineCatalog.cohereEncoderDataFilename,
            sourceURL: URL(string: base + "cohere-encoder.int8.onnx.data?download=true")!,
            expectedSize: VerifiedEngineCatalog.cohereEncoderDataSizeBytes,
            expectedSHA256: VerifiedEngineCatalog.cohereEncoderDataSHA256,
            sourceRevision: sourceRevision,
            destinationDirectory: directory
        )
        try await downloadCohereFile(
            filename: VerifiedEngineCatalog.cohereDecoderDataFilename,
            sourceURL: URL(string: base + "cohere-decoder.int8.onnx.data?download=true")!,
            expectedSize: VerifiedEngineCatalog.cohereDecoderDataSizeBytes,
            expectedSHA256: VerifiedEngineCatalog.cohereDecoderDataSHA256,
            sourceRevision: sourceRevision,
            destinationDirectory: directory
        )
    }

    private func downloadCohereFile(
        filename: String,
        sourceURL: URL,
        expectedSize: Int64,
        expectedSHA256: String,
        sourceRevision: String,
        destinationDirectory: URL
    ) async throws {
        let (_, progress) =
            AsyncStream<VerifiedModelDownloadPhase>.makeStream()
        defer { progress.finish() }
        _ = try await downloader.download(
            sourceURL: sourceURL,
            sourceRevision: sourceRevision,
            filename: filename,
            expectedSize: expectedSize,
            expectedSHA256: expectedSHA256,
            destinationDirectory: destinationDirectory,
            progress: progress
        )
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
        let (_, progress) =
            AsyncStream<VerifiedModelDownloadPhase>.makeStream()
        defer { progress.finish() }
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
