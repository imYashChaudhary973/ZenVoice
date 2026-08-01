import SwiftUI
import ZenVoiceCore
import ZenVoiceStorage

struct ModelsScreen: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    @State private var modelPendingRemoval: VerifiedModel?
    @State private var selectedTier: ModelPerformanceTier?

    private var recommendedTier: ModelPerformanceTier {
        ModelRecommendationEngine.recommendedTier(
            for: viewModel.hardwareProfile,
            language: LanguagePreferences.load()
        )
    }

    private var activeTier: ModelPerformanceTier {
        selectedTier ?? recommendedTier
    }

    /// All models, with the picked tier's models listed first.
    private var orderedModels: [VerifiedModel] {
        viewModel.models.sorted { lhs, rhs in
            let lhsPick = lhs.tier == activeTier
            let rhsPick = rhs.tier == activeTier
            if lhsPick != rhsPick { return lhsPick }
            return false
        }
    }

    var body: some View {
        ZenScreen(
            title: "Models",
            subtitle:
                "Speech models run entirely on this Mac. Verified before first use."
        ) {
            ZenSection(
                title: "What matters most?",
                caption: viewModel.hardwareProfile.summary
            ) {
                HStack(spacing: ZenDesign.Spacing.xs) {
                    tierCard(
                        .fast,
                        icon: "gauge.with.needle",
                        detail: "Lowest latency · good accuracy"
                    )
                    tierCard(
                        .balanced,
                        icon: "slider.horizontal.3",
                        detail: "Best accuracy per second"
                    )
                    tierCard(
                        .highAccuracy,
                        icon: "target",
                        detail: "Strongest results · multilingual"
                    )
                }
            }

            ZenSection(
                title: "Speech models",
                caption: "Mac-optimized local runtimes"
            ) {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    if viewModel.isVerifying {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.small)
                            Text("Verifying installed models…")
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                        }
                    }

                    if let error = viewModel.errorMessage {
                        ZenBanner(
                            kind: .danger,
                            icon: "exclamationmark.triangle",
                            text: error
                        )
                    }

                    if let legacy = viewModel.selectedLegacyModel {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("Legacy model")
                                    .font(ZenDesign.Typography.captionStrong)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                                Spacer()
                                Text("Still verified and usable")
                                    .font(ZenDesign.Typography.caption)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textTertiary
                                    )
                            }
                            ZenPanel {
                                modelRow(legacy, isLegacy: true)
                            }
                        }
                    }

                    if !viewModel.reclaimableModels.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("No longer offered")
                                    .font(ZenDesign.Typography.captionStrong)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                                Spacer()
                                Text(
                                    "\(formattedBytes(viewModel.reclaimableBytes)) can be freed"
                                )
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                            }
                            ZenPanel {
                                ForEach(viewModel.reclaimableModels) { model in
                                    if model.id
                                        != viewModel.reclaimableModels
                                            .first?.id {
                                        ZenPanelDivider()
                                    }
                                    modelRow(model, isLegacy: true)
                                }
                            }
                        }
                    }

                    ZenPanel {
                        ForEach(orderedModels) { model in
                            if model.id != orderedModels.first?.id {
                                ZenPanelDivider()
                            }
                            modelRow(model)
                        }
                    }
                }
            }

            ZenBanner(
                kind: .info,
                icon: "internaldrive",
                text:
                    "Publisher, revision, licence, size, and checksum are recorded for every model — see the Verified Model Catalogue. Deleting a model frees its disk space immediately. After download, transcription runs locally with no account or API key."
            )
        }
        .alert(
            "Remove downloaded model?",
            isPresented: Binding(
                get: { modelPendingRemoval != nil },
                set: { if !$0 { modelPendingRemoval = nil } }
            ),
            presenting: modelPendingRemoval
        ) { model in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                viewModel.remove(model)
                modelPendingRemoval = nil
            }
        } message: { model in
            Text(
                "\(model.displayName) (\(model.languageCapability.displayName)) will be removed from this Mac."
            )
        }
    }

    private func tierCard(
        _ tier: ModelPerformanceTier,
        icon: String,
        detail: String
    ) -> some View {
        ZenChoiceCard(
            title: tier.displayName,
            badge: tier == recommendedTier ? "This Mac" : nil,
            detail: detail,
            selected: activeTier == tier,
            titleIcon: icon
        ) {
            selectedTier = tier
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func modelRow(
        _ model: VerifiedModel,
        isLegacy: Bool = false
    ) -> some View {
        let isInstalled = viewModel.isInstalled(model)
        let isSelected = viewModel.isSelected(model)
        let isCompatible = viewModel.isLanguageCompatible(model)
        let selectionProfile = viewModel.selectionProfile(for: model)
        let isDownloading = viewModel.downloadingModelID == model.id
        let recommendation = viewModel.recommendation(for: model)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: ZenDesign.Spacing.sm) {
                Image(
                    systemName: {
                        switch model.languageCapability {
                        case .multilingual: "globe"
                        case .hinglish: "character.bubble"
                        case .english: "character.book.closed"
                        }
                    }()
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ZenDesign.Semantic.surfaceRaised)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(model.displayName)
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        if isSelected {
                            ZenBadge(
                                text: isLegacy ? "In use · Legacy" : "In use",
                                kind: isLegacy ? .neutral : .success,
                                systemImage: "checkmark"
                            )
                        } else if let badge =
                                    ModelProfileTransition
                                        .incompatibilityBadge(
                                            model: model,
                                            currentProfile:
                                                LanguagePreferences.load()
                                        ) {
                            ZenBadge(text: badge, kind: .neutral)
                        } else if model.tier == recommendedTier,
                                  recommendation.level == .recommended {
                            ZenBadge(
                                text: "Recommended for this Mac",
                                kind: .accent
                            )
                        }
                    }
                    Text(
                        rowNote(
                            model,
                            recommendation: recommendation,
                            isLegacy: isLegacy
                        )
                    )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: ZenDesign.Spacing.sm)

                trailingControls(
                    model,
                    isInstalled: isInstalled,
                    isSelected: isSelected,
                    isCompatible: isCompatible,
                    selectionProfile: selectionProfile,
                    isLegacy: isLegacy,
                    isDownloading: isDownloading,
                    recommendation: recommendation
                )
            }

            ZenModelMeta(parts: [
                model.languageCapability.displayName,
                model.formattedFileSize,
                "rev \(model.sourceRevision.prefix(9))",
                "sha256 \(model.sha256.prefix(8))…",
                model.license
            ])
            .padding(.leading, 44)
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .padding(.vertical, ZenDesign.Spacing.sm)
    }

    private func rowNote(
        _ model: VerifiedModel,
        recommendation: ModelRecommendation,
        isLegacy: Bool
    ) -> String {
        if isLegacy {
            return
                "This model remains available for existing installations "
                + "but is no longer recommended. Switch when you are ready."
        }
        if let benchmark = viewModel.benchmarkSummary(for: model) {
            let factor = benchmark.averageRealtimeFactor.formatted(
                .number.precision(.fractionLength(2))
            )
            let samples = "\(benchmark.sampleCount) local sample"
                + (benchmark.sampleCount == 1 ? "" : "s")
            return "\(recommendation.rationale) · \(factor)× realtime from \(samples)."
        }
        return recommendation.rationale
    }

    @ViewBuilder
    private func trailingControls(
        _ model: VerifiedModel,
        isInstalled: Bool,
        isSelected: Bool,
        isCompatible: Bool,
        selectionProfile: LanguageProfile?,
        isLegacy: Bool,
        isDownloading: Bool,
        recommendation: ModelRecommendation
    ) -> some View {
        if isDownloading {
            VStack(alignment: .trailing, spacing: 5) {
                ZenProgressBar(value: viewModel.downloadProgress ?? 0)
                    .frame(width: 120)
                HStack(spacing: 6) {
                    Text(
                        viewModel.isVerifyingDownload
                            ? "verifying checksum…"
                            : "\(Int(((viewModel.downloadProgress ?? 0) * 100).rounded()))% of \(model.formattedFileSize)"
                    )
                    .font(ZenDesign.Typography.monoSmall)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    Button("Cancel", action: viewModel.cancelDownload)
                        .buttonStyle(.plain)
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
            }
        } else if isInstalled {
            HStack(spacing: 6) {
                if isSelected,
                   isLegacy,
                   viewModel.recommendedInstalledModel != nil {
                    Button("Use recommended") {
                        viewModel.switchFromLegacyModel()
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                } else if !isSelected {
                    Button(
                        isCompatible ? "Use" : "Switch & use"
                    ) {
                        viewModel.select(model)
                    }
                    .buttonStyle(ZenPrimaryButtonStyle(minWidth: 60))
                    .disabled(selectionProfile == nil)
                }
                ZenIconButton(
                    systemImage: "trash",
                    label: "Remove \(model.displayName)",
                    isDanger: true
                ) {
                    modelPendingRemoval = model
                }
            }
        } else {
            Button {
                viewModel.download(model)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(ZenSecondaryButtonStyle())
            .disabled(recommendation.level == .insufficientStorage)
        }
    }
}
