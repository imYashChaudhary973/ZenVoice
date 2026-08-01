import SwiftUI
import ZenVoiceCore
import ZenVoiceStorage

struct InstantRefineScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZenScreen(
            title: "Instant Refine",
            subtitle: "How ZenVoice shapes your words after it hears them."
        ) {
            modeSection
            liveDictationSection
            contextSection
            voiceCommandsSection
        }
    }

    // MARK: mode

    private var modeSection: some View {
        ZenSection(title: "Refinement mode") {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    modeCard(.off, detail: "Raw transcript")
                    modeCard(.clean, detail: "Fillers & restarts out")
                    modeCard(
                        .agentPrompt, detail: "Speech → structured prompt"
                    )
                    // Local Model is withheld — see
                    // InstantRefineMode.userSelectable. It measured 0.0 points
                    // of improvement over Clean while asking for a 1.1 GB
                    // download, so offering it would charge the user a
                    // gigabyte and a wait for identical text.
                }

                ZenPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.instantRefineMode.detail)
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        if let sample = modeSample {
                            Text(sample)
                                .font(ZenDesign.Typography.mono)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                                .fixedSize(
                                    horizontal: false, vertical: true
                                )
                        }
                    }
                    .padding(ZenDesign.Spacing.md)
                }
            }
        }
    }

    private func modeCard(
        _ mode: InstantRefineMode,
        detail: String
    ) -> some View {
        ZenChoiceCard(
            title: mode.displayName,
            detail: detail,
            selected: viewModel.instantRefineMode == mode
        ) {
            viewModel.setInstantRefineMode(mode)
        }
    }

    private var modeSample: String? {
        switch viewModel.instantRefineMode {
        case .off:
            return "“um, create the the local app with Swift”"
        case .clean:
            return "“um, create the the local app with Swift” → “Create the local app with Swift.”"
        case .agentPrompt:
            return "“fix the login bug” → structured, ready-to-paste prompt"
        }
    }

    // MARK: live dictation

    private var liveDictationSection: some View {
        ZenSection(title: "Live dictation") {
            ZenPanel {
                HStack(spacing: ZenDesign.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text("Detect stable phrases")
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            ZenBadge(text: "Slower", kind: .warn)
                        }
                        Text(
                            "Transcribe each phrase as you pause, so text can appear before you stop. Required for commit-on-pause. Costs about twice the processing per dictation, and short fragments transcribe less accurately than a whole sentence — so this is off unless you want it."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ZenDesign.Spacing.sm)
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.livePreviewEnabled },
                            set: viewModel.setLivePreviewEnabled
                        ),
                        label: "Stable phrase detection"
                    )
                }
                .padding(.horizontal, ZenDesign.Spacing.md)
                .padding(.vertical, ZenDesign.Spacing.sm)
                .frame(minHeight: 52)
                ZenPanelDivider()
                HStack(spacing: ZenDesign.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text("Commit on pause")
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            ZenBadge(text: "Experimental", kind: .warn)
                        }
                        Text(
                            "Paste each stable phrase when you pause, instead of all at the end. Guarded: pastes only while the app where dictation started stays active."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ZenDesign.Spacing.sm)
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.commitOnPauseEnabled },
                            set: viewModel.setCommitOnPauseEnabled
                        ),
                        label: "Commit on pause"
                    )
                    .disabled(!viewModel.livePreviewEnabled)
                }
                .padding(.horizontal, ZenDesign.Spacing.md)
                .padding(.vertical, ZenDesign.Spacing.sm)
                .frame(minHeight: 52)
            }
        }
    }

    // MARK: one-shot context

    private var contextSection: some View {
        ZenSection(
            title: "One-shot context",
            caption: "Memory only — clears when the next recording starts"
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(
                            "Names and topic hints help transcription get spellings right. Nothing here is ever written to disk."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        Spacer()
                        Text(
                            "\(viewModel.sanitizedNextDictationContext.count)/\(NextDictationContext.maximumCharacterCount)"
                        )
                        .font(ZenDesign.Typography.monoSmall)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    }

                    TextEditor(text: $viewModel.nextDictationContext)
                        .font(ZenDesign.Typography.body)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 64, maxHeight: 82)
                        .background {
                            RoundedRectangle(
                                cornerRadius: ZenDesign.Radius.small,
                                style: .continuous
                            )
                            .fill(ZenDesign.Semantic.surfaceSunken)
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
                        .onChange(
                            of: viewModel.nextDictationContext
                        ) { _, value in
                            let sanitized =
                                NextDictationContext.sanitized(value)
                            if sanitized.count
                                >= NextDictationContext
                                    .maximumCharacterCount {
                                viewModel.nextDictationContext =
                                    sanitized
                            }
                        }
                        .accessibilityLabel(
                            "Context for the next dictation"
                        )

                    HStack {
                        Label(
                            "Never written to history or settings",
                            systemImage: "memorychip"
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        Spacer()
                        Button(
                            "Clear",
                            action: viewModel.clearNextDictationContext
                        )
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .disabled(
                            viewModel.nextDictationContext.isEmpty
                        )
                    }
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    // MARK: voice commands

    private var voiceCommandsSection: some View {
        ZenSection(
            title: "Voice commands",
            caption: "Layout & punctuation, spoken mid-dictation"
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                ZenPanel {
                    commandRow(
                        "new line / new paragraph",
                        "Inserts a line break or blank line"
                    )
                    ZenPanelDivider()
                    commandRow(
                        "comma · full stop · question mark · exclamation mark",
                        "Inserts punctuation"
                    )
                    ZenPanelDivider()
                    commandRow(
                        "Hindi, Spanish, French, Mandarin, Arabic aliases",
                        "Every command works in six languages"
                    )
                }
                Text(
                    "Turn voice commands on or off globally — and per app — in App Profiles."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }
        }
    }

    private func commandRow(_ say: String, _ does: String) -> some View {
        HStack {
            Text("“\(say)”")
                .font(ZenDesign.Typography.body)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Spacer()
            Text(does)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .frame(minHeight: 44)
    }
}
