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
import ZenVoiceRuntime
import ZenVoiceStorage

struct FormattingScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel

    @AppStorage(TranscriptFormattingPreferences.preferenceKey)
    private var modeRawValue = TranscriptFormattingMode.clean.rawValue
    @AppStorage(TranscriptTonePreferences.preferenceKey)
    private var toneRawValue = TranscriptTone.auto.rawValue
    @State private var heardPhrase = ""
    @State private var replacementPhrase = ""
    @State private var correctionScope = CorrectionLanguageScope.all

    private var mode: TranscriptFormattingMode {
        TranscriptFormattingMode(rawValue: modeRawValue) ?? .clean
    }

    @State private var zenPolishEnabled = ZenPolishPreferences.load()

    private var isZenPolishInstalled: Bool {
        let model = ZenPolishLanguageModel(
            modelsDirectory: try? VerifiedModelCatalog.modelsDirectory()
        )
        return model.availability == .available
    }

    private var zenPolishSubtitle: String {
        if !isZenPolishInstalled {
            return "Download ZenPolish from the Models screen to use it."
        }
        return zenPolishEnabled
            ? "Polished uses the ZenPolish on-device model."
            : "Polished uses Apple's on-device model."
    }

    var body: some View {
        formattingContent
            .onAppear(perform: voiceProfileViewModel.refresh)
    }

    @ViewBuilder
    private var formattingContent: some View {
        textFormatting
        textReplacement

        ZenBanner(
            kind: .info,
            icon: "hand.raised",
            text:
                "Replacements stay on this Mac."
        )
    }

    private var textFormatting: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Layout.contentGap) {
            FormattingLevelPicker(
                mode: Binding(
                    get: { mode },
                    set: { modeRawValue = $0.rawValue }
                )
            )

            ZenSection(title: "Text Formatting") {
                ZenPanel {
                ZenRow(
                    icon: "brain",
                    title: "Formatting model",
                    subtitle: zenPolishSubtitle
                ) {
                    ZenMenuPicker(
                        label: "Formatting model",
                        options: isZenPolishInstalled
                            ? FormattingModelChoice.allCases
                            : [FormattingModelChoice.none],
                        selection: Binding(
                            get: {
                                zenPolishEnabled
                                    ? .zenPolishV2
                                    : .none
                            },
                            set: {
                                ZenPolishPreferences.save($0 == .zenPolishV2)
                                zenPolishEnabled = $0 == .zenPolishV2
                            }
                        ),
                        minWidth: 170,
                        title: { $0.displayName }
                    )
                }

                ZenPanelDivider()

                ZenRow(
                    icon: "theatermasks",
                    title: "Tone",
                    subtitle: "Used when Polished rewrites with Apple Intelligence"
                ) {
                    ZenMenuPicker(
                        label: "Tone",
                        options: TranscriptTone.allCases,
                        selection: Binding(
                            get: {
                                TranscriptTone(rawValue: toneRawValue) ?? .auto
                            },
                            set: { toneRawValue = $0.rawValue }
                        ),
                        minWidth: 150,
                        title: { $0.displayName }
                    )
                }

                ZenPanelDivider()

                ZenRow(
                    icon: "quote.bubble",
                    title: "Spoken commands",
                    subtitle:
                        "“thinking emoji” becomes 🤔, “open parenthesis” becomes ("
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.voiceCommandsEnabled },
                            set: viewModel.setVoiceCommandsEnabled
                        ),
                        label: "Spoken commands"
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
                                    size: ZenDesign.Layout.rowIcon,
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

/// The formatting level as three preview cards (reference design): each card
/// shows the HUD with a sample line for that rung, plus a caption strip.
/// Selection drives the same `AppStorage`-backed mode the tab strip used.
private struct FormattingLevelPicker: View {
    @Binding var mode: TranscriptFormattingMode

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            Text("FORMATTING")
                .font(ZenDesign.Typography.eyebrow)
                .tracking(1.1)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)

            HStack(spacing: ZenDesign.Layout.contentGap) {
                ForEach(TranscriptFormattingMode.allCases) { candidate in
                    FormattingLevelCard(
                        mode: candidate,
                        isSelected: candidate == mode
                    ) {
                        mode = candidate
                    }
                }
            }
        }
    }
}

private struct FormattingLevelCard: View {
    let mode: TranscriptFormattingMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    ZenDesign.Gradient.hudPreview
                    Text(sampleLine)
                        .font(sampleFont)
                        .foregroundStyle(sampleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                            .fill(ZenDesign.Glass.hudTint)
                        }
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                // The thumbnail absorbs any height difference between cards
                // (one-line vs two-line captions), so the caption strip stays
                // flush with the card bottom and no dead space collects.
                .frame(minHeight: 96, maxHeight: .infinity)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: ZenDesign.Spacing.xs) {
                        Image(systemName: glyph)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                isSelected
                                    ? ZenDesign.Semantic.accent
                                    : ZenDesign.Semantic.textSecondary
                            )
                        Text(mode.displayName)
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    }
                    Text(blurb)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenDesign.Spacing.md)
            }
            .background(ZenDesign.Semantic.surface)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.large,
                    style: .continuous
                )
            )
            // Equal heights: every card stretches to the row's tallest
            // sibling, so single-line captions don't shrink their card.
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.large,
                    style: .continuous
                )
                .strokeBorder(
                    isSelected
                        ? ZenDesign.Semantic.accentFill
                        : ZenDesign.Semantic.border.opacity(0.72),
                    lineWidth: isSelected ? 2 : 1
                )
            }
            // Soft pink glow on the selected card, matching the reference.
            .shadow(
                color: isSelected ? ZenDesign.Glass.glow : .clear,
                radius: 12
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(mode.displayName): \(blurb)")
    }

    private var sampleLine: String {
        switch mode {
        case .off: return "um, meet at 930 on, on friday"
        case .clean: return "Meet at 9:30 on Friday"
        case .smart: return "Can we meet at 9:30 on Friday?"
        }
    }

    private var sampleFont: Font {
        switch mode {
        case .off: return .system(size: 11)
        case .clean: return .system(size: 13, weight: .semibold)
        case .smart: return .system(size: 13)
        }
    }

    private var sampleColor: Color {
        switch mode {
        case .off: return ZenDesign.Semantic.textSecondary
        case .clean, .smart: return .white
        }
    }

    private var glyph: String {
        switch mode {
        case .off: return "textformat.alt"
        case .clean: return "sparkles"
        case .smart: return "wand.and.stars"
        }
    }

    private var blurb: String {
        switch mode {
        case .off: return "Your exact words, untouched"
        case .clean: return "Fillers out, times and numbers fixed"
        case .smart: return "Reads like you wrote it"
        }
    }
}

extension TranscriptFormattingMode: Identifiable {
    public var id: String { rawValue }
}

/// Selection for the Smart rung's enhancement model. Backed by the same
/// `ZenPolishPreferences.preferenceKey` as the former toggle, so the runtime
/// wiring is unchanged.
private enum FormattingModelChoice: String, CaseIterable, Identifiable {
    case none
    case zenPolishV2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .zenPolishV2: return "ZenPolish 1.7B v2"
        }
    }
}
