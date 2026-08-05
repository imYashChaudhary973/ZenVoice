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

struct OnboardingScreen: View {
    private enum Step: Int, CaseIterable {
        case welcome
        case privacy
        case permissions
        case shortcut
        case language
        case model
        case test
    }

    @ObservedObject var onboardingViewModel:
        OnboardingViewModel
    @ObservedObject var settingsViewModel:
        SettingsViewModel
    @ObservedObject var modelManagerViewModel:
        ModelManagerViewModel
    @AppStorage("zenvoice.onboarding.step")
    private var savedStep = 0
    @State private var step: Step = .welcome
    @State private var sandboxText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                brand
                Spacer()
                HStack(spacing: 6) {
                    ForEach(
                        Step.allCases,
                        id: \.rawValue
                    ) { item in
                        Capsule()
                            .fill(
                                item.rawValue <= step.rawValue
                                    ? ZenDesign.Semantic.accent
                                    : ZenDesign.Semantic.borderStrong
                            )
                            .frame(
                                width:
                                    item == step ? 20 : 6,
                                height: 6
                            )
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 22)

            ScrollView {
                Group {
                    switch step {
                    case .welcome:
                        welcome
                    case .privacy:
                        privacy
                    case .permissions:
                        permissions
                    case .shortcut:
                        shortcut
                    case .language:
                        language
                    case .model:
                        model
                    case .test:
                        test
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 42)
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(ZenDesign.Semantic.border)

            HStack {
                Button("Skip setup") {
                    finish()
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    ZenDesign.Semantic.textSecondary
                )

                Spacer()

                if step != .welcome {
                    Button("Back") {
                        move(by: -1)
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                }

                Button(
                    step == .test
                        ? "Start using ZenVoice"
                        : "Continue"
                ) {
                    if step == .test {
                        finish()
                    } else {
                        move(by: 1)
                    }
                }
                .buttonStyle(ZenPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 18)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .background(ZenDesign.Semantic.canvas)
        .onAppear {
            step = Step(rawValue: savedStep) ?? .welcome
            settingsViewModel.refreshSystemStatus()
            modelManagerViewModel.refresh()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "ZenVoice setup, step \(step.rawValue + 1) of \(Step.allCases.count)"
        )
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZenBrandMark(size: 28)
            Text("ZenVoice")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(
                    ZenDesign.Semantic.textPrimary
                )
        }
    }

    /* ---- 1 · welcome ---- */
    private var welcome: some View {
        onboardingPage(
            icon: "waveform.badge.mic",
            title: "Speak. It types. Nothing leaves your Mac.",
            detail:
                "ZenVoice turns speech into text on this Mac and inserts it wherever your cursor is — in any app.",
            facts: [
                ("network.slash", "No account or cloud transcription — everything runs on-device"),
                ("bolt.fill", "One shortcut works everywhere: Mail, Slack, Xcode, anything with a cursor"),
                ("lock.fill", "Encrypted local history — recover any dictation, even partial ones")
            ]
        )
    }

    /* ---- 2 · privacy ---- */
    private var privacy: some View {
        onboardingPage(
            icon: "lock.shield.fill",
            title: "Local-first by design.",
            detail:
                "Audio, transcripts, correction rules, insights, and model inference stay on this Mac. The only network use is model downloads you ask for.",
            facts: [
                ("key.fill", "Saved transcripts are encrypted — unreadable without this Mac's key"),
                ("eye.slash", "Private Dictation stores nothing at all"),
                ("trash", "Privacy shows a live inventory — delete anything, anytime")
            ]
        )
    }

    /* ---- 3 · permissions ---- */
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            onboardingHeading(
                icon: "checkmark.shield",
                title: "Two permissions, clearly explained.",
                detail:
                    "Microphone records only after you start dictation. Accessibility inserts the finished text into the active app."
            )
            permissionRow(
                title: "Microphone",
                status:
                    settingsViewModel.microphoneStatus.title,
                isAllowed:
                    settingsViewModel.microphoneStatus
                        == .allowed,
                action:
                    settingsViewModel.requestMicrophoneAccess
            )
            permissionRow(
                title: "Accessibility",
                status:
                    settingsViewModel.accessibilityStatus.title,
                isAllowed:
                    settingsViewModel.accessibilityStatus
                        == .allowed,
                action:
                    settingsViewModel.requestAccessibilityAccess
            )
            Text(
                "Both are optional — you can continue and grant them later from Privacy. Without Accessibility, transcripts are copied to the clipboard instead."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(
                ZenDesign.Semantic.textTertiary
            )
        }
    }

    /* ---- 4 · shortcut ---- */
    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 20) {
            onboardingHeading(
                icon: "command",
                title: "Your dictation shortcut.",
                detail:
                    "Press it once to start, again to finish. Keep the default or record your own — ZenVoice checks for conflicts before saving."
            )
            ZenPanel(padding: ZenDesign.Spacing.lg) {
                onboardingShortcutEditor
            }
            Text(
                "Prefer holding a key instead? Turn on Hold to dictate later in Shortcuts."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(
                ZenDesign.Semantic.textTertiary
            )
        }
    }

    /* ---- 5 · language ---- */
    private var language: some View {
        VStack(alignment: .leading, spacing: 20) {
            onboardingHeading(
                icon: "globe",
                title: "What will you speak?",
                detail:
                    "You can change this anytime, or set a different language per app in App Profiles."
            )
            VStack(spacing: 10) {
                languageChoice(
                    title: "English",
                    detail: "Fastest — works with every model",
                    selected:
                        settingsViewModel.languageProfile
                            == .english,
                    action:
                        settingsViewModel.useEnglishProfile
                )
                languageChoice(
                    title: "Hinglish",
                    detail:
                        "Hindi–English, written in Latin script the way you speak it",
                    selected:
                        settingsViewModel.languageProfile
                            == .hinglish,
                    action:
                        settingsViewModel.useHinglishProfile
                )
                languageChoice(
                    title: "Auto-detect",
                    detail:
                        "Figures out the spoken language per dictation",
                    selected:
                        settingsViewModel.languageProfile
                            .inputLanguageCode
                            == LanguageProfile.automaticCode,
                    action:
                        settingsViewModel.useAutomaticProfile
                )
            }
            Text(
                "64 more languages live in Languages. Hinglish uses Hinglish Apex; auto-detect uses a multilingual model. The next step recommends the right download."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(
                ZenDesign.Semantic.textTertiary
            )
        }
    }

    private func languageChoice(
        title: String,
        detail: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(
                            ZenDesign.Semantic.textPrimary
                        )
                    Text(detail)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(
                            ZenDesign.Semantic.textSecondary
                        )
                }
                Spacer()
                Image(
                    systemName: selected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(
                    selected
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Semantic.textTertiary
                )
            }
            .padding(14)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .fill(
                    selected
                        ? ZenDesign.Semantic.accentMuted
                        : ZenDesign.Component.cardBackground
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                    .strokeBorder(
                        selected
                            ? ZenDesign.Semantic.accent
                            : ZenDesign.Semantic.border
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(
            selected ? .isSelected : []
        )
    }

    /* ---- 6 · model ---- */
    private var featuredModel: VerifiedModel? {
        modelManagerViewModel.models.first {
            modelManagerViewModel.isLanguageCompatible($0)
                && modelManagerViewModel
                    .recommendation(for: $0).level
                    == .recommended
        } ?? modelManagerViewModel.models.first {
            modelManagerViewModel.isLanguageCompatible($0)
        }
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 20) {
            onboardingHeading(
                icon: "cpu",
                title: "One verified download.",
                detail:
                    "ZenVoice measured this Mac and picked the best fit. Every download is pinned to an exact revision and SHA-256 checked before use."
            )
            if let model = featuredModel {
                ZenPanel(padding: ZenDesign.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(model.displayName)
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            ZenBadge(
                                text: "Recommended",
                                kind: .success,
                                showsDot: true
                            )
                            Spacer()
                            modelAction(model)
                        }
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount: model.fileSizeBytes,
                                countStyle: .file
                            )
                            + " · rev \(model.sourceRevision.prefix(9))"
                            + " · sha256 \(model.sha256.prefix(8))…"
                        )
                        .font(ZenDesign.Typography.monoSmall)
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )

                        if modelManagerViewModel
                            .downloadingModelID == model.id {
                            ZenProgressBar(
                                value:
                                    modelManagerViewModel
                                        .downloadProgress ?? 0
                            )
                        }

                        if let error =
                            modelManagerViewModel.errorMessage {
                            ErrorBanner(message: error)
                        }
                    }
                }
            }
            Text(
                "You can skip this and download from Models later — dictation needs at least one speech model."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(
                ZenDesign.Semantic.textTertiary
            )
        }
    }

    @ViewBuilder
    private func modelAction(_ model: VerifiedModel) -> some View {
        if modelManagerViewModel.isInstalled(model) {
            ZenBadge(
                text: "Verified & ready",
                kind: .success,
                showsDot: true
            )
        } else if modelManagerViewModel.downloadingModelID
            == model.id {
            Button("Cancel") {
                modelManagerViewModel.cancelDownload()
            }
            .buttonStyle(ZenSecondaryButtonStyle())
        } else {
            Button("Download") {
                modelManagerViewModel.download(model)
            }
            .buttonStyle(ZenPrimaryButtonStyle())
        }
    }

    /* ---- 7 · test drive ---- */
    private var test: some View {
        VStack(alignment: .leading, spacing: 20) {
            onboardingHeading(
                icon: "mic.fill",
                title: "Take it for a spin.",
                detail:
                    "Click into the sandbox below, press \(settingsViewModel.currentShortcut.displayName), speak, then press it again."
            )
            TextEditor(text: $sandboxText)
                .font(ZenDesign.Typography.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 84)
                .background {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                    .fill(ZenDesign.Component.cardBackground)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.medium,
                            style: .continuous
                        )
                        .strokeBorder(
                            ZenDesign.Semantic.borderStrong,
                            style: StrokeStyle(
                                lineWidth: 1,
                                dash: [5, 4]
                            )
                        )
                    }
                }
                .accessibilityLabel("Dictation sandbox")
            onboardingStatus(
                title: "Language",
                value:
                    settingsViewModel.languageProfile
                        .displayName,
                isReady: true
            )
            onboardingStatus(
                title: "Local speech model",
                value:
                    settingsViewModel.isLocalModelReady
                        ? "Ready"
                        : "Download in Models",
                isReady:
                    settingsViewModel.isLocalModelReady
            )
            Text(
                "Replay this setup anytime from Help & FAQ. ZenVoice lives in your menu bar after you close this window."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(
                ZenDesign.Semantic.textTertiary
            )
        }
    }

    private func onboardingPage(
        icon: String,
        title: String,
        detail: String,
        facts: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            onboardingHeading(
                icon: icon,
                title: title,
                detail: detail
            )
            ZenPanel(padding: ZenDesign.Spacing.lg) {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(
                        Array(facts.enumerated()),
                        id: \.offset
                    ) { _, fact in
                        PrivacyFact(
                            icon: fact.0,
                            text: fact.1
                        )
                    }
                }
            }
        }
    }

    private func onboardingHeading(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                    .fill(ZenDesign.Semantic.surfaceRaised)
                }
                .accessibilityHidden(true)
            Text(title)
                .font(ZenDesign.Typography.display)
                .foregroundStyle(
                    ZenDesign.Semantic.textPrimary
                )
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(ZenDesign.Typography.body)
                .foregroundStyle(
                    ZenDesign.Semantic.textSecondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
    }

    private func permissionRow(
        title: String,
        status: String,
        isAllowed: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(
                systemName:
                    isAllowed
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle"
            )
            .foregroundStyle(
                isAllowed
                    ? ZenDesign.Semantic.success
                    : ZenDesign.Semantic.warn
            )
            Text(title)
                .font(ZenDesign.Typography.bodyStrong)
                .foregroundStyle(
                    ZenDesign.Semantic.textPrimary
                )
            Spacer()
            Text(status)
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(
                    ZenDesign.Semantic.textSecondary
                )
            Button(
                isAllowed ? "Recheck" : "Allow",
                action: action
            )
            .buttonStyle(ZenSecondaryButtonStyle())
        }
        .padding(14)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .fill(ZenDesign.Component.cardBackground)
        }
    }

    private func onboardingStatus(
        title: String,
        value: String,
        isReady: Bool
    ) -> some View {
        HStack {
            Text(title)
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(
                    ZenDesign.Semantic.textSecondary
                )
            Spacer()
            ZenBadge(
                text: value,
                kind: isReady ? .success : .danger,
                showsDot: true
            )
        }
    }

    private var onboardingShortcutEditor: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Dictation shortcut")
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(
                        ZenDesign.Semantic.textSecondary
                    )
                Text("Choose any supported modifier and key combination.")
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
            }
            Spacer()
            ShortcutCaptureButton(
                displayName:
                    settingsViewModel.currentShortcut.displayName,
                isCapturing:
                    settingsViewModel.isCapturingShortcut,
                action: {
                    if settingsViewModel.isCapturingShortcut {
                        settingsViewModel.cancelShortcutCapture()
                    } else {
                        settingsViewModel.beginShortcutCapture()
                    }
                }
            )
        }
    }

    private func move(by offset: Int) {
        let next = min(
            Step.allCases.count - 1,
            max(0, step.rawValue + offset)
        )
        step = Step(rawValue: next) ?? step
        savedStep = step.rawValue
    }

    private func finish() {
        savedStep = 0
        onboardingViewModel.complete()
    }
}

private struct PrivacyFact: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }
}
