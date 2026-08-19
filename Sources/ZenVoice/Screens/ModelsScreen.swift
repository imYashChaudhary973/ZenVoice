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

import SwiftUI
import ZenVoiceCore
import ZenVoiceStorage

private enum EngineGroup: String, CaseIterable {
    case defaults
    case advanced

    var displayName: String {
        switch self {
        case .defaults:
            return "Defaults"
        case .advanced:
            return "Advanced"
        }
    }

    func contains(_ engineID: String) -> Bool {
        let defaults: Set<String> = [
            EngineIdentifiers.appleSpeech,
            EngineIdentifiers.parakeetTDTv3,
            EngineIdentifiers.whisper
        ]
        switch self {
        case .defaults:
            return defaults.contains(engineID)
        case .advanced:
            return !defaults.contains(engineID)
        }
    }
}

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
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            ZenSection(
                title: "What matters most?",
                caption: viewModel.hardwareProfile.summary
            ) {
                HStack(spacing: ZenDesign.Spacing.sm) {
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
                title: "Measured on this Mac",
                caption: "Common Voice Spontaneous, 262 clips, 2026-08-18"
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    werRow("Parakeet TDT v3", "6.9% WER · 73× · English/European default")
                    werRow("Whisper Turbo", "8.2% WER · 11× · 99 languages")
                    werRow("Cohere Transcribe", "10.8% WER · 5× · local, 3 GB, slower")
                    werRow("Parakeet Flash", "14.1% WER · preview only")
                    werRow("Nemotron Ultra Fast", "23.8% WER · preview only")
                    Text("Hinglish Apex keeps 85% of English loanwords; Turbo keeps 0/31. No telemetry.")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .padding(.top, 4)
                }
            }

            ZenSection(
                title: "Speech engine",
                caption: "Runtime that transcribes the current language"
            ) {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    if viewModel.engineAvailabilities.isEmpty {
                        HStack(spacing: ZenDesign.Spacing.xs) {
                            ProgressView().controlSize(.small)
                            Text("Loading engines…")
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        }
                    } else {
                        ForEach(engineGroups, id: \.self) { group in
                            let availabilities = engineAvailabilities(
                                in: group
                            )
                            if !availabilities.isEmpty {
                                VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                                    Text(group.displayName)
                                        .font(
                                            ZenDesign.Typography.captionStrong
                                        )
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textSecondary
                                        )
                                    ZenPanel {
                                        ForEach(
                                            availabilities,
                                            id: \.engine.id
                                        ) { availability in
                                            if availability.engine.id
                                                != availabilities.first?
                                                .engine.id {
                                                ZenPanelDivider()
                                            }
                                            engineRow(availability)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ZenSection(
                title: "Speech models",
                caption: "Mac-optimized local runtimes"
            ) {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    if viewModel.isVerifying {
                        HStack(spacing: ZenDesign.Spacing.xs) {
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
                        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
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
                        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
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

    private func werRow(_ name: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Spacer(minLength: ZenDesign.Spacing.sm)
            Text(detail)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func engineDisplayName(_ engine: EngineDescriptor) -> String {
        if engine.id == EngineIdentifiers.nemotronSpeechMultilingual {
            return "Nemotron 3.5"
        }
        return engine.displayName
    }

    private func engineCaption(_ engine: EngineDescriptor) -> String {
        if engine.id == EngineIdentifiers.cohereTranscribe {
            return "Local ONNX, 14 languages, ~3 GB, slower. Off by default."
        }
        if engine.id == EngineIdentifiers.parakeetFlash {
            return "Live preview only. Final insert stays TDT v3 or Turbo."
        }
        if engine.id == EngineIdentifiers.nemotronSpeechMultilingual {
            return viewModel.nemotronMode == .streaming
                ? "Streaming is live preview only (23.8% WER). Final insert stays TDT v3 or Turbo."
                : "Offline whole-file path. Not the default. Final insert still prefers TDT v3 or Turbo."
        }
        if engine.id == EngineIdentifiers.appleSpeech {
            return "Zero-download fallback. Unmeasured — convenience, not quality."
        }
        return engine.privacyNote
    }

    private func engineRow(_ availability: EngineAvailability) -> some View {
        let engineID = availability.engine.id
        let isPreviewOnly = EngineIdentifiers.isPreviewOnly(engineID)
            || (engineID == EngineIdentifiers.nemotronSpeechMultilingual
                && viewModel.nemotronMode == .streaming)
        let isSelected = viewModel.isSelectedEngine(engineID)
        let isAvailable = availability.isAvailable

        return VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
            HStack(spacing: ZenDesign.Spacing.sm) {
                Image(systemName: engineIcon(for: availability.engine.family))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(ZenDesign.Semantic.surfaceRaised)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: ZenDesign.Spacing.xs) {
                        Text(engineDisplayName(availability.engine))
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(
                                isAvailable
                                    ? ZenDesign.Semantic.textPrimary
                                    : ZenDesign.Semantic.textSecondary
                            )
                        if isPreviewOnly {
                            ZenBadge(text: "Preview only", kind: .neutral)
                        } else if isSelected {
                            ZenBadge(
                                text: "In use",
                                kind: .success,
                                systemImage: "checkmark"
                            )
                        } else if !isAvailable {
                            ZenBadge(
                                text: engineStatusLabel(for: availability),
                                kind: .warn
                            )
                        } else if viewModel.isRecommendedEngine(engineID) {
                            ZenBadge(
                                text: "Recommended",
                                kind: .accent
                            )
                        }
                    }
                    Text(engineCaption(availability.engine))
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: ZenDesign.Spacing.sm)

                if isAvailable, !isSelected, !isPreviewOnly {
                    Button("Use") {
                        viewModel.selectEngine(engineID)
                    }
                    .buttonStyle(ZenPrimaryButtonStyle(minWidth: 60))
                } else if !isAvailable,
                          availability.engine.requiresDownload,
                          let engine = viewModel.engines.first(where: {
                              $0.descriptor.id == engineID
                          }) {
                    Button(viewModel.isEngineDownloading(engine)
                           ? "Downloading…"
                           : "Download") {
                        viewModel.downloadEngine(engine)
                    }
                    .buttonStyle(ZenSecondaryButtonStyle(minWidth: 80))
                    .disabled(viewModel.isEngineDownloading(engine))
                }
            }

            if engineID == EngineIdentifiers.nemotronSpeechMultilingual {
                Picker(
                    "Nemotron mode",
                    selection: Binding(
                        get: { viewModel.nemotronMode },
                        set: { viewModel.setNemotronMode($0) }
                    )
                ) {
                    ForEach(NemotronPreferences.Mode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.leading, 44)
            }

            ZenModelMeta(parts: [
                availability.engine.family.displayName,
                availability.engine.format,
                availability.engine.license
            ])
            .padding(.leading, 44)
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .padding(.vertical, ZenDesign.Spacing.sm)
    }

    private var engineGroups: [EngineGroup] {
        EngineGroup.allCases
    }

    private func engineAvailabilities(
        in group: EngineGroup
    ) -> [EngineAvailability] {
        viewModel.engineAvailabilities.filter {
            $0.engine.id != EngineIdentifiers.nemotronSpeechUltraFast
                && group.contains($0.engine.id)
        }
    }

    private func engineIcon(for family: EngineFamily) -> String {
        switch family {
        case .appleSpeech:
            return "apple.logo"
        case .whisper:
            return "waveform.circle"
        case .parakeetTDT, .parakeetFlash:
            return "bird"
        case .nemotronSpeech:
            return "cpu"
        case .cohereTranscribe:
            return "internaldrive"
        }
    }

    private func engineStatusLabel(for availability: EngineAvailability)
        -> String {
        guard let reason = availability.reason else {
            return "Unavailable"
        }
        switch reason {
        case .unsupportedLanguage:
            return "Unsupported language"
        case .requiresDownload:
            return "Download required"
        case .requiresInternet:
            return "Internet required"
        case .runtimeNotReady:
            return "Not ready"
        case .platformNotSupported:
            return "Unsupported Mac"
        }
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

        return VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
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
                    HStack(spacing: ZenDesign.Spacing.xs) {
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
                    .font(ZenDesign.Typography.caption)
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
