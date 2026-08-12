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

struct VoiceProfileScreen: View {
    @ObservedObject var viewModel: VoiceProfileViewModel
    @State private var heardPhrase = ""
    @State private var replacementPhrase = ""
    @State private var correctionScope: CorrectionLanguageScope =
        LanguagePreferences.load() == .hinglish ? .hinglish : .all
    @State private var confirmsDeleteAllRules = false

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            if let error = viewModel.errorMessage {
                ZenBanner(
                    kind: .danger,
                    icon: "exclamationmark.triangle",
                    text: error
                )
            }

            summary
            learningSection
            correctionsSection

            HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
                wordsSection
                phrasesSection
            }

            ZenBanner(
                kind: .info,
                icon: "person.crop.circle.badge.xmark",
                text:
                    "This is a language-usage profile, not a biometric voiceprint. No background microphone listening; ZenVoice does not identify or authenticate people."
            )
        }
        .onAppear(perform: viewModel.refresh)
        .alert(
            "Delete all correction rules?",
            isPresented: $confirmsDeleteAllRules
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Rules", role: .destructive) {
                viewModel.deleteAllRules()
            }
        } message: {
            Text(
                "This permanently removes every encrypted personal replacement rule. Transcript history is not deleted."
            )
        }
    }

    private var summary: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            ZenStatTile(
                value:
                    viewModel.snapshot.analyzedDictationCount.formatted(),
                label: "dictations analyzed"
            )
            ZenStatTile(
                value: activeHourLabel,
                label: "most active hour"
            )
            ZenStatTile(
                value:
                    viewModel.snapshot.correctionRules.count.formatted(),
                label: "correction rules"
            )
        }
    }

    // MARK: learning controls

    private var learningSection: some View {
        ZenSection(title: "Learning controls") {
            ZenPanel {
                ZenRow(
                    icon: "textformat",
                    title: "Analyze saved history for patterns",
                    subtitle:
                        "Show frequent words, recurring phrases, and your most active hour. No new copy is stored."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.analyzesHistory },
                            set: viewModel.setAnalyzesHistory
                        ),
                        label: "Analyze saved history"
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "pencil",
                    title: "Apply personal correction rules",
                    subtitle:
                        "Pause every encrypted replacement rule without deleting it."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.appliesCorrectionRules },
                            set: viewModel.setAppliesCorrectionRules
                        ),
                        label: "Apply correction rules"
                    )
                }
            }
        }
    }

    // MARK: corrections

    private var correctionsSection: some View {
        ZenSection(
            title: "Correction rules",
            caption: "Encrypted · independent of History"
        ) {
            ZenPanel {
                if viewModel.snapshot.correctionRules.isEmpty {
                    ZenRow(
                        icon: "character.cursor.ibeam",
                        title: "No personal corrections yet",
                        subtitle:
                            "Add only terms you want ZenVoice to replace automatically — whole words, applied locally."
                    )
                } else {
                    ForEach(
                        viewModel.snapshot.correctionRules
                    ) { rule in
                        HStack(spacing: ZenDesign.Spacing.xs) {
                            Text("“\(rule.source)”")
                                .font(ZenDesign.Typography.body)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            Image(systemName: "arrow.right")
                                .font(ZenDesign.Typography.badge)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                            Text(rule.replacement)
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            ZenBadge(
                                text: rule.languageScope.displayName,
                                kind: .neutral
                            )
                            Spacer()
                            Text(
                                "used \(rule.usageCount)×"
                            )
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                            ZenIconButton(
                                systemImage: "trash",
                                label: "Delete rule \(rule.source)",
                                isDanger: true
                            ) {
                                viewModel.deleteRule(rule)
                            }
                        }
                        .padding(.horizontal, ZenDesign.Spacing.md)
                        .frame(minHeight: 44)
                        if rule.id
                            != viewModel.snapshot.correctionRules.last?.id {
                            ZenPanelDivider()
                        }
                    }
                }

                ZenPanelDivider()

                // Entry controls and destructive action, on one line while
                // they fit and two when they do not.
                //
                // Two 150pt fields, a button, a 125pt picker and a second
                // button need about 700pt. The narrowest window leaves 652pt
                // here, so as a single `HStack` this row forced its card wider
                // than the content column and spilled past the edge.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: ZenDesign.Spacing.xs) {
                        correctionEntryFields
                        addRuleButton
                        languageScopePicker
                        Spacer(minLength: ZenDesign.Spacing.xs)
                        deleteAllRulesButton
                    }
                    VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                        HStack(
                            alignment: .bottom,
                            spacing: ZenDesign.Spacing.xs
                        ) {
                            correctionEntryFields
                            addRuleButton
                            Spacer(minLength: 0)
                        }
                        HStack(alignment: .bottom, spacing: ZenDesign.Spacing.xs) {
                            languageScopePicker
                            Spacer(minLength: ZenDesign.Spacing.xs)
                            deleteAllRulesButton
                        }
                    }
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var correctionEntryFields: some View {
        HStack(alignment: .bottom, spacing: ZenDesign.Spacing.xs) {
            VStack(alignment: .leading, spacing: 4) {
                Text("When I say")
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                correctionField(
                    placeholder: "zen pens",
                    text: $heardPhrase
                )
            }
            Image(systemName: "arrow.right")
                .font(ZenDesign.Typography.badge)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .padding(.bottom, 9)
            VStack(alignment: .leading, spacing: 4) {
                Text("Write")
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                correctionField(
                    placeholder: "ZenPense",
                    text: $replacementPhrase
                )
            }
        }
    }

    private var addRuleButton: some View {
        Button("Add rule") {
            Task { @MainActor in
                if await viewModel.addRule(
                    source: heardPhrase,
                    replacement: replacementPhrase,
                    languageScope: correctionScope
                ) {
                    heardPhrase = ""
                    replacementPhrase = ""
                }
            }
        }
        .buttonStyle(ZenSecondaryButtonStyle())
        .disabled(
            heardPhrase.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
                || replacementPhrase.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
        )
        .alignmentGuide(.bottom) { dimensions in
            dimensions[.bottom]
                - (dimensions.height - ZenDesign.Layout.control) / 2
        }
    }

    private var languageScopePicker: some View {
        Menu {
            ForEach(CorrectionLanguageScope.allCases) { scope in
                Button {
                    correctionScope = scope
                } label: {
                    if correctionScope == scope {
                        Label(
                            scope.displayName,
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(scope.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(correctionScope.displayName)
                    .lineLimit(1)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(width: 125, height: ZenDesign.Layout.control)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(ZenDesign.Semantic.surface)
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .strokeBorder(ZenDesign.Semantic.borderStrong)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 125, height: ZenDesign.Layout.control)
        .accessibilityLabel("Language scope")
    }

    private var deleteAllRulesButton: some View {
        Button("Delete All") {
            confirmsDeleteAllRules = true
        }
        .buttonStyle(ZenDestructiveButtonStyle())
        .disabled(viewModel.snapshot.correctionRules.isEmpty)
        .alignmentGuide(.bottom) { dimensions in
            dimensions[.bottom]
                - (dimensions.height - ZenDesign.Layout.control) / 2
        }
    }

    private func correctionField(
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(ZenDesign.Typography.body)
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .padding(.horizontal, 10)
            .frame(width: 150, height: ZenDesign.Layout.control)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(ZenDesign.Semantic.surface)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .strokeBorder(ZenDesign.Semantic.borderStrong)
                }
            }
    }

    // MARK: patterns

    private var wordsSection: some View {
        ZenSection(title: "Most-used words") {
            ZenPanel {
                Group {
                    if viewModel.snapshot.topWords.isEmpty {
                        emptyProfileText
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 104), spacing: ZenDesign.Spacing.xs)
                            ],
                            alignment: .leading,
                            spacing: ZenDesign.Spacing.xs
                        ) {
                            ForEach(
                                viewModel.snapshot.topWords
                            ) { item in
                                HStack(spacing: 6) {
                                    Text(item.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.9)
                                    Text("\(item.count)")
                                        .font(
                                            ZenDesign.Typography.caption
                                        )
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textTertiary
                                        )
                                }
                                .font(ZenDesign.Typography.captionStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background {
                                    Capsule().fill(
                                        ZenDesign.Semantic.surfaceRaised
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(ZenDesign.Spacing.md)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 168,
                    alignment: .topLeading
                )
            }
        }
    }

    private var phrasesSection: some View {
        ZenSection(title: "Recurring phrases") {
            ZenPanel {
                Group {
                    if viewModel.snapshot.catchPhrases.isEmpty {
                        emptyProfileText
                    } else {
                        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                            ForEach(
                                viewModel.snapshot.catchPhrases
                            ) { item in
                                HStack(spacing: ZenDesign.Spacing.xs) {
                                    Image(systemName: "quote.opening")
                                        .font(ZenDesign.Typography.badge)
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textTertiary
                                        )
                                    Text(item.text)
                                        .font(
                                            ZenDesign.Typography.bodyStrong
                                        )
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textPrimary
                                        )
                                        .lineLimit(1)
                                    Spacer()
                                    Text("×\(item.count)")
                                        .font(ZenDesign.Typography.caption)
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textTertiary
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(ZenDesign.Spacing.md)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 168,
                    alignment: .topLeading
                )
            }
        }
    }

    private var emptyProfileText: some View {
        ZenRow(
            icon: "chart.bar.xaxis",
            title:
                viewModel.analyzesHistory
                    ? "More saved dictations are needed"
                    : "Pattern analysis is paused",
            subtitle:
                viewModel.analyzesHistory
                    ? "Keep dictating and ZenVoice will surface frequent words and phrases."
                    : "Turn on history analysis to see your most-used words and phrases."
        )
    }

    private var activeHourLabel: String {
        guard let hour = viewModel.snapshot.mostActiveHour,
              let date = Calendar.current.date(
                from: DateComponents(hour: hour)
              ) else {
            return "—"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
