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

struct ModelsScreen: View {
    @ObservedObject var viewModel: ModelManagerViewModel
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

                Text("Whisper models")
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .padding(.top, ZenDesign.Spacing.sm)

                Text(
                    "These are verified Whisper variants. Choosing one also "
                        + "selects the Whisper engine."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)

                ZenPanel {
                    ForEach(
                        Array(viewModel.models.enumerated()),
                        id: \.element.id
                    ) { index, model in
                        if index > 0 { ZenPanelDivider() }
                        modelRow(model)
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
                    ZenBadge(text: "Active", kind: .success, systemImage: "checkmark")
                } else if downloading {
                    Button("Cancel") { viewModel.cancelDownload() }
                        .buttonStyle(ZenSecondaryButtonStyle())
                } else if installed {
                    Button("Use") { viewModel.select(model) }
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

        return ZenRow(
            icon: "waveform",
            iconTint: selected ? ZenDesign.Semantic.accent : nil,
            title: availability.engine.displayName,
            subtitle: availability.engine.privacyNote
        ) {
            if selected {
                ZenBadge(text: "Active", kind: .success)
            } else if availability.isAvailable {
                Button("Use") {
                    viewModel.selectEngine(availability.engine.id)
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            } else if let downloadable,
                      availability.engine.requiresDownload {
                Button(
                    viewModel.isEngineDownloading(downloadable)
                        ? "Downloading…" : "Download"
                ) {
                    viewModel.downloadEngine(downloadable)
                }
                .buttonStyle(ZenSecondaryButtonStyle())
                .disabled(viewModel.isEngineDownloading(downloadable))
            } else {
                ZenBadge(text: "Unavailable", kind: .neutral)
            }
        }
    }
}
