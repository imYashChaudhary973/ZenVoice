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
import ZenVoiceStorage

struct VoiceProfileScreen: View {
    @ObservedObject var viewModel: VoiceProfileViewModel
    @State private var heardPhrase = ""
    @State private var replacementPhrase = ""
    @State private var correctionScope = CorrectionLanguageScope.all


    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            personalVocabulary
            learnedAutomatically
        }
        .onAppear(perform: viewModel.refresh)

    }

    private var personalVocabulary: some View {
        ZenPanel(padding: ZenDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Personal Vocabulary")
                            .font(ZenDesign.Typography.sectionTitle)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text("Names, jargon, and phrases ZenVoice should always recognize.")
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }
                    Spacer()
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.appliesCorrectionRules },
                            set: viewModel.setAppliesCorrectionRules
                        ),
                        label: "Use personal vocabulary"
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ZenDesign.Spacing.sm) {
                        vocabularyField("ZenVoice heard…", text: $heardPhrase)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        vocabularyField("It should write…", text: $replacementPhrase)
                        scopePicker
                        addButton
                    }
                    VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                        vocabularyField("ZenVoice heard…", text: $heardPhrase)
                        vocabularyField("It should write…", text: $replacementPhrase)
                        HStack {
                            scopePicker
                            Spacer()
                            addButton
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.danger)
                }

                if viewModel.snapshot.correctionRules.isEmpty {
                    Text("No vocabulary entries yet.")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .padding(.vertical, ZenDesign.Spacing.sm)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160))],
                        alignment: .leading,
                        spacing: ZenDesign.Spacing.sm
                    ) {
                        ForEach(viewModel.snapshot.correctionRules) { rule in
                            HStack(spacing: ZenDesign.Spacing.xs) {
                                Text(rule.replacement)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Button {
                                    viewModel.deleteRule(rule)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete \(rule.replacement)")
                            }
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .padding(.horizontal, ZenDesign.Spacing.sm)
                            .frame(minHeight: 40)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: ZenDesign.Radius.small,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.surfaceRaised)
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: ZenDesign.Radius.small,
                                        style: .continuous
                                    )
                                    .strokeBorder(
                                        ZenDesign.Semantic.borderStrong
                                    )
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        ZenHoldToDeleteButton(label: "Hold to delete") {
                            viewModel.deleteAllRules()
                        }
                        .disabled(viewModel.snapshot.correctionRules.isEmpty)
                    }
                }
            }
        }
    }

    private var learnedAutomatically: some View {
        ZenPanel(padding: ZenDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Learned Automatically")
                            .font(ZenDesign.Typography.sectionTitle)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text("Picked up from your encrypted local history on this Mac only.")
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }
                    Spacer()
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.analyzesHistory },
                            set: viewModel.setAnalyzesHistory
                        ),
                        label: "Learn automatically"
                    )
                }

                if !viewModel.analyzesHistory {
                    Text("Automatic learning is paused.")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                } else if viewModel.snapshot.topWords.isEmpty
                    && viewModel.snapshot.catchPhrases.isEmpty {
                    Text("Frequently used words and phrases will appear here after more dictations.")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.snapshot.topWords.prefix(6))) { word in
                            learnedRow(
                                title: word.text,
                                detail: "Used \(word.count) times"
                            )
                            ZenPanelDivider()
                        }
                        ForEach(Array(viewModel.snapshot.catchPhrases.prefix(4))) { phrase in
                            learnedRow(
                                title: phrase.text,
                                detail: "Used \(phrase.count) times"
                            )
                            if phrase.id != viewModel.snapshot.catchPhrases.prefix(4).last?.id {
                                ZenPanelDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func learnedRow(title: String, detail: String) -> some View {
        ZenRow(
            icon: "wand.and.stars",
            title: title,
            subtitle: detail
        )
    }

    private func vocabularyField(
        _ placeholder: String,
        text: Binding<String>
    ) -> some View {
        ZenTextInput(
            placeholder: placeholder,
            text: text,
            icon: placeholder.contains("heard")
                ? "waveform"
                : "text.cursor",
            minWidth: 190
        )
    }

    private var scopePicker: some View {
        ZenMenuPicker(
            label: "Vocabulary language",
            options: CorrectionLanguageScope.allCases,
            selection: $correctionScope,
            minWidth: 150,
            title: \.displayName
        )
    }

    private var addButton: some View {
        Button("Add") {
            Task { @MainActor in
                let saved = await viewModel.addRule(
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
        .buttonStyle(ZenPrimaryButtonStyle(minWidth: 84))
        .disabled(
            heardPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || replacementPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }
}
