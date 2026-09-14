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
import BuilderVoiceCore

struct ModelMismatchAlert: Equatable {
    var title: String
    var description: String
    var token = UUID()
}

struct ModelsScreen: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    @Binding var mismatchAlert: ModelMismatchAlert?

    var body: some View {
        ZenSection(title: "Speech engines") {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                Text(
                    "Choose the engine. Use downloads its file if needed."
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

                cloudSpeechKeySection
            }
        }
    }

    private var cloudSpeechKeySection: some View {
        ZenSection(
            title: "Cloud speech",
            caption: "Optional. Audio leaves this Mac and is billed to your key."
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    Text(
                        "After you stop, BuilderHelm Voice uploads the clip once. "
                            + "Local engines never send audio."
                    )
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    cloudKeyRow(
                        title: "OpenAI",
                        placeholder: "Paste your OpenAI API key",
                        hasKey: viewModel.hasOpenAISpeechKey,
                        draft: $viewModel.openAISpeechKeyDraft,
                        save: viewModel.saveOpenAISpeechKey,
                        delete: viewModel.deleteOpenAISpeechKey
                    )
                    ZenPanelDivider()
                    cloudKeyRow(
                        title: "Gemini",
                        placeholder: "Paste your Google AI Studio key",
                        hasKey: viewModel.hasGeminiSpeechKey,
                        draft: $viewModel.geminiSpeechKeyDraft,
                        save: viewModel.saveGeminiSpeechKey,
                        delete: viewModel.deleteGeminiSpeechKey
                    )
                    ZenPanelDivider()
                    cloudKeyRow(
                        title: "Scribe v2",
                        placeholder: "Paste your ElevenLabs API key",
                        hasKey: viewModel.hasElevenLabsSpeechKey,
                        draft: $viewModel.elevenLabsSpeechKeyDraft,
                        save: viewModel.saveElevenLabsSpeechKey,
                        delete: viewModel.deleteElevenLabsSpeechKey
                    )
                    ZenPanelDivider()
                    cloudKeyRow(
                        title: "Grok",
                        placeholder: "Paste your xAI API key",
                        hasKey: viewModel.hasGrokSpeechKey,
                        draft: $viewModel.grokSpeechKeyDraft,
                        save: viewModel.saveGrokSpeechKey,
                        delete: viewModel.deleteGrokSpeechKey
                    )
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private func cloudKeyRow(
        title: String,
        placeholder: String,
        hasKey: Bool,
        draft: Binding<String>,
        save: @escaping () -> Void,
        delete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
            Text(title)
                .font(ZenDesign.Typography.bodyStrong)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            if hasKey {
                HStack(spacing: ZenDesign.Spacing.xs) {
                    Text("Key stored in Keychain.")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    Spacer(minLength: 0)
                    Button("Remove", action: delete)
                        .buttonStyle(ZenDestructiveButtonStyle())
                }
            } else {
                HStack(spacing: ZenDesign.Spacing.xs) {
                    SecureField(placeholder, text: draft)
                        .textFieldStyle(.roundedBorder)
                    Button("Save", action: save)
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .disabled(
                            draft.wrappedValue
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                        )
                }
            }
        }
    }

    private func engineRow(_ availability: EngineAvailability) -> some View {
        let selected = viewModel.isSelectedEngine(availability.engine.id)
        let downloadable = viewModel.engines.first {
            $0.descriptor.id == availability.engine.id
        }
        let downloadingEngine = downloadable.map(viewModel.isEngineDownloading) ?? false

        return VStack(alignment: .leading, spacing: ZenDesign.Spacing.xxs) {
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
                } else if availability.reason == .requiresAPIKey {
                    ZenBadge(text: "Needs key", kind: .warn)
                } else if let downloadable,
                          availability.engine.requiresDownload {
                    if downloadingEngine {
                        Button("Cancel") { viewModel.cancelDownload() }
                            .buttonStyle(ZenSecondaryButtonStyle())
                    } else {
                        Button("Use") {
                            viewModel.selectEngine(availability.engine.id)
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
                .padding(
                    .leading,
                    ZenDesign.Spacing.md
                        + ZenDesign.Layout.rowIcon
                        + ZenDesign.Spacing.sm
                )
            }
        }
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
