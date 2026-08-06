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

struct CloudAIScreen: View {
    @ObservedObject var viewModel: CloudAIViewModel

    var body: some View {
        ZenScreen(
            title: "Cloud AI Enhancement",
            subtitle:
                "Optionally send a finished transcript to a hosted model for "
                + "cleanup. Off by default — this is the only ZenVoice feature "
                + "that can send your text off this Mac."
        ) {
            enableSection
            if viewModel.configuration.isEnabled {
                providerSection
                keySection
                promptSection
                previewSection
            }
            messageSection
        }
    }

    private var enableSection: some View {
        ZenSection(title: "Off-device processing") {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    Text(
                        "When this is on, the transcript text and your prompt "
                        + "are sent to the provider you choose, using your own "
                        + "API key. Audio, the app you dictated into, your "
                        + "history, and your voice profile are never sent. "
                        + "ZenVoice runs no server of its own, so your text "
                        + "goes to that provider under their retention policy."
                    )
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Toggle(
                        "Enable Cloud AI Enhancement",
                        isOn: Binding(
                            get: { viewModel.configuration.isEnabled },
                            set: { viewModel.setEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Text(viewModel.providerDetail)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(
                            viewModel.configuration.isEnabled
                                ? ZenDesign.Semantic.textPrimary
                                : ZenDesign.Semantic.textTertiary
                        )
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var providerSection: some View {
        ZenSection(title: "Provider") {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    Picker(
                        "Provider",
                        selection: Binding(
                            get: { viewModel.configuration.provider },
                            set: { viewModel.setProvider($0) }
                        )
                    ) {
                        ForEach(CloudAIProvider.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }

                    TextField(
                        "Base URL",
                        text: Binding(
                            get: { viewModel.configuration.baseURL },
                            set: { viewModel.setBaseURL($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "Model",
                        text: Binding(
                            get: { viewModel.configuration.model },
                            set: { viewModel.setModel($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Text(
                        "The endpoint must use HTTPS. Choose Custom endpoint to "
                        + "point at a self-hosted or local model and keep the "
                        + "text on your own infrastructure."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var keySection: some View {
        ZenSection(
            title: "API key",
            caption: viewModel.hasStoredKey ? "Stored in Keychain" : "Not set"
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    HStack(spacing: ZenDesign.Spacing.xs) {
                        SecureField(
                            viewModel.hasStoredKey
                                ? "Replace stored key"
                                : "Paste your provider API key",
                            text: $viewModel.apiKeyDraft
                        )
                        .textFieldStyle(.roundedBorder)

                        Button("Save") { viewModel.saveKey() }
                            .buttonStyle(ZenPrimaryButtonStyle())
                            .disabled(viewModel.apiKeyDraft.isEmpty)

                        Button("Remove") { viewModel.deleteKey() }
                            .buttonStyle(ZenDestructiveButtonStyle())
                            .disabled(!viewModel.hasStoredKey)
                    }

                    Text(
                        "The key is stored in your macOS Keychain, never in "
                        + "preferences and never in the transcript database. "
                        + "Turning Cloud AI off deletes it."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var promptSection: some View {
        ZenSection(title: "Prompt") {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    TextEditor(
                        text: Binding(
                            get: { viewModel.configuration.prompt },
                            set: { viewModel.setPrompt($0) }
                        )
                    )
                    .font(ZenDesign.Typography.body)
                    .frame(minHeight: 90)
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: ZenDesign.Radius.small)
                            .fill(ZenDesign.Semantic.surfaceRaised)
                    }

                    HStack(spacing: ZenDesign.Spacing.xs) {
                        ForEach(
                            CloudAIPromptTemplate.builtIns,
                            id: \.name
                        ) { template in
                            Button(template.name) {
                                viewModel.applyTemplate(template)
                            }
                            .buttonStyle(ZenSecondaryButtonStyle())
                        }
                        Spacer()
                    }
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var previewSection: some View {
        ZenSection(
            title: "Preview",
            caption: "Nothing is applied until you accept it."
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    HStack(spacing: ZenDesign.Spacing.xs) {
                        Button("Enhance last transcript") {
                            viewModel.enhanceLastTranscript()
                        }
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .disabled(!viewModel.isReady || viewModel.isEnhancing)

                        if viewModel.isEnhancing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Spacer()
                    }

                    if let preview = viewModel.preview {
                        comparison(preview)
                        HStack(spacing: ZenDesign.Spacing.xs) {
                            Button("Accept") { viewModel.acceptPreview() }
                                .buttonStyle(ZenPrimaryButtonStyle())
                            Button("Discard") { viewModel.discardPreview() }
                                .buttonStyle(ZenSecondaryButtonStyle())
                            Spacer()
                        }
                    } else if !viewModel.isReady {
                        Text(
                            "Enable the feature and store a key to try it."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    }
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private func comparison(
        _ preview: CloudAIEnhancementResult
    ) -> some View {
        HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
            previewColumn("Original", text: preview.original)
            previewColumn("Enhanced", text: preview.enhanced)
        }
    }

    private func previewColumn(
        _ title: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            ScrollView {
                Text(text)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: ZenDesign.Radius.small)
                    .fill(ZenDesign.Semantic.surfaceRaised)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var messageSection: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.danger)
                .fixedSize(horizontal: false, vertical: true)
        } else if let status = viewModel.statusMessage {
            Text(status)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }
}
