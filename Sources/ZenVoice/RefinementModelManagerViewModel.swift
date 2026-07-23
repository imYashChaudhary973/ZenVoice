import Combine
import Foundation
import ZenVoiceCore

@MainActor
final class RefinementModelManagerViewModel: ObservableObject {
    let models = VerifiedRefinementModelCatalog.models
    let hardwareProfile: HardwareProfile

    @Published private(set) var installedModelIDs: Set<String> = []
    @Published private(set) var selectedModelID: String?
    @Published private(set) var downloadingModelID: String?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var isVerifyingDownload = false
    @Published private(set) var isVerifying = false
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
        selectedModelID =
            RefinementModelSelectionPreferences.load()?.id
        refresh()
    }

    var hasSelectedInstalledModel: Bool {
        guard let selectedModelID else {
            return false
        }
        return installedModelIDs.contains(selectedModelID)
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
                          let url =
                            try? VerifiedRefinementModelCatalog
                                .installedURL(
                                    for: model,
                                    fileManager: fileManager
                                ),
                          (try? VerifiedRefinementModelCatalog.verify(
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
            if let selected =
                RefinementModelSelectionPreferences.load(),
               !installed.contains(selected.id) {
                RefinementModelSelectionPreferences.clear()
                self?.selectedModelID = nil
                self?.errorMessage =
                    "The selected refinement model failed verification and was disabled."
            } else {
                self?.selectedModelID =
                    RefinementModelSelectionPreferences.load()?.id
            }
            self?.isVerifying = false
            self?.selectionChanged()
        }
    }

    func download(_ model: VerifiedRefinementModel) {
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
                guard !Task.isCancelled, let self else {
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

    func select(_ model: VerifiedRefinementModel) {
        guard installedModelIDs.contains(model.id) else {
            errorMessage =
                VerifiedModelDownloadError.modelNotInstalled
                    .localizedDescription
            return
        }
        RefinementModelSelectionPreferences.save(model)
        selectedModelID = model.id
        errorMessage = nil
        selectionChanged()
    }

    func remove(_ model: VerifiedRefinementModel) {
        guard downloadingModelID != model.id else {
            return
        }
        do {
            let url =
                try VerifiedRefinementModelCatalog.installedURL(
                    for: model,
                    fileManager: fileManager
                )
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            installedModelIDs.remove(model.id)
            if selectedModelID == model.id {
                RefinementModelSelectionPreferences.clear()
                selectedModelID = nil
                selectionChanged()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isInstalled(_ model: VerifiedRefinementModel) -> Bool {
        installedModelIDs.contains(model.id)
    }

    func isSelected(_ model: VerifiedRefinementModel) -> Bool {
        selectedModelID == model.id
    }

    func recommendation(
        for model: VerifiedRefinementModel
    ) -> ModelRecommendation {
        let storageHeadroom = max(
            model.fileSizeBytes * 2,
            model.fileSizeBytes + 512 * 1_048_576
        )
        guard hardwareProfile.availableModelStorageBytes
                >= storageHeadroom else {
            return ModelRecommendation(
                level: .insufficientStorage,
                title: "More storage needed",
                rationale:
                    "Keep at least \(formatted(storageHeadroom)) free for safe installation."
            )
        }
        guard Int64(hardwareProfile.physicalMemoryBytes)
                >= model.minimumMemoryBytes else {
            return ModelRecommendation(
                level: .caution,
                title: "May feel slow",
                rationale:
                    "Designed for \(model.formattedMinimumMemory) memory or more; manual override remains available."
            )
        }
        let recommendedTier: RefinementModelTier =
            hardwareProfile.memoryGigabytes >= 16
                ? .balanced
                : .fast
        return ModelRecommendation(
            level:
                model.tier == recommendedTier
                    ? .recommended
                    : .supported,
            title:
                model.tier == recommendedTier
                    ? "Recommended"
                    : "Compatible",
            rationale:
                model.tier == .fast
                    ? "Prioritizes response time and lower memory use."
                    : "Uses more memory for stronger instruction following."
        )
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }

    deinit {
        downloadTask?.cancel()
        verificationTask?.cancel()
    }
}
