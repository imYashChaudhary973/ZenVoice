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

/// Cloud AI controls without a screen wrapper.
///
/// `FormattingScreen` inlines this directly so the provider, key, prompt, and
/// preview live under the single Formatting title instead of nesting a second
/// `ZenScreen` scaffold.
struct CloudAIConfigurationView: View {
    @ObservedObject var viewModel: CloudAIViewModel
    @State private var isReplacingKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            enableSection
            if viewModel.configuration.isEnabled {
                providerSection
                keySection
                applySection
                promptSection
                previewSection
            }
            messageSection
        }
    }

    /// Whether a dictation gets enhanced silently or stops to be reviewed.
    ///
    /// Sending the text off-device is the decision that needs consent, and it
    /// has already been made by the time this section renders. This one is
    /// about trust in the output, which is the user's call to make once.
    private var applySection: some View {
        ZenSection(
            title: "Applying enhancements",
            caption: viewModel.configuration.autoApply
                ? "No prompt after dictation"
                : "Review each one"
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    Toggle(
                        "Apply enhanced text automatically",
                        isOn: Binding(
                            get: { viewModel.configuration.autoApply },
                            set: { viewModel.setAutoApply($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Text(
                        viewModel.configuration.autoApply
                            ? "Enhanced text replaces your local transcript as "
                                + "soon as it arrives. Nothing interrupts you "
                                + "after you finish speaking."
                            : "After each dictation, ZenVoice shows the local "
                                + "and enhanced text side by side and waits "
                                + "for you to accept or discard."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var enableSection: some View {
        ZenSection(title: "Off-device processing") {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    Text(
                        "Sends finished text and this prompt to your provider. Audio stays on this Mac."
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
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: ZenDesign.Spacing.sm
                    ) {
                        Text("Provider")
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .frame(width: 64, alignment: .leading)

                        providerPicker
                    }

                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: ZenDesign.Spacing.sm
                    ) {
                        Text("Model")
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .frame(width: 64, alignment: .leading)

                        if viewModel.configuration.provider.knownModels.isEmpty {
                            ZenTextInput(
                                placeholder: "Model",
                                text: Binding(
                                    get: { viewModel.configuration.model },
                                    set: { viewModel.setModel($0) }
                                ),
                                icon: "cpu",
                                minWidth: 220
                            )
                        } else {
                            modelPicker
                        }
                    }

                    ZenTextInput(
                        placeholder: "Base URL",
                        text: Binding(
                            get: { viewModel.configuration.baseURL },
                            set: { viewModel.setBaseURL($0) }
                        ),
                        icon: "link",
                        minWidth: 280
                    )
                    .padding(.top, ZenDesign.Spacing.xs)

                    Text(
                        viewModel.configuration.provider == .ollama
                            ? "Local Ollama uses HTTP on this Mac. Other providers must use HTTPS."
                            : "The endpoint must use HTTPS, except a local Ollama address on this Mac."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ZenDesign.Spacing.xs)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var providerPicker: some View {
        ZenMenuPicker(
            label: "Provider",
            options: CloudAIProvider.allCases,
            selection: Binding(
                get: { viewModel.configuration.provider },
                set: { viewModel.setProvider($0) }
            ),
            minWidth: 220,
            title: \.displayName
        )
    }

    private var modelPicker: some View {
        ZenMenuPicker(
            label: "Model",
            options: modelOptions,
            selection: Binding(
                get: { viewModel.configuration.model },
                set: { viewModel.setModel($0) }
            ),
            minWidth: 260,
            title: { $0 }
        )
    }

    private var keySection: some View {
        ZenSection(
            title: "API key",
            caption: viewModel.hasStoredKey ? "Stored in Keychain" : "Not set"
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    if viewModel.hasStoredKey && !isReplacingKey {
                        HStack(spacing: ZenDesign.Spacing.xs) {
                            Text("A provider key is stored on this Mac.")
                                .font(ZenDesign.Typography.body)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            Spacer(minLength: 0)
                            Button("Replace stored key") {
                                isReplacingKey = true
                            }
                            .buttonStyle(ZenSecondaryButtonStyle())
                            Button("Remove") {
                                viewModel.deleteKey()
                            }
                            .buttonStyle(ZenDestructiveButtonStyle())
                        }
                    } else {
                        HStack(spacing: ZenDesign.Spacing.xs) {
                            SecureField(
                                viewModel.hasStoredKey
                                    ? "Replace stored key"
                                    : "Paste your provider API key",
                                text: $viewModel.apiKeyDraft
                            )
                            .textFieldStyle(.roundedBorder)

                            Button("Save") {
                                viewModel.saveKey()
                                isReplacingKey = false
                            }
                            .buttonStyle(ZenPrimaryButtonStyle())
                            .disabled(viewModel.apiKeyDraft.isEmpty)

                            if viewModel.hasStoredKey {
                                Button("Cancel") {
                                    viewModel.apiKeyDraft = ""
                                    isReplacingKey = false
                                }
                                .buttonStyle(ZenSecondaryButtonStyle())
                            } else {
                                Button("Remove") {
                                    viewModel.deleteKey()
                                }
                                .buttonStyle(ZenDestructiveButtonStyle())
                                .disabled(!viewModel.hasStoredKey)
                            }
                        }
                    }

                    Text(
                        viewModel.configuration.provider.requiresAPIKey
                            ? "Kept in the Keychain. Turning Cloud AI off stops sending text but keeps the key."
                            : "Local Ollama does not need a key. Leave this blank."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    /// The provider's known models, plus whatever is currently stored.
    ///
    /// A `Picker` shows a blank selection when nothing carries the selected
    /// tag. Replacing the free-text model field with a fixed list therefore
    /// left anyone whose saved model predates that list — `gpt-4-turbo`, an
    /// older Groq id — looking at an empty control while the unlisted value
    /// was still what got sent. Keeping the stored value in the list means the
    /// UI always shows what will actually be used.
    private var modelOptions: [String] {
        let known = viewModel.configuration.provider.knownModels
        let current = viewModel.configuration.model
        guard !current.isEmpty, !known.contains(current) else {
            return known
        }
        return known + [current]
    }

    private var promptSection: some View {
        ZenSection(title: "Prompt") {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    ZenTextArea(
                        label: "Prompt",
                        text: Binding(
                            get: { viewModel.configuration.prompt },
                            set: { viewModel.setPrompt($0) }
                        ),
                        hint: "Sent with each enhancement.",
                        maxLength: 2_000
                    )

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
                .font(ZenDesign.Typography.eyebrow)
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
            .padding(ZenDesign.Spacing.xs)
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
