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

struct LanguagesScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""
    @State private var showsAllLanguages = false

    private var visibleLanguages: [SupportedLanguage] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return LanguageCatalog.languages }
        return LanguageCatalog.languages.filter {
            $0.displayName.lowercased().contains(query)
                || $0.nativeName.lowercased().contains(query)
                || $0.code.lowercased().contains(query)
        }
    }

    private var isAutomatic: Bool {
        viewModel.languageProfile.inputLanguageCode
            == LanguageProfile.automaticCode
    }

    var body: some View {
        ZenSection(title: "Languages") {
            ZenPanel {
                if let error = viewModel.languageError {
                    ZenBanner(
                        kind: .danger,
                        icon: "exclamationmark.triangle",
                        text: error
                    )
                    .padding(ZenDesign.Spacing.md)
                }

                ZenRow(
                    icon: "globe",
                    title: "Primary language",
                    subtitle: "The language ZenVoice expects when dictation begins"
                ) {
                    ZenMenuPicker(
                        label: "Primary language",
                        options:
                            [LanguageProfile.automaticCode]
                            + LanguageCatalog.languages.map(\.code),
                        selection: Binding(
                            get: {
                                viewModel.languageProfile.inputLanguageCode
                            },
                            set: viewModel.setInputLanguage
                        ),
                        minWidth: 230,
                        title: languageTitle
                    )
                }

                ZenPanelDivider()

                ZenRow(
                    icon: "waveform.badge.magnifyingglass",
                    title: "Automatic language detection",
                    subtitle: "Detect the spoken language for each dictation"
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { isAutomatic },
                            set: { enabled in
                                if enabled {
                                    viewModel.useAutomaticProfile()
                                } else {
                                    viewModel.useEnglishProfile()
                                }
                            }
                        ),
                        label: "Automatic language detection"
                    )
                }

                ZenPanelDivider()

                ZenRow(
                    icon: "character.cursor.ibeam",
                    title: "Output mode",
                    subtitle: "Choose the script used for the final transcript"
                ) {
                    ZenMenuPicker(
                        label: "Output mode",
                        options: TranscriptionOutputMode.allCases,
                        selection: Binding(
                            get: { viewModel.languageProfile.outputMode },
                            set: viewModel.setOutputMode
                        ),
                        minWidth: 230,
                        title: \.displayName
                    )
                }

                ZenPanelDivider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsAllLanguages.toggle()
                    }
                } label: {
                    HStack(spacing: ZenDesign.Spacing.sm) {
                        Text("Browse all \(LanguageCatalog.languages.count) languages")
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(ZenDesign.Typography.badge)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                            .rotationEffect(.degrees(showsAllLanguages ? 180 : 0))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ZenDesign.Spacing.md)
                    .padding(.vertical, ZenDesign.Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ZenPressButtonStyle())

                if showsAllLanguages {
                    VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                        ZenSearchField(
                            placeholder: "Search languages…",
                            text: $searchText
                        )
                        ForEach(visibleLanguages) { language in
                            languageButton(language)
                        }
                    }
                    .padding(.horizontal, ZenDesign.Spacing.md)
                    .padding(.bottom, ZenDesign.Spacing.md)
                }
            }

            if viewModel.languageProfile.requiresMultilingualModel {
                ZenBanner(
                    kind: .warn,
                    icon: "cpu",
                    text: "This language requires a compatible multilingual model. Choose one below."
                )
            }
        }
    }

    private func languageTitle(_ code: String) -> String {
        guard code != LanguageProfile.automaticCode else {
            return "Automatic"
        }
        return LanguageCatalog.language(code: code)?.displayName ?? code
    }

    private func languageButton(_ language: SupportedLanguage) -> some View {
        let selected = viewModel.languageProfile.inputLanguageCode
            == language.code
        return Button {
            viewModel.setInputLanguage(language.code)
        } label: {
            HStack(spacing: ZenDesign.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.displayName)
                        .font(ZenDesign.Typography.bodyStrong)
                    Text(language.nativeName)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                Spacer()
                Text(language.code)
                    .font(ZenDesign.Typography.monoSmall)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ZenDesign.Semantic.accent)
                }
            }
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .padding(.horizontal, ZenDesign.Spacing.sm)
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    selected
                        ? ZenDesign.Semantic.accentMuted
                        : ZenDesign.Semantic.surfaceRaised
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
