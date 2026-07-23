import Combine
import Foundation
import ZenVoiceCore

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
        guard model.downloadURL.scheme == "https",
              model.downloadURL.host == "huggingface.co",
              model.downloadURL.path.contains(model.sourceRevision),
              model.downloadURL.lastPathComponent == model.filename else {
            throw VerifiedModelDownloadError.invalidSource
        }

        var request = URLRequest(url: model.downloadURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60 * 60
        let (temporaryURL, response) = try await download(
            request,
            expectedSize: model.fileSizeBytes,
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
              Int64(values.fileSize ?? -1) == model.fileSizeBytes else {
            throw VerifiedModelDownloadError.unexpectedSize
        }
        guard try VerifiedModelCatalog.sha256Hex(of: temporaryURL)
                == model.sha256 else {
            throw VerifiedModelDownloadError.checksumMismatch
        }

        let directory = try VerifiedModelCatalog.modelsDirectory(
            fileManager: fileManager
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        let stagingURL = directory
            .appendingPathComponent(".\(model.filename).\(UUID().uuidString)")
        let destinationURL = directory.appendingPathComponent(model.filename)
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
                    if let error {
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
    private let selectionChanged: () -> Void
    private var downloadTask: Task<Void, Never>?
    private var activeDownloadID: UUID?
    private var verificationTask: Task<Void, Never>?

    init(
        downloader: VerifiedModelDownloader = VerifiedModelDownloader(),
        fileManager: FileManager = .default,
        selectionChanged: @escaping () -> Void
    ) {
        self.downloader = downloader
        self.fileManager = fileManager
        self.selectionChanged = selectionChanged
        hardwareProfile = HardwareProfile.current(fileManager: fileManager)
        selectedModelID = ModelSelectionPreferences.load()?.id
        refreshBenchmarks()
        refresh()
    }

    func refresh() {
        verificationTask?.cancel()
        refreshBenchmarks()
        isVerifying = true
        let models = models
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
                self?.selectionChanged()
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
        ModelSelectionPreferences.save(model)
        selectedModelID = model.id
        errorMessage = nil
        selectionChanged()
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
                selectionChanged()
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

    func recommendation(for model: VerifiedModel) -> ModelRecommendation {
        ModelRecommendationEngine.recommendation(
            for: model,
            profile: hardwareProfile
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
}
