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

struct ModelMismatchAlert: Equatable {
    var title: String
    var description: String
    var token = UUID()
}

struct ModelsScreen: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    @Binding var mismatchAlert: ModelMismatchAlert?
    @State private var modelPendingRemoval: VerifiedModel?

    var body: some View {
        ZenSection(title: "Speech engines") {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                Text(
                    "Choose the engine that transcribes. Every listed option "
                        + "runs on this Mac."
                )
                .font(ZenDesign.Typography.body)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)

                if viewModel.isVerifying {
                    HStack(spacing: ZenDesign.Spacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Verifying installed models…")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }
                }

                if let error = viewModel.errorMessage,
                   !error.contains("Automatic detection requires") {
                    ZenBanner(
                        kind: .danger,
                        icon: "exclamationmark.triangle",
                        text: error
                    )
                }

                ZenPanel {
                    if viewModel.engineAvailabilities.isEmpty {
                        Text("Engine availability is loading…")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                            .padding(ZenDesign.Spacing.md)
                    } else {
                        ForEach(
                            Array(viewModel.engineAvailabilities.enumerated()),
                            id: \.element.engine.id
                        ) { index, availability in
                            if index > 0 { ZenPanelDivider() }
                            engineRow(availability)
                        }
                    }
                }

                Text("Models")
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .padding(.top, ZenDesign.Spacing.sm)

                Text(
                    "The active row is the file the engine above loads. "
                        + "Only Whisper can pick among four."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)

                ZenPanel {
                    ForEach(
                        Array(listedModels.enumerated()),
                        id: \.element.id
                    ) { index, item in
                        if index > 0 { ZenPanelDivider() }
                        switch item {
                        case .engine(let linked):
                            engineModelRow(linked)
                        case .whisper(let model):
                            modelRow(model)
                        }
                    }
                }
            }
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
            Text("\(model.displayName) will be removed from this Mac.")
        }
    }

    private func modelRow(_ model: VerifiedModel) -> some View {
        let installed = viewModel.isInstalled(model)
        let selected = viewModel.isSelected(model)
        let downloading = viewModel.downloadingModelID == model.id

        return VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
            HStack(spacing: ZenDesign.Spacing.sm) {
                ZenIconChip(
                    systemImage: "cpu",
                    size: ZenDesign.Layout.hitTarget,
                    tint: selected
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Semantic.textSecondary
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text("\(model.languageCapability.displayName) · \(model.formattedFileSize) · \(model.tier.displayName)")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                Spacer()

                if selected {
                    ZenBadge(
                        text: "Active",
                        kind: .success,
                        systemImage: "checkmark"
                    )
                } else if downloading {
                    Button("Cancel") { viewModel.cancelDownload() }
                        .buttonStyle(ZenSecondaryButtonStyle())
                } else if installed {
                    Button("Use") { chooseWhisper(model) }
                        .buttonStyle(ZenPrimaryButtonStyle())
                    ZenIconButton(
                        systemImage: "trash",
                        label: "Remove \(model.displayName)",
                        isDanger: true
                    ) {
                        modelPendingRemoval = model
                    }
                } else {
                    Button("Download") { viewModel.download(model) }
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .disabled(viewModel.downloadingModelID != nil)
                }
            }

            if downloading {
                VStack(alignment: .leading, spacing: 5) {
                    ZenProgressBar(value: viewModel.downloadProgress ?? 0)
                        .frame(height: 3)
                    Text(
                        viewModel.isVerifyingDownload
                            ? "Verifying checksum…"
                            : "Downloading \(Int(((viewModel.downloadProgress ?? 0) * 100).rounded()))%"
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                .padding(.leading, 50)
            }
        }
        .padding(.horizontal, ZenDesign.Spacing.lg)
        .padding(.vertical, ZenDesign.Spacing.md)
    }

    private func engineRow(_ availability: EngineAvailability) -> some View {
        let selected = viewModel.isSelectedEngine(availability.engine.id)
        let downloadable = viewModel.engines.first {
            $0.descriptor.id == availability.engine.id
        }
        let downloadingEngine = downloadable.map(viewModel.isEngineDownloading) ?? false

        return VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
            ZenRow(
                icon: "waveform",
                iconTint: selected ? ZenDesign.Semantic.accent : nil,
                title: availability.engine.displayName,
                subtitle: availability.engine.privacyNote
            ) {
                if selected {
                    ZenBadge(text: "Active", kind: .success)
                } else if availability.isAvailable {
                    if viewModel.isRecommendedEngine(availability.engine.id) {
                        ZenBadge(
                            text: "Recommended",
                            kind: .accent,
                            systemImage: "sparkles"
                        )
                    }
                    Button("Use") {
                        viewModel.selectEngine(availability.engine.id)
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                } else if let downloadable,
                          availability.engine.requiresDownload {
                    if downloadingEngine {
                        Button("Cancel") { viewModel.cancelDownload() }
                            .buttonStyle(ZenSecondaryButtonStyle())
                    } else {
                        Button("Download") {
                            viewModel.downloadEngine(downloadable)
                        }
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .disabled(viewModel.downloadingModelID != nil)
                    }
                } else {
                    ZenBadge(text: "Unavailable", kind: .neutral)
                }
            }

            if downloadingEngine {
                VStack(alignment: .leading, spacing: 5) {
                    ZenProgressBar(value: viewModel.downloadProgress ?? 0)
                        .frame(height: 3)
                    Text(
                        viewModel.isVerifyingDownload
                            ? "Verifying checksum…"
                            : "Downloading \(Int(((viewModel.downloadProgress ?? 0) * 100).rounded()))%"
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                .padding(.leading, 50)
            }
        }
        .padding(.horizontal, ZenDesign.Spacing.lg)
        .padding(.vertical, ZenDesign.Spacing.md)
    }

    private enum ListedModel: Identifiable {
        case engine(EngineLinkedModel)
        case whisper(VerifiedModel)

        var id: String {
            switch self {
            case .engine(let linked): return "engine-\(linked.id)"
            case .whisper(let model): return "whisper-\(model.id)"
            }
        }
    }

    private struct EngineLinkedModel: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let engineIDs: [String]
        let engineName: String
    }

    private var listedModels: [ListedModel] {
        engineLinkedModels.map(ListedModel.engine)
            + viewModel.models.map(ListedModel.whisper)
    }

    private var engineLinkedModels: [EngineLinkedModel] {
        var byID: [String: EngineLinkedModel] = [:]
        var order: [String] = []
        for engine in viewModel.engines {
            guard let modelID = engine.wrappedModelID else { continue }
            if let existing = byID[modelID] {
                byID[modelID] = EngineLinkedModel(
                    id: existing.id,
                    title: existing.title,
                    subtitle: existing.subtitle,
                    engineIDs: existing.engineIDs + [engine.descriptor.id],
                    engineName: existing.engineName
                )
                continue
            }
            let listing = engineListing(engine)
            let size = listing.bytes.map {
                ByteCountFormatter.string(
                    fromByteCount: $0,
                    countStyle: .file
                )
            } ?? ""
            byID[modelID] = EngineLinkedModel(
                id: modelID,
                title: listing.title,
                subtitle:
                    "\(listing.language.displayName) · \(size) · \(listing.tier.displayName)",
                engineIDs: [engine.descriptor.id],
                engineName: engine.descriptor.displayName
            )
            order.append(modelID)
        }
        return order.compactMap { byID[$0] }
    }

    private func engineListing(_ engine: VerifiedEngine) -> (
        title: String,
        language: ModelLanguageCapability,
        tier: ModelPerformanceTier,
        bytes: Int64?
    ) {
        switch engine.descriptor.id {
        case EngineIdentifiers.parakeetTDTv2:
            return (
                "Parakeet TDT V2",
                .english,
                .highAccuracy,
                engine.fileSizeBytes
            )
        case EngineIdentifiers.parakeetTDTv3:
            return (
                "Parakeet TDT V3",
                .multilingual,
                .highAccuracy,
                engine.fileSizeBytes
            )
        case EngineIdentifiers.parakeetFlash:
            return (
                "Parakeet Flash",
                .english,
                .fast,
                engine.fileSizeBytes
            )
        case EngineIdentifiers.nemotronSpeechUltraFast,
             EngineIdentifiers.nemotronSpeechMultilingual:
            return (
                "Nemotron 3.5",
                .multilingual,
                .balanced,
                engine.fileSizeBytes
            )
        case EngineIdentifiers.cohereTranscribe:
            return (
                "Cohere Transcribe",
                .multilingual,
                .highAccuracy,
                VerifiedEngineCatalog.cohereBundleSizeBytes
            )
        default:
            return (
                engine.descriptor.displayName,
                .multilingual,
                .balanced,
                engine.fileSizeBytes
            )
        }
    }

    private func engineModelRow(_ linked: EngineLinkedModel) -> some View {
        let selected = linked.engineIDs.contains {
            viewModel.isSelectedEngine($0)
        }
        return HStack(spacing: ZenDesign.Spacing.sm) {
            ZenIconChip(
                systemImage: "cpu",
                size: ZenDesign.Layout.hitTarget,
                tint: selected
                    ? ZenDesign.Semantic.accent
                    : ZenDesign.Semantic.textSecondary
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(linked.title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(linked.subtitle)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }
            Spacer()
            if selected {
                ZenBadge(
                    text: "Active",
                    kind: .success,
                    systemImage: "checkmark"
                )
            } else {
                Button("Use") { refuse(linked) }
                    .buttonStyle(ZenSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, ZenDesign.Spacing.lg)
        .padding(.vertical, ZenDesign.Spacing.md)
    }

    private func chooseWhisper(_ model: VerifiedModel) {
        if let engineID = viewModel.activeEngineID,
           engineID != EngineIdentifiers.whisper {
            let name = viewModel.activeEngineDisplayName
            let modelID = VerifiedEngineCatalog.engine(id: engineID)?
                .wrappedModelID
            showMismatch(
                title: "Can't use this model",
                description: modelID.map {
                    "\(name) only loads \($0)."
                } ?? "\(name) does not load Whisper files."
            )
            return
        }
        viewModel.select(model)
    }

    private func refuse(_ linked: EngineLinkedModel) {
        let name = viewModel.activeEngineDisplayName
        if let engineID = viewModel.activeEngineID,
           let allowed = VerifiedEngineCatalog.engine(id: engineID)?
            .wrappedModelID {
            showMismatch(
                title: "Can't use this model",
                description: "\(name) only loads \(allowed)."
            )
        } else {
            showMismatch(
                title: "Can't use this model",
                description: "\(name) does not load \(linked.title)."
            )
        }
    }

    private func showMismatch(title: String, description: String) {
        mismatchAlert = ModelMismatchAlert(
            title: title,
            description: description
        )
    }
}

struct ModelMismatchToastOverlay: View {
    @Binding var alert: ModelMismatchAlert?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack {
            Spacer()
            if visible, let alert {
                ZenSystemAlert(
                    title: alert.title,
                    description: alert.description
                ) {
                    dismiss()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .transition(
                    .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .allowsHitTesting(visible)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: visible)
        .onChange(of: alert) { _, new in
            guard new != nil else {
                visible = false
                return
            }
            present()
        }
    }

    private func present() {
        hideTask?.cancel()
        visible = true
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        visible = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            alert = nil
        }
    }
}
