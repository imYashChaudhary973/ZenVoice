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
    /// Six steps, and every one of them either asks for something or hands
    /// something back. The old flow opened with two consecutive pages of
    /// reading — a promise page and a privacy page — before the user could do
    /// anything, which is the most expensive place in an app to spend
    /// somebody's patience. They are one page now.
    private enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case shortcut
        case language
        case model
        case test

        /// Shown beside the progress dots. A user who can see where the flow
        /// ends stops wondering how long it is.
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .permissions: return "Permissions"
            case .shortcut: return "Shortcut"
            case .language: return "Language"
            case .model: return "Engine"
            case .test: return "Try it"
            }
        }
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

    private var canContinue: Bool {
        switch step {
        case .welcome:
            return true
        case .permissions:
            return settingsViewModel.microphoneStatus == .allowed
                && settingsViewModel.accessibilityStatus == .allowed
        case .shortcut:
            return true
        case .language:
            return true
        case .model, .test:
            return hasReadySpeechEngine
        }
    }

    private var hasReadySpeechEngine: Bool {
        let id = modelManagerViewModel.selectedEngineID
            ?? EngineIdentifiers.appleSpeech
        if id == EngineIdentifiers.appleSpeech {
            return true
        }
        return modelManagerViewModel.installedEngineIDs.contains(id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                brand
                Spacer()
                HStack(spacing: ZenDesign.Spacing.sm) {
                    Text("Step \(step.rawValue + 1) of \(Step.allCases.count) · \(step.title)")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .monospacedDigit()
                    HStack(spacing: 5) {
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
                                    width: item == step ? 18 : 5,
                                    height: 5
                                )
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .padding(.horizontal, ZenDesign.Spacing.xxl)
            .padding(.top, ZenDesign.Spacing.xl)

            ScrollView {
                Group {
                    switch step {
                    case .welcome:
                        welcome
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
                .frame(maxWidth: step == .model ? 760 : 560, alignment: .leading)
                .padding(.horizontal, ZenDesign.Spacing.xxl)
                .padding(.vertical, ZenDesign.Spacing.xxl)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(ZenDesign.Semantic.border)

            HStack {
                if step != .welcome {
                    Button("Back") {
                        move(by: -1)
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                }

                Spacer()

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
                .disabled(!canContinue)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, ZenDesign.Spacing.xxl)
            .padding(.vertical, ZenDesign.Spacing.lg)
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
        HStack(spacing: ZenDesign.Spacing.xs) {
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
                "ZenVoice turns speech into text on this Mac and inserts it wherever your cursor is — in any app. Audio, transcripts, correction rules, and model inference all stay here; the only network use is a model download you ask for.",
            facts: [
                ("network.slash", "No account, no subscription, no cloud transcription"),
                ("bolt.fill", "One shortcut everywhere: Mail, Slack, Xcode, anything with a cursor"),
                ("key.fill", "Saved transcripts are encrypted — unreadable without this Mac's key"),
                ("pause.circle", "Pause history anytime in Privacy")
            ]
        )
    }

    /* ---- 3 · permissions ---- */
    private var permissions: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
            onboardingHeading(
                icon: "checkmark.shield",
                title: "Two permissions, clearly explained.",
                detail:
                    "Microphone records only after you start dictation. Accessibility inserts the finished text into the active app."
            )
            permissionRow(
                title: "Microphone",
                status: settingsViewModel.microphoneStatus,
                action:
                    settingsViewModel.requestMicrophoneAccess
            )
            permissionRow(
                title: "Accessibility",
                status: settingsViewModel.accessibilityStatus,
                action:
                    settingsViewModel.requestAccessibilityAccess
            )
            Text(
                "Both are required before you can continue. ZenVoice cannot hear or insert text without them."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(
                ZenDesign.Semantic.textTertiary
            )
        }
        // Granting happens in System Settings, so this step watches for the
        // change instead of showing a stale status until the user clicks
        // something.
        .onAppear(perform: settingsViewModel.beginWatchingPermissions)
        .onDisappear(perform: settingsViewModel.stopWatchingPermissions)
    }

    /* ---- 4 · shortcut ---- */
    private var shortcut: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
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
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
            onboardingHeading(
                icon: "globe",
                title: "What will you speak?",
                detail:
                    "You can change this anytime in Language."
            )
            VStack(spacing: ZenDesign.Spacing.xs) {
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
                "More spoken languages live in Models. Next: pick a speech engine."
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
            ZenInsetRow(tinted: selected) {
                HStack(spacing: ZenDesign.Spacing.sm) {
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
                .padding(.vertical, ZenDesign.Spacing.xs)
            }
        }
        .buttonStyle(ZenPressButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(
            selected ? .isSelected : []
        )
    }

    /* ---- 6 · model ---- */
    private var chosenEngineID: String {
        modelManagerViewModel.selectedEngineID
            ?? EngineIdentifiers.appleSpeech
    }


    private var model: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
            onboardingHeading(
                icon: "waveform",
                title: "Choose your speech engine.",
                detail:
                    "All three run entirely on this Mac. Apple Speech is ready now, so the first dictation just works."
            )
            HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
                engineCard(
                    icon: "apple.logo",
                    title: "Apple Speech",
                    badge: "Built in",
                    badgeKind: .success,
                    detail: "Built into macOS. Nothing to download.",
                    selected: chosenEngineID == EngineIdentifiers.appleSpeech,
                    enabled: true
                ) {
                    modelManagerViewModel.selectEngine(
                        EngineIdentifiers.appleSpeech
                    )
                } footer: {
                    ZenBadge(
                        text: "Built in",
                        kind: .success,
                        showsDot: true
                    )
                }

                engineCard(
                    icon: "hare.fill",
                    title: "Parakeet V3",
                    badge: "Fastest",
                    badgeKind: .accent,
                    detail: "Fastest local engine. 25 languages.",
                    selected: chosenEngineID == EngineIdentifiers.parakeetTDTv3,
                    enabled: true
                ) {
                    modelManagerViewModel.selectEngine(
                        EngineIdentifiers.parakeetTDTv3
                    )
                } footer: {
                    parakeetCardFooter
                }

                engineCard(
                    icon: "globe",
                    title: "Nemotron 3.5",
                    badge: "Streaming",
                    badgeKind: .accent,
                    detail: "True live streaming. 8 languages, including Chinese and Japanese.",
                    selected: chosenEngineID == EngineIdentifiers.nemotronSpeech,
                    enabled: true
                ) {
                    modelManagerViewModel.selectEngine(
                        EngineIdentifiers.nemotronSpeech
                    )
                } footer: {
                    nemotronCardFooter
                }
            }

            if let error = modelManagerViewModel.errorMessage {
                ErrorBanner(message: error)
            }

            Text(
                "Whisper models stay in Models if you want them later."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
        }
        .onAppear {
            if modelManagerViewModel.selectedEngineID == nil {
                modelManagerViewModel.selectEngine(
                    EngineIdentifiers.appleSpeech
                )
            }
        }
    }

    @ViewBuilder
    private var parakeetCardFooter: some View {
        downloadFooter(id: EngineIdentifiers.parakeetTDTv3)
    }

    @ViewBuilder
    private var nemotronCardFooter: some View {
        downloadFooter(id: EngineIdentifiers.nemotronSpeech)
    }

    @ViewBuilder
    private func downloadFooter(id: String) -> some View {
        let installed = modelManagerViewModel.installedEngineIDs.contains(id)
        let downloading = modelManagerViewModel.downloadingModelID == id
        if downloading {
            VStack(alignment: .leading, spacing: 6) {
                ZenProgressBar(
                    value: modelManagerViewModel.downloadProgress ?? 0
                )
                Button("Cancel") {
                    modelManagerViewModel.cancelDownload()
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }
        } else if installed {
            ZenBadge(text: "Ready", kind: .success, showsDot: true)
        } else {
            Button(downloadLabel(id: id)) {
                modelManagerViewModel.selectEngine(id)
            }
            .buttonStyle(ZenPrimaryButtonStyle())
        }
    }

    private func downloadLabel(id: String) -> String {
        guard let bytes = VerifiedEngineCatalog.engine(id: id)?.fileSizeBytes
        else {
            return "Download"
        }
        return "Download · "
            + ByteCountFormatter.string(
                fromByteCount: bytes,
                countStyle: .file
            )
    }

    private func engineCard<Footer: View>(
        icon: String,
        title: String,
        badge: String?,
        badgeKind: ZenBadge.Kind,
        detail: String,
        selected: Bool,
        enabled: Bool,
        select: @escaping () -> Void,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                    .fill(ZenDesign.Component.cardBackground)
                    .frame(height: 72)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                }
                HStack(spacing: 6) {
                    Text(title)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    if let badge {
                        ZenBadge(text: badge, kind: badgeKind)
                    }
                }
                Text(detail)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 36, alignment: .top)
                footer()
            }
            .padding(ZenDesign.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.large,
                    style: .continuous
                )
                .fill(ZenDesign.Component.cardBackground)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.large,
                        style: .continuous
                    )
                    .strokeBorder(
                        selected
                            ? ZenDesign.Semantic.accent
                            : ZenDesign.Semantic.borderStrong,
                        lineWidth: selected ? 2 : 1
                    )
                }
            }
        }
        .buttonStyle(ZenPressButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /* ---- 6 · test drive ---- */
    private var test: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
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
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            onboardingHeading(
                icon: icon,
                title: title,
                detail: detail
            )
            ZenPanel(padding: ZenDesign.Spacing.lg) {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
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
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            ZenIconChip(
                systemImage: icon,
                size: 52,
                tint: ZenDesign.Semantic.textSecondary
            )
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
        status: SettingsViewModel.PermissionStatus,
        action: @escaping () -> Void
    ) -> some View {
        ZenPanel(padding: 0) {
            ZenRow(
                icon:
                    status.isAllowed
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle",
                iconTint: status.isAllowed
                    ? ZenDesign.Semantic.success
                    : ZenDesign.Semantic.warn,
                title: title,
                subtitle: status.remedy
            ) {
                HStack(spacing: ZenDesign.Spacing.sm) {
                    Text(status.title)
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(
                            ZenDesign.Semantic.textSecondary
                        )
                    if let actionTitle = status.actionTitle {
                        Button(actionTitle, action: action)
                            .buttonStyle(ZenSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private func onboardingStatus(
        title: String,
        value: String,
        isReady: Bool
    ) -> some View {
        ZenRow(title: title) {
            ZenBadge(
                text: value,
                kind: isReady ? .success : .danger,
                showsDot: true
            )
        }
    }

    private var onboardingShortcutEditor: some View {
        HStack(spacing: ZenDesign.Spacing.md) {
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
        HStack(spacing: ZenDesign.Spacing.xs) {
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
