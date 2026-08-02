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
        if model.runtime == .parakeetCoreML {
            return try await downloadParakeet(
                model,
                to: directory,
                progress: progress
            )
        }
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

    /// Downloads a multi-file bundle from this catalogue's pinned revision.
    ///
    /// The fetch is done here, file by file, rather than delegated to
    /// FluidAudio: its registry resolves the repository's default branch and
    /// honours `REGISTRY_URL`, so the revision ZenVoice records and the bytes
    /// ZenVoice requested were not the same statement. Every file is verified
    /// in a staging directory and the bundle is swapped into place only once
    /// the whole manifest matches, so an interrupted download cannot leave a
    /// half-written bundle where a verified one used to be.
    private func downloadParakeet(
        _ model: VerifiedModel,
        to directory: URL,
        progress:
            AsyncStream<VerifiedModelDownloadPhase>.Continuation
    ) async throws -> URL {
        guard !model.bundleFiles.isEmpty else {
            throw VerifiedModelDownloadError.invalidSource
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destinationURL = directory.appendingPathComponent(
            model.filename,
            isDirectory: true
        )
        let stagingURL = directory.appendingPathComponent(
            ".\(model.filename).\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }
        try fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let totalBytes = model.bundleFiles.reduce(Int64(0)) {
            $0 + $1.fileSizeBytes
        }
        var completedBytes: Int64 = 0
        for file in model.bundleFiles {
            try Task.checkCancellation()
            guard let sourceURL = model.bundleFileURL(for: file) else {
                throw VerifiedModelDownloadError.invalidSource
            }
            let fileURL = stagingURL.appendingPathComponent(
                file.relativePath,
                isDirectory: false
            )
            guard fileURL.standardizedFileURL.path.hasPrefix(
                stagingURL.standardizedFileURL.path + "/"
            ) else {
                throw VerifiedModelDownloadError.invalidSource
            }
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let fileStart = completedBytes
            try await downloadBundleFile(
                from: sourceURL,
                revision: model.sourceRevision,
                to: fileURL,
                expectedSize: file.fileSizeBytes,
                expectedSHA256: file.sha256
            ) { fraction in
                guard totalBytes > 0 else { return }
                let done = Double(fileStart)
                    + fraction * Double(file.fileSizeBytes)
                progress.yield(.downloading(done / Double(totalBytes)))
            }
            completedBytes += file.fileSizeBytes
        }

        try Task.checkCancellation()
        progress.yield(.verifying)
        guard try VerifiedModelCatalog.verify(
            stagingURL,
            for: model,
            fileManager: fileManager
        ) else {
            throw VerifiedModelDownloadError.checksumMismatch
        }

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

    private func downloadBundleFile(
        from sourceURL: URL,
        revision: String,
        to destinationURL: URL,
        expectedSize: Int64,
        expectedSHA256: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard sourceURL.scheme == "https",
              sourceURL.host == "huggingface.co",
              sourceURL.path.contains(revision) else {
            throw VerifiedModelDownloadError.invalidSource
        }
        var request = URLRequest(url: sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60 * 60

        let stream = AsyncStream<VerifiedModelDownloadPhase>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        let relay = Task {
            for await phase in stream.stream {
                if case let .downloading(fraction) = phase {
                    progress(fraction)
                }
            }
        }
        defer {
            stream.continuation.finish()
            relay.cancel()
        }

        let (temporaryURL, response) = try await download(
            request,
            expectedSize: expectedSize,
            progress: stream.continuation
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
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destinationURL.path
        )
    }


    private func download(
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
    let hardwareProfile: HardwareProfile

    @Published private(set) var installedModelIDs: Set<String> = []
    @Published private(set) var selectedModelID: String?
    @Published private(set) var downloadingModelID: String?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var isVerifyingDownload = false
    @Published private(set) var isVerifying = false
    @Published private(set) var benchmarkSummaries:
        [String: ModelBenchmarkSummary] = [:]
    @Published var errorMessage: String?

    private let downloader: VerifiedModelDownloader
    private let fileManager: FileManager
    private let applySelection:
        (VerifiedModel, LanguageProfile) -> Result<Void, Error>
    private let selectionInvalidated: () -> Void
    private var downloadTask: Task<Void, Never>?
    private var activeDownloadID: UUID?
    private var verificationTask: Task<Void, Never>?

    init(
        downloader: VerifiedModelDownloader = VerifiedModelDownloader(),
        fileManager: FileManager = .default,
        applySelection: @escaping
            (VerifiedModel, LanguageProfile) -> Result<Void, Error>,
        selectionInvalidated: @escaping () -> Void
    ) {
        self.downloader = downloader
        self.fileManager = fileManager
        self.applySelection = applySelection
        self.selectionInvalidated = selectionInvalidated
        hardwareProfile = HardwareProfile.current(fileManager: fileManager)
        selectedModelID = ModelSelectionPreferences.load()?.id
        refreshBenchmarks()
        refresh()
    }

    func refresh() {
        verificationTask?.cancel()
        refreshBenchmarks()
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
                          (try? VerifiedModelCatalog.verify(
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
            self?.isVerifying = false
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

    deinit {
        downloadTask?.cancel()
        verificationTask?.cancel()
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
