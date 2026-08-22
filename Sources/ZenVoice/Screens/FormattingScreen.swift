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

struct FormattingScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var cloudAIViewModel: CloudAIViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel

    @AppStorage(TranscriptFormattingPreferences.preferenceKey)
    private var modeRawValue = TranscriptFormattingMode.clean.rawValue
    @State private var heardPhrase = ""
    @State private var replacementPhrase = ""
    @State private var correctionScope = CorrectionLanguageScope.all

    private var mode: TranscriptFormattingMode {
        TranscriptFormattingMode(rawValue: modeRawValue) ?? .clean
    }

    var body: some View {
        formattingContent
            .onAppear(perform: voiceProfileViewModel.refresh)
    }

    @ViewBuilder
    private var formattingContent: some View {
        textFormatting
        textReplacement

        if mode == .cloud {
            if !cloudAIViewModel.isReady {
                ZenBanner(
                    kind: .warn,
                    icon: "exclamationmark.triangle",
                    text: "Cloud formatting needs a provider and key below."
                )
            }
            CloudAIConfigurationView(viewModel: cloudAIViewModel)
        } else {
            ZenBanner(
                kind: .info,
                icon: "hand.raised",
                text:
                    "Replacements stay on this Mac. Cloud mode sends finished text only."
            )
        }
    }

    private var textFormatting: some View {
        ZenSection(title: "Text Formatting") {
            ZenPanel {
                ZenRow(
                    icon: "wand.and.stars",
                    title: "Formatting level",
                    subtitle: mode.detail
                ) {
                    ZenTabStrip(
                        items: TranscriptFormattingMode.allCases.map {
                            .init(tab: $0, title: $0.displayName)
                        },
                        selection: Binding(
                            get: { mode },
                            set: { modeRawValue = $0.rawValue }
                        )
                    )
                }

                ZenPanelDivider()

                ZenRow(
                    icon: "captions.bubble",
                    title: "Live transcript",
                    subtitle: "Show words while you speak"
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.livePreviewEnabled },
                            set: viewModel.setLivePreviewEnabled
                        ),
                        label: "Live transcript"
                    )
                }

                ZenPanelDivider()

                ZenRow(
                    icon: "pause.circle",
                    title: "Commit on pause",
                    subtitle: "Insert stable phrases during longer dictations"
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.commitOnPauseEnabled },
                            set: viewModel.setCommitOnPauseEnabled
                        ),
                        label: "Commit on pause"
                    )
                }

                ZenPanelDivider()

                ZenRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Apply text replacements",
                    subtitle: "Use your saved phrase corrections automatically"
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { voiceProfileViewModel.appliesCorrectionRules },
                            set: voiceProfileViewModel.setAppliesCorrectionRules
                        ),
                        label: "Apply text replacements"
                    )
                }
            }
        }
    }

    private var textReplacement: some View {
        ZenSection(title: "Text Replacement") {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: ZenDesign.Spacing.sm) {
                            replacementField("Heard phrase", text: $heardPhrase)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                            replacementField("Replacement", text: $replacementPhrase)
                            scopePicker
                            addReplacementButton
                        }
                        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                            replacementField("Heard phrase", text: $heardPhrase)
                            replacementField("Replacement", text: $replacementPhrase)
                            HStack {
                                scopePicker
                                Spacer()
                                addReplacementButton
                            }
                        }
                    }

                    if let error = voiceProfileViewModel.errorMessage {
                        Text(error)
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.danger)
                    }

                    if voiceProfileViewModel.snapshot.correctionRules.isEmpty {
                        Text("No replacements yet. Add the phrases ZenVoice should rewrite every time.")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                            .padding(.vertical, ZenDesign.Spacing.sm)
                    } else {
                        ZenPanelDivider()
                        ForEach(voiceProfileViewModel.snapshot.correctionRules) { rule in
                            HStack(spacing: ZenDesign.Spacing.sm) {
                                ZenIconChip(
                                    systemImage: "wand.and.stars",
                                    size: 30,
                                    tint: ZenDesign.Semantic.textSecondary
                                )
                                Text("\"\(rule.source)\"")
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                                Text("\"\(rule.replacement)\"")
                                Spacer()
                                ZenBadge(
                                    text: rule.languageScope.displayName,
                                    kind: .neutral
                                )
                                ZenIconButton(
                                    systemImage: "trash",
                                    label: "Delete replacement",
                                    isDanger: true
                                ) {
                                    voiceProfileViewModel.deleteRule(rule)
                                }
                            }
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .padding(.vertical, ZenDesign.Spacing.xs)
                        }
                    }
                }
                .padding(ZenDesign.Spacing.lg)
            }
        }
    }

    private func replacementField(
        _ placeholder: String,
        text: Binding<String>
    ) -> some View {
        ZenTextInput(
            placeholder: placeholder,
            text: text,
            icon: placeholder == "Heard phrase"
                ? "waveform"
                : "text.cursor",
            minWidth: 180
        )
    }

    private var scopePicker: some View {
        ZenMenuPicker(
            label: "Replacement language",
            options: CorrectionLanguageScope.allCases,
            selection: $correctionScope,
            minWidth: 150,
            title: \.displayName
        )
    }

    private var addReplacementButton: some View {
        Button("Add Replacement") {
            Task { @MainActor in
                let saved = await voiceProfileViewModel.addRule(
                    source: heardPhrase,
                    replacement: replacementPhrase,
                    languageScope: correctionScope
                )
                if saved {
                    heardPhrase = ""
                    replacementPhrase = ""
                }
            }
        }
        .buttonStyle(
            ZenPrimaryButtonStyle(
                minWidth: 150,
                height: ZenDesign.Layout.hitTarget
            )
        )
        .disabled(
            heardPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || replacementPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }
}

extension TranscriptFormattingMode: Identifiable {
    public var id: String { rawValue }
}
