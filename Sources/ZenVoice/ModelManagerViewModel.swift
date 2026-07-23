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

struct VerifiedModelDownloader {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func download(_ model: VerifiedModel) async throws -> URL {
        guard model.downloadURL.scheme == "https",
              model.downloadURL.host == "huggingface.co",
              model.downloadURL.path.contains(model.sourceRevision),
              model.downloadURL.lastPathComponent == model.filename else {
            throw VerifiedModelDownloadError.invalidSource
        }

        var request = URLRequest(url: model.downloadURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60 * 60
        let (temporaryURL, response) = try await URLSession.shared.download(
            for: request
        )
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
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        return destinationURL
    }
}

@MainActor
final class ModelManagerViewModel: ObservableObject {
    let models = VerifiedModelCatalog.models

    @Published private(set) var installedModelIDs: Set<String> = []
    @Published private(set) var selectedModelID: String?
    @Published private(set) var downloadingModelID: String?
    @Published private(set) var isVerifying = false
    @Published var errorMessage: String?

    private let downloader: VerifiedModelDownloader
    private let fileManager: FileManager
    private let selectionChanged: () -> Void
    private var downloadTask: Task<Void, Never>?
    private var verificationTask: Task<Void, Never>?

    init(
        downloader: VerifiedModelDownloader = VerifiedModelDownloader(),
        fileManager: FileManager = .default,
        selectionChanged: @escaping () -> Void
    ) {
        self.downloader = downloader
        self.fileManager = fileManager
        self.selectionChanged = selectionChanged
        selectedModelID = ModelSelectionPreferences.load()?.id
        refresh()
    }

    func refresh() {
        verificationTask?.cancel()
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
        downloadingModelID = model.id
        downloadTask = Task { [weak self] in
            do {
                _ = try await self?.downloader.download(model)
                guard !Task.isCancelled else {
                    return
                }
                self?.installedModelIDs.insert(model.id)
                self?.select(model)
            } catch is CancellationError {
                // Cancellation is an explicit user action.
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.downloadingModelID = nil
            self?.downloadTask = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingModelID = nil
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

    deinit {
        downloadTask?.cancel()
        verificationTask?.cancel()
    }
}
