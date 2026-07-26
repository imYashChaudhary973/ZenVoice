import SwiftUI
import ZenVoiceCore
import ZenVoiceStorage

private enum OverviewDestination {
    case audio
    case models
    case languages
    case history
    case insights
    case shortcuts
    case help
}

struct ZenVoiceSettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case home = "Home"
        case shortcuts = "Shortcuts"
        case audio = "Audio"
        case languages = "Languages"
        case refine = "Instant Refine"
        case voiceProfile = "Voice Profile"
        case appProfiles = "App Profiles"
        case history = "History"
        case insights = "Insights"
        case models = "Models"
        case privacy = "Privacy"
        case help = "Help & FAQ"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home:
                return "house"
            case .shortcuts:
                return "command"
            case .audio:
                return "mic"
            case .languages:
                return "globe"
            case .refine:
                return "wand.and.stars"
            case .voiceProfile:
                return "quote.bubble"
            case .appProfiles:
                return "square.grid.2x2"
            case .history:
                return "clock.arrow.circlepath"
            case .insights:
                return "chart.bar.xaxis"
            case .models:
                return "cpu"
            case .privacy:
                return "hand.raised"
            case .help:
                return "questionmark.circle"
            }
        }

        /// Grouped navigation (DESIGN.md §6).
        static let groups: [(title: String?, sections: [Section])] = [
            (nil, [.home]),
            ("Dictation", [.shortcuts, .audio, .languages, .refine]),
            ("Personal", [.voiceProfile, .appProfiles]),
            ("Your data", [.history, .insights]),
            ("System", [.models, .privacy, .help])
        ]
    }

    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var insightsViewModel: InsightsViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var applicationProfileViewModel:
        ApplicationProfileViewModel
    @ObservedObject var onboardingViewModel:
        OnboardingViewModel
    @ObservedObject var appState: AppState
    let toggleRecording: () -> Void
    @State private var selection: Section = .home
    @AppStorage("zenvoice.appearance") private var appearance = "light"

    private var prefersDarkAppearance: Bool {
        appearance != "light"
    }

    var body: some View {
        Group {
            if onboardingViewModel.isPresented {
                // First-run setup owns the whole window — it is never
                // presented as a sheet above the settings tabs.
                OnboardingScreen(
                    onboardingViewModel: onboardingViewModel,
                    settingsViewModel: viewModel,
                    modelManagerViewModel: modelManagerViewModel
                )
            } else {
                VStack(spacing: 0) {
                    ledgerTitleBar
                    HStack(spacing: 0) {
                        sidebar
                        content
                    }
                }
            }
        }
        .background(ZenDesign.Semantic.canvas)
        .frame(minWidth: 900, minHeight: 640)
        .preferredColorScheme(
            prefersDarkAppearance ? .dark : .light
        )
        .onAppear {
            viewModel.refreshSystemStatus()
        }
    }

    private var ledgerTitleBar: some View {
        ZStack {
            Text("ZenVoice")
                .font(.system(size: 13.5, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(ZenDesign.Semantic.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ZenDesign.Semantic.border)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZenBrandMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ZenVoice")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Local voice, refined")
                        .font(.system(size: 10.5, design: .serif))
                        .italic()
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ZenDesign.Semantic.border)
                    .frame(height: 1)
            }
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(
                        Array(Section.groups.enumerated()),
                        id: \.offset
                    ) { index, group in
                        if let title = group.title {
                            Text(title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                                .padding(.horizontal, 8)
                                .padding(.top, index == 0 ? 0 : 16)
                                .padding(.bottom, 6)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(group.sections) { section in
                            sidebarItem(section)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 10)

            Rectangle()
                .fill(ZenDesign.Semantic.border)
                .frame(height: 1)
                .padding(.horizontal, -2)
                .padding(.bottom, 10)

            HStack(spacing: 2) {
                appearanceButton(
                    title: "Light",
                    systemImage: "sun.max",
                    value: "light"
                )
                appearanceButton(
                    title: "Dark",
                    systemImage: "moon",
                    value: "dark"
                )
            }
            .padding(2)
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
                    .strokeBorder(ZenDesign.Semantic.border)
                }
            }

        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 224)
        .background(ZenDesign.Semantic.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ZenDesign.Semantic.border)
                .frame(width: 1)
        }
    }

    private func sidebarItem(_ section: Section) -> some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 15)
                    .foregroundStyle(
                        selection == section
                            ? ZenDesign.Semantic.accent
                            : ZenDesign.Semantic.textTertiary
                    )
                Text(section.rawValue)
                    .font(
                        selection == section
                            ? ZenDesign.Typography.bodyStrong
                            : ZenDesign.Typography.body
                    )
                    .foregroundStyle(
                        selection == section
                            ? ZenDesign.Semantic.accentStrong
                            : ZenDesign.Semantic.textSecondary
                    )
                Spacer()
                if section == .history,
                   historyViewModel.recoveryCount > 0 {
                    Text("\(historyViewModel.recoveryCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textOnAccent
                        )
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    ZenDesign.Semantic.accent
                                )
                        }
                        .accessibilityLabel(
                            "\(historyViewModel.recoveryCount) items in Recovery Inbox"
                        )
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    selection == section
                        ? ZenDesign.Component.selectedNavigation
                        : Color.clear
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 1)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(
            selection == section ? .isSelected : []
        )
    }

    private func appearanceButton(
        title: String,
        systemImage: String,
        value: String
    ) -> some View {
        let selected = appearance == value
        return Button {
            appearance = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(ZenDesign.Typography.captionStrong)
            }
            .foregroundStyle(
                selected
                    ? ZenDesign.Semantic.textPrimary
                    : ZenDesign.Semantic.textSecondary
            )
            .frame(maxWidth: .infinity, minHeight: 25)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        selected
                            ? ZenDesign.Semantic.surface
                            : Color.clear
                    )
                    .shadow(
                        color: selected ? Color.black.opacity(0.10) : .clear,
                        radius: 2,
                        y: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) appearance")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:
            OverviewScreen(
                viewModel: viewModel,
                appState: appState,
                modelManagerViewModel: modelManagerViewModel,
                historyViewModel: historyViewModel,
                insightsViewModel: insightsViewModel,
                startDictation: toggleRecording,
                replaySetup: onboardingViewModel.show,
                navigate: { destination in
                    switch destination {
                    case .audio:
                        selection = .audio
                    case .models:
                        selection = .models
                    case .languages:
                        selection = .languages
                    case .history:
                        selection = .history
                    case .insights:
                        selection = .insights
                    case .shortcuts:
                        selection = .shortcuts
                    case .help:
                        selection = .help
                    }
                }
            )
        case .audio:
            AudioScreen(viewModel: viewModel)
        case .models:
            ModelsScreen(viewModel: modelManagerViewModel)
        case .languages:
            LanguagesScreen(viewModel: viewModel)
        case .refine:
            InstantRefineScreen(
                viewModel: viewModel,
            )
        case .history:
            HistoryScreen(viewModel: historyViewModel)
        case .insights:
            InsightsScreen(viewModel: insightsViewModel)
        case .voiceProfile:
            VoiceProfileScreen(viewModel: voiceProfileViewModel)
        case .appProfiles:
            AppProfilesScreen(
                viewModel: viewModel,
                applicationProfileViewModel:
                    applicationProfileViewModel
            )
        case .shortcuts:
            ShortcutsScreen(viewModel: viewModel)
        case .privacy:
            PrivacyScreen(
                viewModel: viewModel,
                historyViewModel: historyViewModel,
                voiceProfileViewModel:
                    voiceProfileViewModel,
                modelManagerViewModel:
                    modelManagerViewModel,
            )
        case .help:
            HelpScreen(
                viewModel: viewModel,
                onboardingViewModel: onboardingViewModel,
                openShortcuts: { selection = .shortcuts }
            )
        }
    }

}

private struct OnboardingScreen: View {
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
            ZenCard {
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
                ZenCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(model.displayName)
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            StatusPill(
                                title: "Recommended",
                                isPositive: true
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
                            ProgressView(
                                value:
                                    modelManagerViewModel
                                        .downloadProgress ?? 0
                            )
                            .tint(ZenDesign.Semantic.accent)
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
            StatusPill(
                title: "Verified & ready",
                isPositive: true
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
            ZenCard {
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
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                    .fill(ZenDesign.Semantic.accentMuted)
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
                    : ZenDesign.Semantic.accent
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
            StatusPill(
                title: value,
                isPositive: isReady
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

private struct AudioScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZenScreen(
            title: "Audio",
            subtitle: "Pick the microphone ZenVoice listens to."
        ) {
            inputSection
            doctorSection

            ZenBanner(
                kind: .info,
                icon: "bolt.horizontal",
                text:
                    "If a pinned microphone disconnects during dictation, ZenVoice stops safely — anything captured follows your recovery-audio privacy setting."
            )
        }
        .onAppear {
            viewModel.refreshMicrophones()
        }
    }

    // MARK: input devices

    private var inputSection: some View {
        ZenSection(
            title: "Input device",
            caption: viewModel.selectedMicrophoneUID == nil
                ? "Following the macOS default"
                : "Pinned to \(viewModel.selectedMicrophoneName)"
        ) {
            ZenPanel {
                deviceButton(
                    id: nil,
                    icon: "macbook",
                    name: "System default",
                    detail:
                        "Follow the current macOS input automatically — switches when macOS does.",
                    selected: viewModel.selectedMicrophoneUID == nil,
                    isDefault: false,
                    enabled: !viewModel.isAudioDoctorActive
                )

                if viewModel.microphones.isEmpty {
                    ZenPanelDivider()
                    ZenRow(
                        icon: "mic.slash",
                        iconTint: ZenDesign.Semantic.danger,
                        iconBackground: ZenDesign.Semantic.dangerMuted,
                        title: "No connected microphones found",
                        subtitle: "Connect a microphone, then reopen this screen."
                    )
                } else {
                    ForEach(viewModel.microphones) { microphone in
                        ZenPanelDivider()
                        deviceButton(
                            id: microphone.id,
                            icon: deviceIcon(microphone),
                            name: microphone.name,
                            detail: microphoneDetail(microphone),
                            selected:
                                viewModel.selectedMicrophoneUID
                                    == microphone.id,
                            isDefault: microphone.isDefault,
                            enabled: microphone.isConnected
                                && !viewModel.isAudioDoctorActive
                        )
                    }
                }
            }
        }
    }

    private func deviceButton(
        id: String?,
        icon: String,
        name: String,
        detail: String,
        selected: Bool,
        isDefault: Bool,
        enabled: Bool
    ) -> some View {
        Button {
            viewModel.selectMicrophone(id)
        } label: {
            ZenRow(
                icon: icon,
                iconTint: selected ? ZenDesign.Semantic.accent : nil,
                iconBackground:
                    selected ? ZenDesign.Semantic.accentMuted : nil,
                title: name,
                subtitle: detail
            ) {
                if isDefault {
                    ZenBadge(text: "macOS default", kind: .neutral)
                }
                if selected {
                    ZenBadge(
                        text: "In use", kind: .accent,
                        systemImage: "checkmark"
                    )
                } else if enabled {
                    Text("Pin")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func deviceIcon(_ microphone: MicrophoneDevice) -> String {
        let name = microphone.name.lowercased()
        if name.contains("airpods") || name.contains("headphones") {
            return "headphones"
        }
        return "mic"
    }

    private func microphoneDetail(
        _ microphone: MicrophoneDevice
    ) -> String {
        if !microphone.isConnected {
            return "Disconnected"
        }
        if microphone.isInUseByAnotherApplication {
            return "Connected · also in use by another app"
        }
        return microphone.isDefault
            ? "Connected · current macOS default"
            : "Connected"
    }

    // MARK: audio doctor

    private var doctorSection: some View {
        ZenSection(
            title: "Audio Doctor",
            caption: "3-second on-device check"
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: ZenDesign.Spacing.sm) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                            .frame(width: 28, height: 28)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: 8, style: .continuous
                                )
                                .fill(ZenDesign.Semantic.surfaceRaised)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check signal and format")
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text(viewModel.audioDoctorState.title)
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(audioDoctorTint)
                        }
                        Spacer()
                        Button(audioDoctorButtonTitle) {
                            switch viewModel.audioDoctorState {
                            case .running, .paused:
                                viewModel.toggleAudioDoctorPause()
                            case .idle, .passed, .quiet, .failed:
                                viewModel.runAudioDoctor()
                            case .analyzing:
                                break
                            }
                        }
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .disabled(
                            viewModel.audioDoctorState == .analyzing
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        AudioDoctorWaveform(
                            samples: viewModel.audioDoctorSamples,
                            tint: audioDoctorTint
                        )
                        .frame(height: 44)

                        HStack {
                            Text(audioDoctorTimingLabel)
                            Spacer()
                            Text("16 kHz · mono · local")
                        }
                        .font(ZenDesign.Typography.monoSmall)
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
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
                            .strokeBorder(ZenDesign.Semantic.border)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Microphone waveform")
                    .accessibilityValue(
                        "\(Int((viewModel.audioDoctorLevel * 100).rounded())) percent"
                    )

                    Text(
                        "Records three seconds locally, measures loudness, confirms the sample format, then deletes the clip. No test audio leaves this Mac."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var audioDoctorTint: Color {
        switch viewModel.audioDoctorState {
        case .passed:
            return ZenDesign.Semantic.success
        case .quiet, .failed:
            return ZenDesign.Semantic.danger
        case .idle, .running, .paused, .analyzing:
            return ZenDesign.Semantic.accent
        }
    }

    private var audioDoctorButtonTitle: String {
        switch viewModel.audioDoctorState {
        case .running:
            return "Pause"
        case .paused:
            return "Resume"
        case .analyzing:
            return "Checking…"
        case .idle, .passed, .quiet, .failed:
            return "Run check"
        }
    }

    private var audioDoctorTimingLabel: String {
        switch viewModel.audioDoctorState {
        case .running, .paused:
            return String(
                format: "%.1f s remaining",
                viewModel.audioDoctorRemainingSeconds
            )
        case .analyzing:
            return "Capture complete · validating"
        case .idle:
            return "Ready · 3.0 s check"
        case .passed:
            return "Signal and format passed"
        case .quiet:
            return "Format passed · signal is quiet"
        case .failed:
            return "Check could not complete"
        }
    }
}

private struct AudioDoctorWaveform: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    let samples: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let count = max(1, samples.count)
            let barWidth = max(
                2,
                (proxy.size.width - spacing * CGFloat(count - 1))
                    / CGFloat(count)
            )
            HStack(alignment: .center, spacing: spacing) {
                ForEach(
                    Array(samples.enumerated()),
                    id: \.offset
                ) { _, sample in
                    Capsule()
                        .fill(
                            tint.opacity(sample > 0.03 ? 0.95 : 0.24)
                        )
                        .frame(
                            width: barWidth,
                            height: max(
                                3,
                                proxy.size.height
                                    * max(0.06, min(1, sample))
                            )
                        )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
        }
        .animation(
            reduceMotion ? nil : .linear(duration: 0.06),
            value: samples
        )
    }
}

private struct LanguagesScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""

    private var visibleLanguages: [SupportedLanguage] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else {
            return LanguageCatalog.languages
        }
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
        ZenScreen(
            title: "Languages",
            subtitle: "What you speak, and how it should be written."
        ) {
            if let error = viewModel.languageError {
                ZenBanner(
                    kind: .danger,
                    icon: "exclamationmark.triangle",
                    text: error
                )
            }

            profileSection
            outputSection
            allLanguagesSection

            if viewModel.languageProfile.requiresMultilingualModel {
                ZenBanner(
                    kind: .warn,
                    icon: "cpu",
                    text:
                        "This profile requires the Multilingual model — download it in Models. Language quality varies by model and language."
                )
            } else {
                ZenBanner(
                    kind: .info,
                    icon: "checkmark.shield",
                    text:
                        "English-only and Multilingual models are both compatible with this profile. Language quality varies by model and language."
                )
            }
        }
    }

    // MARK: quick profiles

    private var profileSection: some View {
        ZenSection(title: "English · Multilingual · Auto-Detect") {
            HStack(spacing: ZenDesign.Spacing.xs) {
                ZenChoiceCard(
                    title: "English",
                    detail: "English-safe: never outputs another language",
                    selected: viewModel.languageProfile == .english,
                    action: viewModel.useEnglishProfile
                )
                ZenChoiceCard(
                    title: "Hinglish",
                    badge: "Multilingual",
                    detail: "Hindi–English the way you actually speak it",
                    selected: viewModel.languageProfile == .hinglish,
                    action: viewModel.useHinglishProfile
                )
                ZenChoiceCard(
                    title: "Auto-Detect",
                    badge: "Multilingual model",
                    detail: "Detects the spoken language per dictation",
                    selected: isAutomatic,
                    action: viewModel.useAutomaticProfile
                )
            }
        }
    }

    // MARK: output mode

    private var outputSection: some View {
        ZenSection(
            title: "Output mode",
            caption: viewModel.languageProfile.displayName
        ) {
            HStack(spacing: ZenDesign.Spacing.xs) {
                ForEach(TranscriptionOutputMode.allCases) { mode in
                    ZenChoiceCard(
                        title: mode.displayName,
                        detail: mode.detail,
                        selected:
                            viewModel.languageProfile.outputMode == mode,
                        action: {
                            viewModel.setOutputMode(mode)
                        }
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Transcription output mode")
        }
    }

    // MARK: all languages

    private var allLanguagesSection: some View {
        ZenSection(
            title: "All languages",
            caption: "\(LanguageCatalog.languages.count) supported"
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                ZenSearchField(
                    placeholder: "Search languages…",
                    text: $searchText
                )

                ZenPanel {
                    Button {
                        viewModel.useAutomaticProfile()
                    } label: {
                        ZenRow(
                            icon: "wand.and.rays",
                            title: "Automatic detection",
                            subtitle:
                                "Useful for unknown input; less reliable for short phrases"
                        ) {
                            if isAutomatic {
                                ZenBadge(
                                    text: "Selected", kind: .accent,
                                    systemImage: "checkmark"
                                )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        isAutomatic ? .isSelected : []
                    )

                    if visibleLanguages.isEmpty {
                        ZenPanelDivider()
                        VStack(spacing: 4) {
                            Text("No language matches “\(searchText)”")
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text("Search covers English names, native names, and codes.")
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ZenDesign.Spacing.lg)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleLanguages) { language in
                                ZenPanelDivider()
                                languageButton(language)
                            }
                        }
                    }
                }
            }
        }
    }

    private func languageButton(
        _ language: SupportedLanguage
    ) -> some View {
        let selected = viewModel.languageProfile.inputLanguageCode
            == language.code
        return Button {
            viewModel.setInputLanguage(language.code)
        } label: {
            HStack(spacing: ZenDesign.Spacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.displayName)
                        .font(
                            selected
                                ? ZenDesign.Typography.bodyStrong
                                : ZenDesign.Typography.body
                        )
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(language.nativeName)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                ZenBadge(
                    text: language.supportLevel.displayName,
                    kind: .neutral
                )
                Image(
                    systemName: selected
                        ? "checkmark.circle.fill" : "circle"
                )
                .font(.system(size: 13))
                .foregroundStyle(
                    selected
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Semantic.borderStrong
                )
            }
            .padding(.horizontal, ZenDesign.Spacing.md)
            .frame(minHeight: 44)
            .background(
                selected
                    ? ZenDesign.Semantic.accentMuted
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ModelsScreen: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    @State private var modelPendingRemoval: VerifiedModel?
    @State private var selectedTier: ModelPerformanceTier?

    private var recommendedTier: ModelPerformanceTier {
        ModelRecommendationEngine.recommendedTier(
            for: viewModel.hardwareProfile,
            language: LanguagePreferences.load()
        )
    }

    private var activeTier: ModelPerformanceTier {
        selectedTier ?? recommendedTier
    }

    /// All models, with the picked tier's models listed first.
    private var orderedModels: [VerifiedModel] {
        viewModel.models.sorted { lhs, rhs in
            let lhsPick = lhs.tier == activeTier
            let rhsPick = rhs.tier == activeTier
            if lhsPick != rhsPick { return lhsPick }
            return false
        }
    }

    var body: some View {
        ZenScreen(
            title: "Models",
            subtitle:
                "Speech models run entirely on this Mac. Verified before first use."
        ) {
            ZenSection(
                title: "What matters most?",
                caption: viewModel.hardwareProfile.summary
            ) {
                HStack(spacing: ZenDesign.Spacing.xs) {
                    tierCard(
                        .fast,
                        icon: "gauge.with.needle",
                        detail: "Lowest latency · good accuracy"
                    )
                    tierCard(
                        .balanced,
                        icon: "slider.horizontal.3",
                        detail: "Best accuracy per second"
                    )
                    tierCard(
                        .highAccuracy,
                        icon: "target",
                        detail: "Strongest results · multilingual"
                    )
                }
            }

            ZenSection(
                title: "Speech models",
                caption: "whisper.cpp runtime, bundled"
            ) {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    if viewModel.isVerifying {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.small)
                            Text("Verifying installed models…")
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                        }
                    }

                    if let error = viewModel.errorMessage {
                        ZenBanner(
                            kind: .danger,
                            icon: "exclamationmark.triangle",
                            text: error
                        )
                    }

                    if let legacy = viewModel.selectedLegacyModel {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("Legacy model")
                                    .font(ZenDesign.Typography.captionStrong)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                                Spacer()
                                Text("Still verified and usable")
                                    .font(ZenDesign.Typography.caption)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textTertiary
                                    )
                            }
                            ZenPanel {
                                modelRow(legacy, isLegacy: true)
                            }
                        }
                    }

                    ZenPanel {
                        ForEach(orderedModels) { model in
                            if model.id != orderedModels.first?.id {
                                ZenPanelDivider()
                            }
                            modelRow(model)
                        }
                    }
                }
            }

            ZenBanner(
                kind: .info,
                icon: "internaldrive",
                text:
                    "Publisher, revision, licence, size, and checksum are recorded for every model — see the Verified Model Catalogue. Deleting a model frees its disk space immediately. After download, transcription runs locally with no account or API key."
            )
        }
        .alert(
            "Remove downloaded model?",
            isPresented: Binding(
                get: { modelPendingRemoval != nil },
                set: { if !$0 { modelPendingRemoval = nil } }
            ),
            presenting: modelPendingRemoval
        ) { model in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                viewModel.remove(model)
                modelPendingRemoval = nil
            }
        } message: { model in
            Text(
                "\(model.displayName) (\(model.languageCapability.displayName)) will be removed from this Mac."
            )
        }
    }

    private func tierCard(
        _ tier: ModelPerformanceTier,
        icon: String,
        detail: String
    ) -> some View {
        ZenChoiceCard(
            title: tier.displayName,
            badge: tier == recommendedTier ? "This Mac" : nil,
            detail: detail,
            selected: activeTier == tier,
            titleIcon: icon
        ) {
            selectedTier = tier
        }
    }

    private func modelRow(
        _ model: VerifiedModel,
        isLegacy: Bool = false
    ) -> some View {
        let isInstalled = viewModel.isInstalled(model)
        let isSelected = viewModel.isSelected(model)
        let isCompatible = viewModel.isLanguageCompatible(model)
        let selectionProfile = viewModel.selectionProfile(for: model)
        let isDownloading = viewModel.downloadingModelID == model.id
        let recommendation = viewModel.recommendation(for: model)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: ZenDesign.Spacing.sm) {
                Image(
                    systemName: {
                        switch model.languageCapability {
                        case .multilingual: "globe"
                        case .hinglish: "character.bubble"
                        case .english: "character.book.closed"
                        }
                    }()
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ZenDesign.Semantic.surfaceRaised)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(model.displayName)
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        if isSelected {
                            ZenBadge(
                                text: isLegacy ? "In use · Legacy" : "In use",
                                kind: isLegacy ? .neutral : .success,
                                systemImage: "checkmark"
                            )
                        } else if let badge =
                                    ModelProfileTransition
                                        .incompatibilityBadge(
                                            model: model,
                                            currentProfile:
                                                LanguagePreferences.load()
                                        ) {
                            ZenBadge(text: badge, kind: .neutral)
                        } else if model.tier == recommendedTier,
                                  recommendation.level == .recommended {
                            ZenBadge(
                                text: "Recommended for this Mac",
                                kind: .accent
                            )
                        }
                    }
                    Text(
                        rowNote(
                            model,
                            recommendation: recommendation,
                            isLegacy: isLegacy
                        )
                    )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: ZenDesign.Spacing.sm)

                trailingControls(
                    model,
                    isInstalled: isInstalled,
                    isSelected: isSelected,
                    isCompatible: isCompatible,
                    selectionProfile: selectionProfile,
                    isLegacy: isLegacy,
                    isDownloading: isDownloading,
                    recommendation: recommendation
                )
            }

            ZenModelMeta(parts: [
                model.languageCapability.displayName,
                model.formattedFileSize,
                "rev \(model.sourceRevision.prefix(9))",
                "sha256 \(model.sha256.prefix(8))…",
                model.license
            ])
            .padding(.leading, 44)
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .padding(.vertical, ZenDesign.Spacing.sm)
    }

    private func rowNote(
        _ model: VerifiedModel,
        recommendation: ModelRecommendation,
        isLegacy: Bool
    ) -> String {
        if isLegacy {
            return
                "This model remains available for existing installations "
                + "but is no longer recommended. Switch when you are ready."
        }
        if let benchmark = viewModel.benchmarkSummary(for: model) {
            let factor = benchmark.averageRealtimeFactor.formatted(
                .number.precision(.fractionLength(2))
            )
            let samples = "\(benchmark.sampleCount) local sample"
                + (benchmark.sampleCount == 1 ? "" : "s")
            return "\(recommendation.rationale) · \(factor)× realtime from \(samples)."
        }
        return recommendation.rationale
    }

    @ViewBuilder
    private func trailingControls(
        _ model: VerifiedModel,
        isInstalled: Bool,
        isSelected: Bool,
        isCompatible: Bool,
        selectionProfile: LanguageProfile?,
        isLegacy: Bool,
        isDownloading: Bool,
        recommendation: ModelRecommendation
    ) -> some View {
        if isDownloading {
            VStack(alignment: .trailing, spacing: 5) {
                ProgressView(value: viewModel.downloadProgress ?? 0)
                    .progressViewStyle(.linear)
                    .tint(ZenDesign.Semantic.accent)
                    .frame(width: 120)
                HStack(spacing: 6) {
                    Text(
                        viewModel.isVerifyingDownload
                            ? "Verifying checksum…"
                            : "\(Int(((viewModel.downloadProgress ?? 0) * 100).rounded()))% of \(model.formattedFileSize)"
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    Button("Cancel", action: viewModel.cancelDownload)
                        .buttonStyle(.plain)
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
            }
        } else if isInstalled {
            HStack(spacing: 6) {
                if isSelected,
                   isLegacy,
                   viewModel.recommendedInstalledModel != nil {
                    Button("Use recommended") {
                        viewModel.switchFromLegacyModel()
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                } else if !isSelected {
                    Button(
                        isCompatible ? "Use" : "Switch & use"
                    ) {
                        viewModel.select(model)
                    }
                    .buttonStyle(ZenPrimaryButtonStyle(minWidth: 60))
                    .disabled(selectionProfile == nil)
                }
                ZenIconButton(
                    systemImage: "trash",
                    label: "Remove \(model.displayName)",
                    isDanger: true
                ) {
                    modelPendingRemoval = model
                }
            }
        } else {
            Button {
                viewModel.download(model)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(ZenSecondaryButtonStyle())
            .disabled(recommendation.level == .insufficientStorage)
        }
    }
}

private struct InstantRefineScreen: View {
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
                ZenRow(
                    title: "Detect stable phrases",
                    subtitle:
                        "Detect natural pauses for commit-on-pause. While listening, ZenBar stays focused on the live waveform and controls."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.livePreviewEnabled },
                            set: viewModel.setLivePreviewEnabled
                        ),
                        label: "Stable phrase detection"
                    )
                }
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
                        .font(ZenDesign.Typography.captionStrong)
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

private struct OverviewScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var appState: AppState
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var insightsViewModel: InsightsViewModel
    let startDictation: () -> Void
    let replaySetup: () -> Void
    let navigate: (OverviewDestination) -> Void

    var body: some View {
        ZenScreen(
            title: "Home",
            subtitle:
                "Everything runs on this Mac. Nothing to sign into, nothing to sync."
        ) {
            homeGrid
        }
        .onAppear {
            viewModel.refreshSystemStatus()
            historyViewModel.refresh()
            insightsViewModel.refresh()
        }
    }

    private var homeGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                readyPanel(
                    minHeight: historyViewModel.recoveryCount > 0
                        ? 312
                        : nil
                )
                    .frame(minWidth: 430, maxWidth: .infinity)
                homeSideColumn
                    .frame(width: 278)
            }

            VStack(spacing: 16) {
                readyPanel()
                homeSideColumn
            }
        }
    }

    private var homeSideColumn: some View {
        VStack(spacing: 12) {
            permissionsPanel
            recentActivityPanel
            if historyViewModel.recoveryCount > 0 {
                recoveryNote
            }
        }
    }

    private func readyPanel(minHeight: CGFloat? = nil) -> some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(ZenDesign.Semantic.success)
                        .frame(width: 8, height: 8)
                    Text("Ready to dictate")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                }

                VStack(spacing: 0) {
                    readyFact(
                        "Shortcut",
                        value: viewModel.currentShortcut.displayName,
                        usesKeycap: true
                    )
                    readyFact("Microphone", value: microphoneDisplayName)
                    readyFact(
                        "Language",
                        value: appState.languageProfile.displayName
                    )
                    readyFact("Model", value: modelDisplayName)
                }
                .padding(.top, 12)

                HStack(spacing: 10) {
                    Button(action: startDictation) {
                        Label("Start dictating", systemImage: "mic")
                            .fixedSize()
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())

                    Button("Replay setup guide", action: replaySetup)
                        .buttonStyle(ZenSecondaryButtonStyle())
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(minHeight: minHeight, alignment: .topLeading)
        }
    }

    private func readyFact(
        _ label: String,
        value: String,
        usesKeycap: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(ZenDesign.Typography.body)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
            Spacer()
            if usesKeycap {
                ZenKbdGroup(combo: value)
            } else {
                Text(value)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ZenDesign.Semantic.border)
                .frame(height: 1)
        }
    }

    private var permissionsPanel: some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: 0) {
                miniTitle("Permissions")
                permissionRow(
                    icon: "mic",
                    title: "Microphone",
                    granted: viewModel.microphoneStatus == .allowed
                )
                permissionRow(
                    icon: "gearshape",
                    title: "Accessibility",
                    granted: viewModel.accessibilityStatus == .allowed
                )
            }
            .padding(.bottom, 8)
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        granted: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .frame(width: 16)
            Text(title)
                .font(ZenDesign.Typography.body)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Spacer()
            ZenBadge(
                text: granted ? "Granted" : "Needs access",
                kind: granted ? .success : .warn,
                systemImage: granted ? "checkmark" : nil
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private var recentActivityPanel: some View {
        let recent = Array(historyViewModel.records.prefix(3))
        return ZenPanel {
            VStack(alignment: .leading, spacing: 0) {
                miniTitle("Recent activity")
                if recent.isEmpty {
                    Text("Your latest dictations will appear here.")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                } else {
                    ForEach(recent) { record in
                        Button {
                            navigate(.history)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                                    .frame(width: 24, height: 24)
                                    .background {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(
                                                ZenDesign.Semantic
                                                    .surfaceRaised
                                            )
                                    }
                                Text(record.targetAppName ?? "Unknown app")
                                    .font(ZenDesign.Typography.body)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                    .lineLimit(1)
                                Spacer()
                                Text(
                                    record.startedAt.formatted(
                                        .relative(presentation: .named)
                                    )
                                )
                                .font(
                                    .system(
                                        size: 11,
                                        design: .serif
                                    )
                                )
                                .italic()
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                                .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func miniTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 7)
    }

    private var recoveryNote: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
            Text("\(historyViewModel.recoveryCount) items waiting in Recovery")
                .font(ZenDesign.Typography.captionStrong)
                .lineLimit(1)
            Spacer()
            Button("Review") {
                navigate(.history)
            }
            .buttonStyle(.plain)
            .font(ZenDesign.Typography.captionStrong)
        }
        .foregroundStyle(ZenDesign.Semantic.accentStrong)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background {
            RoundedRectangle(cornerRadius: ZenDesign.Radius.medium)
                .fill(ZenDesign.Semantic.accentMuted)
                .overlay {
                    RoundedRectangle(cornerRadius: ZenDesign.Radius.medium)
                        .strokeBorder(
                            ZenDesign.Semantic.accent.opacity(0.18)
                        )
                }
        }
    }

    private var microphoneDisplayName: String {
        viewModel.selectedMicrophoneName
    }

    private var modelDisplayName: String {
        guard let selectedModelID = modelManagerViewModel.selectedModelID,
              let model = modelManagerViewModel.models.first(
                where: { $0.id == selectedModelID }
              ) else {
            return viewModel.isLocalModelReady
                ? "Verified local model"
                : "Not installed"
        }
        return model.displayName
    }

    private var subtitleText: String {
        switch appState.phase {
        case .idle:
            return viewModel.isLocalModelReady
                ? "Everything runs locally and is ready to dictate."
                : "Almost there — one download and you're ready to dictate."
        case .listening:
            return "Listening now — press \(viewModel.currentShortcut.displayName) again to finish."
        case .transcribing:
            return "Transcribing locally…"
        case .inserting:
            return "Inserting your text…"
        case .success:
            return "Dictation inserted. Ready for the next one."
        case .error(let message):
            return message
        }
    }

    // MARK: status

    private var statusPanel: some View {
        ZenPanel {
            clickableRow(destination: .models) {
                ZenRow(
                    icon: "cpu",
                    title: "Speech model",
                    subtitle: modelSubtitle
                ) {
                    if viewModel.isLocalModelReady {
                        ZenBadge(
                            text: "Ready", kind: .success, showsDot: true
                        )
                    } else {
                        ZenBadge(text: "Install", kind: .warn)
                    }
                    chevron
                }
            }
            ZenPanelDivider()
            clickableRow(destination: .audio) {
                ZenRow(
                    icon: "mic",
                    title: "Microphone",
                    subtitle: microphoneSubtitle
                ) {
                    if viewModel.microphoneStatus == .allowed {
                        ZenBadge(
                            text: "Connected", kind: .success, showsDot: true
                        )
                    } else {
                        ZenBadge(
                            text: viewModel.microphoneStatus.title,
                            kind: .warn
                        )
                    }
                    chevron
                }
            }
            ZenPanelDivider()
            clickableRow(destination: .languages) {
                ZenRow(
                    icon: "globe",
                    title: "Language",
                    subtitle: appState.languageProfile.displayName
                ) {
                    ZenBadge(text: "Local", kind: .success)
                    chevron
                }
            }
            ZenPanelDivider()
            clickableRow(destination: .shortcuts) {
                ZenRow(
                    icon: "command",
                    title: "Shortcut",
                    subtitle: shortcutSubtitle
                ) {
                    ZenKbdGroup(
                        combo: viewModel.currentShortcut.displayName
                    )
                    chevron
                }
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
    }

    private func clickableRow<Content: View>(
        destination: OverviewDestination,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            navigate(destination)
        } label: {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: dictate anywhere

    private var dictateAnywhere: some View {
        ZenPanel {
            ZenRow(
                title: "Dictate anywhere",
                subtitle:
                    "Place the cursor in any text field, press the shortcut, speak, press again to insert."
            ) {
                ZenKbdGroup(
                    combo: viewModel.currentShortcut.displayName
                )
                if viewModel.holdToDictateEnabled {
                    ZenBadge(
                        text: "Hold \(viewModel.holdKey.displayName)",
                        kind: .accent
                    )
                }
            }
        }
    }

    // MARK: activity

    private var activitySection: some View {
        ZenSection(
            title: "Your activity",
            caption: activityCaption
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                HStack(spacing: ZenDesign.Spacing.sm) {
                    ZenStatTile(
                        value:
                            insightsViewModel.snapshot.totalWordCount
                                .formatted(),
                        label: "words dictated"
                    )
                    ZenStatTile(
                        value: averageSpeed,
                        label: "weighted WPM"
                    )
                    ZenStatTile(
                        value:
                            "\(insightsViewModel.snapshot.currentStreakDays) day"
                            + (
                                insightsViewModel.snapshot
                                    .currentStreakDays == 1 ? "" : "s"
                            ),
                        label: "current streak"
                    )
                    ZenStatTile(
                        value:
                            insightsViewModel.snapshot.dictationCount
                                .formatted(),
                        label: "dictations"
                    )
                }
                HStack {
                    Spacer()
                    Button("All insights") {
                        navigate(.insights)
                    }
                    .buttonStyle(.plain)
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.accent)
                }
            }
        }
    }

    private var activityCaption: String {
        historyViewModel.historyEnabled
            ? "Computed on this Mac from encrypted History"
            : "History is paused — totals stay local"
    }

    private var averageSpeed: String {
        let speed = insightsViewModel.snapshot.weightedWordsPerMinute
        return speed > 0 ? "\(Int(speed.rounded()))" : "—"
    }

    // MARK: recent

    @ViewBuilder
    private var recentDictations: some View {
        let recent = Array(historyViewModel.records.prefix(3))
        if !recent.isEmpty {
            ZenSection(title: "Recent dictations") {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    ZenPanel {
                        ForEach(recent) { record in
                            if record.id != recent.first?.id {
                                ZenPanelDivider()
                            }
                            clickableRow(destination: .history) {
                                ZenRow(
                                    icon: "text.bubble",
                                    title: recentTitle(record),
                                    subtitle: recentTranscript(record)
                                ) {
                                    Text("\(record.wordCount) words")
                                        .font(ZenDesign.Typography.caption)
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textTertiary
                                        )
                                }
                            }
                        }
                    }
                    HStack {
                        Spacer()
                        Button("View history") {
                            navigate(.history)
                        }
                        .buttonStyle(.plain)
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.accent)
                    }
                }
            }
        }
    }

    private func recentTitle(_ record: DictationRecord) -> String {
        let app = record.targetAppName ?? "Unknown app"
        let time = record.startedAt.formatted(
            .relative(presentation: .named)
        )
        return "\(app) · \(time)"
    }

    private func recentTranscript(_ record: DictationRecord) -> String {
        let text = record.finalTranscript
            ?? record.rawTranscript
            ?? "Transcript unavailable"
        return text.count > 110
            ? String(text.prefix(110)) + "…"
            : text
    }

    // MARK: derived status text

    private var modelSubtitle: String {
        guard let selectedModelID = modelManagerViewModel.selectedModelID,
              let model = modelManagerViewModel.models.first(
                where: { $0.id == selectedModelID }
              ) else {
            return viewModel.isLocalModelReady
                ? "Local model — verified and loaded"
                : "No model installed yet — download one in Models"
        }
        return "\(model.displayName) — verified and loaded"
    }

    private var microphoneSubtitle: String {
        let name = viewModel.selectedMicrophoneUID == nil
            ? "System default"
            : viewModel.selectedMicrophoneName
        return viewModel.selectedMicrophoneUID == nil
            ? "\(viewModel.selectedMicrophoneName) — following system default"
            : name
    }

    private var shortcutSubtitle: String {
        viewModel.holdToDictateEnabled
            ? "Press to toggle, or hold \(viewModel.holdKey.displayName)"
            : "Press once to start, again to insert"
    }
}
private struct HistoryScreen: View {
    @ObservedObject var viewModel: HistoryViewModel
    @State private var confirmsDeleteAll = false
    @State private var spellingRecord: DictationRecord?

    var body: some View {
        ZenScreen(
            title: "History",
            subtitle: "Every dictation, kept on this Mac."
        ) {
            if !viewModel.hasMadeHistoryChoice {
                consentCard
            } else {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    ZenTabStrip(
                        items: [
                            .init(tab: HistoryViewModel.Scope.all,
                                  title: "All dictations"),
                            .init(tab: HistoryViewModel.Scope.recovery,
                                  title: "Recovery Inbox",
                                  badge: viewModel.recoveryCount)
                        ],
                        selection: $viewModel.scope
                    )

                    HStack(spacing: ZenDesign.Spacing.sm) {
                        ZenSearchField(
                            placeholder: "Search transcripts or apps…",
                            text: $viewModel.searchText
                        )
                        .frame(maxWidth: .infinity)
                        Button("Delete All") {
                            confirmsDeleteAll = true
                        }
                        .buttonStyle(ZenDestructiveButtonStyle())
                        .disabled(viewModel.scopedRecords.isEmpty)
                    }

                    if let error = viewModel.errorMessage {
                        ZenBanner(
                            kind: .danger,
                            icon: "exclamationmark.triangle",
                            text: error
                        )
                    }

                    if viewModel.filteredRecords.isEmpty {
                        emptyState
                    } else {
                        recordGroups
                    }

                    if viewModel.scope == .recovery {
                        ZenBanner(
                            kind: .info,
                            icon: "info.circle",
                            text:
                                "Temporary audio is deleted after every attempt — recovery keeps encrypted text partials, and audio only if you allowed it in Privacy."
                        )
                    }
                }
            }
        }
        .alert(
            deleteConfirmationTitle,
            isPresented: $confirmsDeleteAll
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                viewModel.deleteAll(in: viewModel.scope)
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .sheet(item: $spellingRecord) { record in
            SpellingCorrectionSheet(
                record: record,
                scope: viewModel.correctionScope(for: record),
                suggestions: viewModel.spellingSuggestions(for: record),
                save: { source, replacement in
                    let saved = viewModel.addSpellingCorrection(
                        source: source,
                        replacement: replacement,
                        for: record
                    )
                    if saved {
                        spellingRecord = nil
                    }
                    return saved
                },
                cancel: {
                    spellingRecord = nil
                }
            )
        }
    }

    private var deleteConfirmationTitle: String {
        switch viewModel.scope {
        case .all:
            return "Delete all dictations?"
        case .recovery:
            return "Delete the Recovery Inbox?"
        }
    }

    private var deleteConfirmationMessage: String {
        switch viewModel.scope {
        case .all:
            return
                "This permanently deletes \(viewModel.standardRecords.count) saved dictations. Recovery Inbox items are kept."
        case .recovery:
            return
                "This permanently deletes \(viewModel.recoveryRecords.count) Recovery Inbox items and any retained recovery audio. Saved dictations are kept."
        }
    }

    private var recordGroups: some View {
        ForEach(groupedRecords, id: \.title) { group in
            ZenSection(title: group.title) {
                ZenPanel {
                    ForEach(
                        Array(group.records.enumerated()),
                        id: \.element.id
                    ) { index, record in
                        if index > 0 {
                            ZenPanelDivider()
                        }
                        HistoryRecordRow(
                            record: record,
                            copy: { viewModel.copy(record) },
                            retry: { viewModel.retry(record) },
                            correctSpelling: {
                                spellingRecord = record
                            },
                            setCategory: {
                                viewModel.setCategory($0, for: record)
                            },
                            delete: { viewModel.delete(record) }
                        )
                    }
                }
            }
        }
    }

    private var consentCard: some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 15) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.accent)
                        .frame(width: 46, height: 46)
                        .background {
                            RoundedRectangle(
                                cornerRadius: 12, style: .continuous
                            )
                            .fill(ZenDesign.Semantic.accentMuted)
                        }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Keep a private local history?")
                            .font(ZenDesign.Typography.sectionTitle)
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(
                            "ZenVoice can save encrypted transcripts so an interrupted paste never loses your words."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ConsentFact(
                        icon: "key.fill",
                        text: "Transcript text is encrypted with a Keychain-protected key."
                    )
                    ConsentFact(
                        icon: "internaldrive",
                        text: "History stays on this Mac and is never synced."
                    )
                    ConsentFact(
                        icon: "waveform.slash",
                        text: "Successful audio is deleted after transcription."
                    )
                }

                HStack {
                    Button("Not Now") {
                        viewModel.declineHistory()
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                    Spacer()
                    Button("Enable Local History") {
                        viewModel.enableHistory()
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                }
            }
            .padding(ZenDesign.Spacing.lg)
        }
    }

    private var emptyState: some View {
        ZenPanel {
            VStack(spacing: 8) {
                Image(
                    systemName: viewModel.scope == .recovery
                        ? "checkmark.circle" : "text.badge.checkmark"
                )
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                Text(
                    viewModel.scope == .recovery
                        ? "Recovery Inbox is empty"
                        : viewModel.historyEnabled
                            ? "Your next dictation will appear here"
                            : "History saving is paused"
                )
                .font(ZenDesign.Typography.sectionTitle)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(
                    viewModel.scope == .recovery
                        ? "When a dictation fails, anything usable lands here with Copy, Retry, and Delete."
                        : viewModel.historyEnabled
                            ? "Place the cursor anywhere, press your shortcut, and speak."
                            : "Existing records remain local until you delete them."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ZenDesign.Spacing.xxl)
        }
    }

    private var groupedRecords:
        [(title: String, records: [ZenVoiceStorage.DictationRecord])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: viewModel.filteredRecords) { record in
            calendar.startOfDay(for: record.startedAt)
        }
        return groups.keys.sorted(by: >).map { date in
            let title: String
            if calendar.isDateInToday(date) {
                title = "Today"
            } else if calendar.isDateInYesterday(date) {
                title = "Yesterday"
            } else {
                title = date.formatted(
                    .dateTime.weekday(.wide).month(.abbreviated).day()
                )
            }
            return (
                title: title,
                records: groups[date, default: []].sorted {
                    $0.startedAt > $1.startedAt
                }
            )
        }
    }
}

private struct SpellingCorrectionSheet: View {
    let record: DictationRecord
    let scope: CorrectionLanguageScope
    let suggestions: [CorrectionSuggestion]
    let save: (String, String) -> Bool
    let cancel: () -> Void

    @State private var source = ""
    @State private var replacement = ""
    @State private var dismissedSuggestionIDs = Set<String>()
    @State private var showsSaveError = false

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Correct spelling")
                        .font(ZenDesign.Typography.pageTitle)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        "Approve only the spelling you want ZenVoice to remember."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                Spacer()
                ZenBadge(
                    text: scope.displayName,
                    kind: scope == .hinglish ? .accent : .neutral
                )
            }

            ZenPanel {
                Text(record.finalTranscript ?? "")
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(ZenDesign.Spacing.md)
            }

            if !visibleSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Possible matches")
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    ForEach(visibleSuggestions) { suggestion in
                        HStack(spacing: 8) {
                            Text("“\(suggestion.source)”")
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            Image(systemName: "arrow.right")
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                            Text(suggestion.replacement)
                                .font(ZenDesign.Typography.bodyStrong)
                            Spacer()
                            Button("Accept") {
                                showsSaveError = !save(
                                    suggestion.source,
                                    suggestion.replacement
                                )
                            }
                            .buttonStyle(ZenSecondaryButtonStyle())
                            ZenIconButton(
                                systemImage: "xmark",
                                label:
                                    "Dismiss suggestion \(suggestion.source)"
                            ) {
                                dismissedSuggestionIDs.insert(
                                    suggestion.id
                                )
                            }
                        }
                        .font(ZenDesign.Typography.body)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                spellingField(
                    title: "Incorrect spelling",
                    placeholder: "bild",
                    text: $source
                )
                Image(systemName: "arrow.right")
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .padding(.bottom, 9)
                spellingField(
                    title: "Preferred spelling",
                    placeholder: "build",
                    text: $replacement
                )
            }

            if showsSaveError {
                Text(
                    "This rule could not be saved. Check that the incorrect spelling appears in the transcript and does not already have a rule."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.danger)
            }

            HStack {
                Button("Cancel", action: cancel)
                    .buttonStyle(ZenSecondaryButtonStyle())
                Spacer()
                Button("Save correction") {
                    showsSaveError = !save(source, replacement)
                }
                .buttonStyle(ZenPrimaryButtonStyle())
                .disabled(
                    source.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                        || replacement.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            }
        }
        .padding(ZenDesign.Spacing.lg)
        .frame(width: 560)
    }

    private var visibleSuggestions: [CorrectionSuggestion] {
        suggestions.filter {
            !dismissedSuggestionIDs.contains($0.id)
        }
    }

    private func spellingField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct InsightsScreen: View {
    @ObservedObject var viewModel: InsightsViewModel
    @State private var showsShareCard = false

    var body: some View {
        ZenScreen(
            title: "Insights",
            subtitle:
                "How you dictate, computed on this Mac. Never uploaded."
        ) {
            if let error = viewModel.errorMessage {
                ZenBanner(
                    kind: .danger,
                    icon: "exclamationmark.triangle",
                    text: error
                )
            }

            if viewModel.snapshot.dictationCount == 0 {
                emptyState
            } else {
                metrics
                activitySection

                HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
                    appsSection
                    categoriesSection
                }

                HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
                    ZenBanner(
                        kind: .info,
                        icon: "lock",
                        text:
                            "Insights are calculated locally. ZenVoice stores app identity — never window titles, URLs, recipients, or surrounding text."
                    )
                    Button {
                        showsShareCard = true
                    } label: {
                        Label(
                            "Share highlights",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .buttonStyle(ZenSecondaryButtonStyle(height: 60))
                }
            }
        }
        .onAppear(perform: viewModel.refresh)
        .sheet(isPresented: $showsShareCard) {
            ShareHighlightSheet(summary: shareSummary)
        }
    }

    // MARK: stat tiles

    private var metrics: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            ZenStatTile(
                value: viewModel.snapshot.totalWordCount.formatted(),
                label: "words dictated"
            )
            ZenStatTile(
                value:
                    "\(Int(viewModel.snapshot.weightedWordsPerMinute.rounded()))",
                label: "weighted WPM"
            )
            ZenStatTile(
                value:
                    "\(viewModel.snapshot.currentStreakDays) day"
                    + (viewModel.snapshot.currentStreakDays == 1 ? "" : "s"),
                label: "streak",
                detail: "best: \(viewModel.snapshot.longestStreakDays)"
            )
            ZenStatTile(
                value: viewModel.snapshot.dictationCount.formatted(),
                label: "dictations"
            )
        }
    }

    // MARK: words per day

    private var activitySection: some View {
        ZenSection(
            title: "Words per day",
            caption: busiestCaption
        ) {
            ZenPanel {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(viewModel.snapshot.recentActivity) { day in
                        VStack(spacing: 6) {
                            RoundedRectangle(
                                cornerRadius: 4, style: .continuous
                            )
                            .fill(
                                day.wordCount == maxActivityWords
                                    && day.wordCount > 0
                                    ? ZenDesign.Semantic.accent
                                    : day.wordCount > 0
                                        ? ZenDesign.Semantic.accentMuted
                                        : ZenDesign.Semantic.surfaceRaised
                            )
                            .frame(
                                height: activityHeight(for: day.wordCount)
                            )
                            .frame(maxHeight: 96, alignment: .bottom)
                            .accessibilityLabel(
                                "\(day.date.formatted(.dateTime.weekday(.wide))): \(day.wordCount) words"
                            )
                            Text(
                                day.date.formatted(
                                    .dateTime.weekday(.abbreviated)
                                )
                            )
                            .font(.system(size: 10))
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(ZenDesign.Spacing.md)
                .frame(height: 140, alignment: .bottom)
            }
        }
    }

    private var busiestCaption: String {
        guard
            let top = viewModel.snapshot.recentActivity
                .max(by: { $0.wordCount < $1.wordCount }),
            top.wordCount > 0
        else {
            return "\(viewModel.snapshot.dictationCount) dictations total"
        }
        return "Busiest: \(top.date.formatted(.dateTime.weekday(.wide))) · \(top.wordCount.formatted()) words"
    }

    // MARK: apps & categories

    private var appsSection: some View {
        ZenSection(title: "Where you dictate") {
            ZenPanel {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.snapshot.topApplications.isEmpty {
                        Text("No application context has been saved yet.")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                            .padding(ZenDesign.Spacing.md)
                    } else {
                        ForEach(
                            viewModel.snapshot.topApplications
                        ) { app in
                            ZenMeterRow(
                                label: app.displayName,
                                percent: percentOfWords(app.wordCount)
                            )
                        }
                        .padding(.horizontal, ZenDesign.Spacing.md)
                    }
                }
                .padding(.vertical, ZenDesign.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var categoriesSection: some View {
        ZenSection(title: "What kind of work") {
            ZenPanel {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.snapshot.categories) { insight in
                        ZenMeterRow(
                            label: insight.category.displayName,
                            percent: percentOfWords(insight.wordCount)
                        )
                    }
                    .padding(.horizontal, ZenDesign.Spacing.md)
                }
                .padding(.vertical, ZenDesign.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func percentOfWords(_ count: Int) -> Int {
        let total = max(1, viewModel.snapshot.totalWordCount)
        return Int(
            (Double(count) / Double(total) * 100).rounded()
        )
    }

    // MARK: empty

    private var emptyState: some View {
        ZenPanel {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                Text("Your local insights will appear here")
                    .font(ZenDesign.Typography.sectionTitle)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(
                    "Save a completed dictation to begin tracking words, speed, streaks, apps, and categories."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ZenDesign.Spacing.xxl)
        }
    }

    private var shareSummary: ShareCardSummary {
        ShareCardSummary(
            totalWordCount: viewModel.snapshot.totalWordCount,
            weightedWordsPerMinute:
                Int(viewModel.snapshot.weightedWordsPerMinute.rounded()),
            currentStreakDays: viewModel.snapshot.currentStreakDays,
            distinctApplicationCount:
                viewModel.snapshot.distinctApplicationCount
        )
    }

    private var maxActivityWords: Int {
        viewModel.snapshot.recentActivity.map(\.wordCount).max() ?? 0
    }

    private func activityHeight(for wordCount: Int) -> CGFloat {
        let maximum = max(1, maxActivityWords)
        guard wordCount > 0 else { return 4 }
        return 12 + 84 * CGFloat(wordCount) / CGFloat(maximum)
    }
}

private struct VoiceProfileScreen: View {
    @ObservedObject var viewModel: VoiceProfileViewModel
    @State private var heardPhrase = ""
    @State private var replacementPhrase = ""
    @State private var correctionScope: CorrectionLanguageScope =
        LanguagePreferences.load() == .hinglish ? .hinglish : .all
    @State private var confirmsDeleteAllRules = false

    var body: some View {
        ZenScreen(
            title: "Voice Profile",
            subtitle:
                "ZenVoice learns the words you correct — nothing else."
        ) {
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
                        HStack(spacing: 8) {
                            Text("“\(rule.source)”")
                                .font(ZenDesign.Typography.body)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
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
                                kind: rule.languageScope == .hinglish
                                    ? .accent : .neutral
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

                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("When I say")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                        correctionField(
                            placeholder: "zen pens", text: $heardPhrase
                        )
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .padding(.bottom, 9)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Write")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                        correctionField(
                            placeholder: "ZenPense",
                            text: $replacementPhrase
                        )
                    }
                    Button("Add rule") {
                        if viewModel.addRule(
                            source: heardPhrase,
                            replacement: replacementPhrase,
                            languageScope: correctionScope
                        ) {
                            heardPhrase = ""
                            replacementPhrase = ""
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
                    Picker("Language scope", selection: $correctionScope) {
                        ForEach(CorrectionLanguageScope.allCases) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 125)
                    Spacer()
                    Button("Delete All") {
                        confirmsDeleteAllRules = true
                    }
                    .buttonStyle(ZenDestructiveButtonStyle())
                    .disabled(
                        viewModel.snapshot.correctionRules.isEmpty
                    )
                }
                .padding(ZenDesign.Spacing.md)
            }
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
            .frame(width: 150, height: 30)
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
                                GridItem(.adaptive(minimum: 104), spacing: 8)
                            ],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(
                                viewModel.snapshot.topWords
                            ) { item in
                                HStack(spacing: 6) {
                                    Text(item.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.9)
                                    Text("\(item.count)")
                                        .foregroundStyle(
                                            ZenDesign.Semantic.accent
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
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(
                                viewModel.snapshot.catchPhrases
                            ) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: "quote.opening")
                                        .font(.system(size: 10))
                                        .foregroundStyle(
                                            ZenDesign.Semantic.accent
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
        Text(
            viewModel.analyzesHistory
                ? "More saved dictations are needed."
                : "Pattern analysis is paused."
        )
        .font(ZenDesign.Typography.caption)
        .foregroundStyle(ZenDesign.Semantic.textTertiary)
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

private struct ShortcutsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZenScreen(
            title: "Shortcuts",
            subtitle:
                "Global shortcuts work in any app. Change them anytime."
        ) {
            dictationSection
            zenBarSection

            ZenBanner(
                kind: .info,
                icon: "lightbulb",
                text:
                    "A two-modifier shortcut is less likely to conflict with other apps. Select Change, press one key with Command, Control, Option, or Shift — Escape cancels. Your choice stays on this Mac."
            )
        }
    }

    // MARK: dictation shortcuts

    private var dictationSection: some View {
        ZenSection(title: "Dictation") {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                ZenPanel {
                    ZenRow(
                        icon: "mic",
                        title: "Start / stop dictation",
                        subtitle: "Press once to start, again to transcribe and insert"
                    ) {
                        ShortcutCaptureButton(
                            displayName:
                                viewModel.currentShortcut.displayName,
                            isCapturing: viewModel.isCapturingShortcut,
                            action: {
                                if viewModel.isCapturingShortcut {
                                    viewModel.cancelShortcutCapture()
                                } else {
                                    viewModel.beginShortcutCapture()
                                }
                            }
                        )
                        ZenIconButton(
                            systemImage: "arrow.counterclockwise",
                            label: "Reset dictation shortcut"
                        ) {
                            viewModel.resetShortcut()
                        }
                    }
                    ZenPanelDivider()
                    ZenRow(
                        icon: "eye.slash",
                        title: "Private dictation",
                        subtitle: "Dictate without saving history, insights, or recovery audio"
                    ) {
                        ShortcutCaptureButton(
                            displayName:
                                viewModel.privateModeShortcut.displayName,
                            isCapturing:
                                viewModel.isCapturingPrivateModeShortcut,
                            action: {
                                if viewModel
                                    .isCapturingPrivateModeShortcut {
                                    viewModel.cancelShortcutCapture()
                                } else {
                                    viewModel.beginShortcutCapture(
                                        for: .privateMode
                                    )
                                }
                            }
                        )
                        ZenIconButton(
                            systemImage: "arrow.counterclockwise",
                            label: "Reset private dictation shortcut"
                        ) {
                            viewModel.resetPrivateModeShortcut()
                        }
                    }
                    ZenPanelDivider()
                    ZenRow(
                        icon: "doc.on.doc",
                        title: "Paste latest dictation",
                        subtitle: "Re-insert the most recent transcript anywhere"
                    ) {
                        ShortcutCaptureButton(
                            displayName:
                                viewModel.pasteLastShortcut.displayName,
                            isCapturing:
                                viewModel.isCapturingPasteLastShortcut,
                            action: {
                                if viewModel
                                    .isCapturingPasteLastShortcut {
                                    viewModel.cancelShortcutCapture()
                                } else {
                                    viewModel.beginShortcutCapture(
                                        for: .pasteLast
                                    )
                                }
                            }
                        )
                        ZenIconButton(
                            systemImage: "arrow.counterclockwise",
                            label: "Reset paste shortcut"
                        ) {
                            viewModel.resetPasteLastShortcut()
                        }
                    }
                    ZenPanelDivider()
                    ZenRow(
                        icon: "hand.tap",
                        title: "Hold to dictate",
                        subtitle:
                            "Hold a modifier, speak, then release to insert"
                    ) {
                        ZenSwitch(
                            isOn: Binding(
                                get: {
                                    viewModel.holdToDictateEnabled
                                },
                                set:
                                    viewModel.setHoldToDictateEnabled
                            ),
                            label: "Hold to dictate"
                        )
                    }
                    if viewModel.holdToDictateEnabled {
                        ZenPanelDivider()
                        ZenRow(
                            title: "Hold key",
                            subtitle:
                                "Select Change, then press the modifier you want to hold"
                        ) {
                            ShortcutCaptureButton(
                                displayName:
                                    viewModel.holdKey.displayName,
                                isCapturing:
                                    viewModel.isCapturingHoldKey,
                                action: {
                                    if viewModel.isCapturingHoldKey {
                                        viewModel.cancelShortcutCapture()
                                    } else {
                                        viewModel.beginHoldKeyCapture()
                                    }
                                }
                            )
                            ZenIconButton(
                                systemImage: "arrow.counterclockwise",
                                label: "Reset hold key"
                            ) {
                                viewModel.resetHoldKey()
                            }
                        }
                    }
                }

                if viewModel.holdToDictateEnabled,
                   viewModel.accessibilityStatus != .allowed {
                    HStack(spacing: ZenDesign.Spacing.sm) {
                        ZenBanner(
                            kind: .danger,
                            icon: "exclamationmark.shield",
                            text:
                                "Allow Accessibility so the hold key works in every app."
                        )
                        Button("Allow Access") {
                            viewModel.requestAccessibilityAccess()
                        }
                        .buttonStyle(ZenSecondaryButtonStyle())
                    }
                }

                if let error = viewModel.shortcutError {
                    ZenBanner(
                        kind: .danger,
                        icon: "exclamationmark.triangle",
                        text: error
                    )
                }
            }
        }
    }

    // MARK: ZenBar behavior

    private var zenBarSection: some View {
        ZenSection(title: "While dictating") {
            ZenPanel {
                ZenRow(
                    icon: "rectangle.bottomthird.inset.filled",
                    title: "Show ZenVoice at all times",
                    subtitle: "When off, the bar appears when dictation starts and hides after your text is inserted"
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.showsZenVoiceAtAllTimes },
                            set: viewModel.setShowsZenVoiceAtAllTimes
                        ),
                        label: "Show ZenVoice at all times"
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "captions.bubble",
                    title: "ZenBar controls",
                    subtitle: "Cancel or finish a dictation from the bar itself — no shortcut needed. Live preview options live in Instant Refine."
                )
            }
        }
    }
}

private struct ShortcutCaptureButton: View {
    let displayName: String
    let isCapturing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isCapturing {
                    Circle()
                        .fill(ZenDesign.Semantic.accent)
                        .frame(width: 7, height: 7)
                    Text("Press keys…")
                    Text("Cancel")
                        .foregroundStyle(
                            ZenDesign.Semantic.textOnAccent.opacity(0.72)
                        )
                } else {
                    Image(systemName: "keyboard")
                    Text(displayName)
                        .font(ZenDesign.Typography.captionStrong)
                    Divider()
                        .frame(height: 16)
                    Text("Change")
                        .foregroundStyle(
                            ZenDesign.Semantic.accent
                        )
                }
            }
            .font(ZenDesign.Typography.button)
            .foregroundStyle(
                isCapturing
                    ? ZenDesign.Semantic.textOnAccent
                    : ZenDesign.Semantic.textPrimary
            )
            .padding(.horizontal, 15)
            .frame(minWidth: 174, minHeight: 44)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    isCapturing
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Component.shortcutBackground
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .strokeBorder(
                        isCapturing
                            ? ZenDesign.Component.focusRing
                            : ZenDesign.Semantic.borderStrong,
                        lineWidth: 1
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isCapturing
                ? "Cancel shortcut capture"
                : "Change shortcut. Current shortcut \(displayName)"
        )
    }
}

private struct PrivacyScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var voiceProfileViewModel:
        VoiceProfileViewModel
    @ObservedObject var modelManagerViewModel:
        ModelManagerViewModel
    @State private var confirmsDeleteRecoveryAudio = false
    @State private var confirmsDeleteTranscripts = false
    @State private var confirmsDeleteRules = false

    var body: some View {
        ZenScreen(
            title: "Privacy",
            subtitle: "What ZenVoice keeps, and where."
        ) {
            dictationPrivacy
            inventory
            permissions

            ZenBanner(
                kind: .success,
                icon: "network.slash",
                text:
                    "Network access is used for one thing: model downloads you explicitly start — each pinned to a revision and SHA-256 verified. Audio, text, rules, and insights never leave this Mac. One-shot context is memory-only and never counted here."
            )
        }
        .onAppear {
            historyViewModel.refresh()
            voiceProfileViewModel.refresh()
            modelManagerViewModel.refresh()
            }
        .alert(
            "Delete all retained recovery audio?",
            isPresented: $confirmsDeleteRecoveryAudio
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Audio", role: .destructive) {
                historyViewModel.deleteAllRecoveryAudio()
            }
        } message: {
            Text(
                "Failed dictations will no longer be retryable, but saved partial transcript text remains in encrypted History."
            )
        }
        .alert(
            "Delete all history?",
            isPresented: $confirmsDeleteTranscripts
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                historyViewModel.deleteAll()
            }
        } message: {
            Text(
                "This removes every saved transcript and recovery recording from this Mac."
            )
        }
        .alert(
            "Delete all correction rules?",
            isPresented: $confirmsDeleteRules
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Rules", role: .destructive) {
                voiceProfileViewModel.deleteAllRules()
            }
        } message: {
            Text(
                "This permanently removes every encrypted personal replacement rule."
            )
        }
    }

    // MARK: dictation privacy

    private var dictationPrivacy: some View {
        ZenSection(title: "Dictation privacy") {
            ZenPanel {
                ZenRow(
                    icon: "clock.arrow.circlepath",
                    title: "Save history",
                    subtitle:
                        "Encrypted locally. Pausing keeps existing records but stops new ones."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { historyViewModel.historyEnabled },
                            set: historyViewModel.setHistoryEnabled
                        ),
                        label: "Save history"
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "waveform",
                    title: "Keep failed audio for 24 hours",
                    subtitle:
                        "Only when no usable transcript was produced, so you can retry."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: {
                                historyViewModel.retainsFailedAudio
                            },
                            set:
                                historyViewModel.setRetainsFailedAudio
                        ),
                        label: "Keep failed audio"
                    )
                    .disabled(!historyViewModel.historyEnabled)
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "eye.slash",
                    title: "Private Dictation mode",
                    subtitle:
                        "While enabled, nothing is saved — no history, no insights, no recovery. Toggle anytime with \(viewModel.privateModeShortcut.displayName)."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: {
                                historyViewModel.privateModeEnabled
                            },
                            set:
                                historyViewModel.setPrivateModeEnabled
                        ),
                        label: "Private Dictation"
                    )
                }
            }
        }
    }

    // MARK: live inventory

    private var inventory: some View {
        ZenSection(
            title: "What's on this Mac right now",
            caption: "Live inventory · ZenVoice \(appVersion)"
        ) {
            ZenPanel {
                ZenRow(
                    icon: "lock",
                    title: "Encrypted transcripts",
                    subtitle:
                        "\(historyViewModel.savedTranscriptCount) records · AES-GCM, key in the macOS Keychain"
                ) {
                    Button("Delete") {
                        confirmsDeleteTranscripts = true
                    }
                    .buttonStyle(.plain)
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.danger)
                    .disabled(historyViewModel.savedTranscriptCount == 0)
                    .opacity(
                        historyViewModel.savedTranscriptCount == 0
                            ? 0.4 : 1
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "tray",
                    title: "Recovery audio",
                    subtitle:
                        "\(historyViewModel.recoveryAudioCount) clips · kept at most 24 hours, only if you allowed it"
                ) {
                    Button("Delete") {
                        confirmsDeleteRecoveryAudio = true
                    }
                    .buttonStyle(.plain)
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.danger)
                    .disabled(historyViewModel.recoveryAudioCount == 0)
                    .opacity(
                        historyViewModel.recoveryAudioCount == 0
                            ? 0.4 : 1
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "pencil",
                    title: "Correction rules",
                    subtitle:
                        "\(voiceProfileViewModel.snapshot.correctionRules.count) rules · encrypted with the same key"
                ) {
                    Button("Delete") {
                        confirmsDeleteRules = true
                    }
                    .buttonStyle(.plain)
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.danger)
                    .disabled(
                        voiceProfileViewModel.snapshot
                            .correctionRules.isEmpty
                    )
                    .opacity(
                        voiceProfileViewModel.snapshot
                            .correctionRules.isEmpty ? 0.4 : 1
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "cpu",
                    title: "Local models",
                    subtitle:
                        "\(modelManagerViewModel.installedModelIDs.count) speech — verified weights, removable in Models"
                )
            }
        }
    }

    // MARK: permissions

    private var permissions: some View {
        ZenSection(title: "macOS permissions") {
            ZenPanel {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "Used only while a dictation is active.",
                    status: viewModel.microphoneStatus,
                    action: viewModel.requestMicrophoneAccess
                )
                ZenPanelDivider()
                PermissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    detail:
                        "Types the finished text into the active app. Without it, transcripts are copied to the clipboard instead.",
                    status: viewModel.accessibilityStatus,
                    action: viewModel.requestAccessibilityAccess
                )
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
    }
}

private struct HistoryRecordRow: View {
    let record: ZenVoiceStorage.DictationRecord
    let copy: () -> Void
    let retry: () -> Void
    let correctSpelling: () -> Void
    let setCategory: (DictationCategory) -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(iconTint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    if let appName = record.targetAppName {
                        Text(appName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                    }
                    if record.isPartial {
                        Text("Partial")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ZenDesign.Semantic.accent)
                    }
                    Text(record.category.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.accent)
                }

                Text(transcript)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        record.status == .failed
                            ? ZenDesign.Semantic.textSecondary
                            : ZenDesign.Semantic.textPrimary
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if record.finalTranscript != nil {
                    Text(
                        "\(record.wordCount) words · "
                            + "\(Int(record.wordsPerMinute.rounded())) WPM"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 7) {
                if record.status == .failed,
                   record.recoveryAudioURL != nil {
                    Button("Retry", action: retry)
                        .buttonStyle(ZenSecondaryButtonStyle())
                }

                if record.finalTranscript != nil {
                    Button("Copy", action: copy)
                        .buttonStyle(ZenSecondaryButtonStyle())
                }

                Menu {
                    if record.finalTranscript != nil {
                        Button(
                            "Correct spelling…",
                            systemImage: "textformat.abc"
                        ) {
                            correctSpelling()
                        }
                    }
                    Menu("Category") {
                        ForEach(DictationCategory.allCases) { category in
                            Button {
                                setCategory(category)
                            } label: {
                                if record.category == category {
                                    Label(
                                        category.displayName,
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(category.displayName)
                                }
                            }
                        }
                    }
                    Button("Delete", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 26, height: 26)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(ZenDesign.Spacing.md)
    }

    private var transcript: String {
        if let transcript = record.finalTranscript {
            return transcript
        }
        return record.errorMessage ?? "This dictation did not finish."
    }

    private var icon: String {
        switch record.status {
        case .failed:
            return "exclamationmark.arrow.triangle.2.circlepath"
        case .inserted:
            return "checkmark"
        case .copiedOnly:
            return "doc.on.doc"
        default:
            return "waveform"
        }
    }

    private var iconTint: Color {
        record.status == .failed
            ? ZenDesign.Semantic.danger
            : ZenDesign.Semantic.accent
    }
}

private extension DictationCategory {
    var icon: String {
        switch self {
        case .documents: "doc.text"
        case .email: "envelope"
        case .workMessages: "person.2"
        case .personalMessages: "message"
        case .aiPrompts: "sparkles"
        case .notes: "note.text"
        case .development: "chevron.left.forwardslash.chevron.right"
        case .other: "square.grid.2x2"
        }
    }
}

private struct ConsentFact: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.success)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }
}

private struct PrivacyToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(ZenDesign.Semantic.accent)
        }
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(ZenDesign.Semantic.danger)
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.small,
                style: .continuous
            )
            .fill(ZenDesign.Semantic.danger.opacity(0.10))
        }
    }
}

private struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.lowercased().capitalized)
                .font(ZenDesign.Typography.pageContext)
                .foregroundStyle(ZenDesign.Semantic.accent)
            Text(title)
                .font(ZenDesign.Typography.pageTitle)
                .tracking(-0.25)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Text(subtitle)
                .font(ZenDesign.Typography.body)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ZenCard<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(
        padding: CGFloat = ZenDesign.Spacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        ZenDesign.Component.cardBorder,
                        lineWidth: 1
                    )
                }
            }
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    var status: String? = nil
    var statusIsPositive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(ZenDesign.Typography.captionStrong)
                .tracking(0.2)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    valueLabel
                        .fixedSize(horizontal: true, vertical: false)
                    statusPill
                }
                VStack(alignment: .leading, spacing: 5) {
                    valueLabel
                    statusPill
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 96)
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
                .strokeBorder(ZenDesign.Component.cardBorder)
            }
        }
    }

    private var valueLabel: some View {
        Text(value)
            .font(ZenDesign.Typography.sectionTitle)
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    @ViewBuilder
    private var statusPill: some View {
        if let status {
            StatusPill(
                title: status,
                isPositive: statusIsPositive
            )
            .fixedSize()
        }
    }
}

private struct QuickStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                    .fill(ZenDesign.Semantic.accentMuted)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.medium,
                            style: .continuous
                        )
                        .strokeBorder(ZenDesign.Semantic.border)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: SettingsViewModel.PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .fill(ZenDesign.Semantic.accentMuted)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }

            Spacer()

            StatusPill(
                title: status.title,
                isPositive: status == .allowed
            )

            if status != .allowed {
                Button("Open") {
                    action()
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, ZenDesign.Spacing.md)
    }
}

private struct StatusPill: View {
    let title: String
    let isPositive: Bool
    var isNeutral = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(
                    isNeutral
                        ? ZenDesign.Semantic.textTertiary
                        : (
                            isPositive
                                ? ZenDesign.Semantic.success
                                : ZenDesign.Semantic.danger
                        )
                )
                .frame(width: 6, height: 6)
            Text(title)
                .font(ZenDesign.Typography.captionStrong)
        }
        .foregroundStyle(ZenDesign.Semantic.textPrimary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background {
            Capsule()
                .fill(ZenDesign.Semantic.surface)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isNeutral
                                ? ZenDesign.Semantic.textTertiary
                                : (
                                    isPositive
                                        ? ZenDesign.Semantic.success
                                        : ZenDesign.Semantic.textTertiary
                                ),
                            lineWidth: 1
                        )
                }
        }
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

struct ZenSecondaryButtonStyle: ButtonStyle {
    var minWidth: CGFloat? = nil
    var height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .padding(.horizontal, 13)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    configuration.isPressed
                        ? ZenDesign.Semantic.surfaceRaised
                        : ZenDesign.Component.shortcutBackground
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .strokeBorder(
                        ZenDesign.Semantic.borderStrong,
                        lineWidth: 1
                    )
                }
            }
    }
}

struct ZenPrimaryButtonStyle: ButtonStyle {
    var minWidth: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(ZenDesign.Semantic.textOnAccent)
            .padding(.horizontal, 13)
            .frame(minWidth: minWidth)
            .frame(height: 30)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    configuration.isPressed
                        ? ZenDesign.Primitive.gold500
                        : ZenDesign.Semantic.accent
                )
            }
    }
}

struct ZenDestructiveButtonStyle: ButtonStyle {
    var minWidth: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(ZenDesign.Semantic.textOnAccent)
            .padding(.horizontal, 13)
            .frame(minWidth: minWidth)
            .frame(height: 30)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    ZenDesign.Semantic.danger.opacity(
                        configuration.isPressed ? 0.78 : 1
                    )
                )
            }
    }
}

private struct AppProfilesScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var applicationProfileViewModel:
        ApplicationProfileViewModel

    var body: some View {
        ZenScreen(
            title: "App Profiles",
            subtitle:
                "Different apps, different behavior. Overrides apply only where you set them."
        ) {
            applicationProfilesCard

            ZenBanner(
                kind: .info,
                icon: "info.circle",
                text:
                    "Profiles switch automatically the moment you start dictating — ZenVoice checks which app is frontmost, locally."
            )
        }
        .onAppear {
            applicationProfileViewModel.refresh()
        }
    }

    private var applicationProfilesCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Application profiles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(
                            "Automatically choose language, refinement, and local voice commands for a target app."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(
                            ZenDesign.Semantic.textSecondary
                        )
                    }
                    Spacer()
                    Button {
                        applicationProfileViewModel.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                    .accessibilityLabel("Refresh running applications")
                }

                if let error =
                    applicationProfileViewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                PrivacyToggleRow(
                    title: "Enable local voice commands by default",
                    detail:
                        "Interpret spoken layout and punctuation commands locally. Each application profile can override this.",
                    isOn: Binding(
                        get: {
                            viewModel.voiceCommandsEnabled
                        },
                        set:
                            viewModel.setVoiceCommandsEnabled
                    )
                )

                HStack(spacing: 9) {
                    Picker(
                        "Running app",
                        selection:
                            $applicationProfileViewModel
                                .selectedApplicationID
                    ) {
                        if applicationProfileViewModel
                            .runningApplications.isEmpty {
                            Text("No running apps")
                                .tag(String?.none)
                        }
                        ForEach(
                            applicationProfileViewModel
                                .runningApplications
                        ) { application in
                            Text(application.name)
                                .tag(Optional(application.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button("Add profile") {
                        applicationProfileViewModel
                            .addSelectedApplication(
                                languageProfile:
                                    viewModel.languageProfile,
                                refinementMode:
                                    viewModel.instantRefineMode
                            )
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(
                        applicationProfileViewModel
                            .selectedApplicationID == nil
                    )
                }

                if applicationProfileViewModel.profiles.isEmpty {
                    Text(
                        "No profiles yet. Open a target app, refresh this list, then add it."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                } else {
                    ForEach(
                        applicationProfileViewModel.profiles
                    ) { profile in
                        Divider()
                            .overlay(ZenDesign.Semantic.border)
                        applicationProfileRow(profile)
                    }
                }

                Text(
                    "Voice commands: new line, new paragraph, comma, full stop, question mark, and exclamation mark. English commands work with every profile; Hindi, Spanish, French, Mandarin, and Arabic aliases are included."
                )
                .font(.system(size: 11))
                .foregroundStyle(
                    ZenDesign.Semantic.textTertiary
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func applicationProfileRow(
        _ profile: ApplicationProfile
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.applicationName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textPrimary
                        )
                    Text(profile.bundleIdentifier)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                }
                Spacer()
                Button("Remove") {
                    applicationProfileViewModel.remove(profile)
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }

            HStack(spacing: 10) {
                Picker(
                    "Language",
                    selection: Binding(
                        get: { profile.languageProfile },
                        set: {
                            applicationProfileViewModel
                                .setLanguage($0, for: profile)
                        }
                    )
                ) {
                    ForEach(
                        applicationProfileLanguageOptions,
                        id: \.id
                    ) { languageProfile in
                        Text(languageProfile.displayName)
                            .tag(languageProfile)
                    }
                }
                .frame(maxWidth: .infinity)

                Picker(
                    "Refinement",
                    selection: Binding(
                        get: { profile.refinementMode },
                        set: {
                            applicationProfileViewModel
                                .setRefinementMode(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                ) {
                    ForEach(
                        InstantRefineMode.allCases,
                        id: \.self
                    ) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .frame(maxWidth: .infinity)

                Toggle(
                    "Voice commands",
                    isOn: Binding(
                        get: {
                            profile.voiceCommandsEnabled
                        },
                        set: {
                            applicationProfileViewModel
                                .setVoiceCommandsEnabled(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var applicationProfileLanguageOptions:
        [LanguageProfile] {
        [
            .hinglish,
            LanguageProfile(
                inputLanguageCode: LanguageProfile.automaticCode,
                outputMode: .spokenLanguage
            )
        ] + LanguageCatalog.languages.map {
            LanguageProfile(
                inputLanguageCode: $0.code,
                outputMode: .spokenLanguage
            )
        }
    }
}

private struct ZenFAQ: Identifiable {
    let id: Int
    let question: String
    let answer: String
    let tags: String
}

private struct HelpScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var onboardingViewModel: OnboardingViewModel
    let openShortcuts: () -> Void

    @State private var searchText = ""
    @State private var expandedFAQs: Set<Int> = []

    private static let faqs: [ZenFAQ] = [
        ZenFAQ(
            id: 1,
            question: "Does my voice ever leave this Mac?",
            answer:
                "No. Recording, transcription, refinement, history, and insights all run locally. ZenVoice has no accounts, no analytics, and no cloud transcription service. The only network use is downloading models you explicitly request — each one checksum-verified.",
            tags: "privacy cloud offline network"
        ),
        ZenFAQ(
            id: 2,
            question: "How do I start dictating?",
            answer:
                "Place the cursor in any text field and press your dictation shortcut. Speak while ZenBar shows the waveform, then press the shortcut again — the text is inserted where your cursor is. You can also enable hold-to-dictate in Shortcuts.",
            tags: "start dictate shortcut begin how"
        ),
        ZenFAQ(
            id: 3,
            question: "What is Private Dictation?",
            answer:
                "Use the private dictation shortcut to dictate without saving anything: no history entry, no insights, no recovery audio.",
            tags: "private incognito secret history"
        ),
        ZenFAQ(
            id: 4,
            question: "Why does ZenVoice need Accessibility permission?",
            answer:
                "macOS requires it to type the finished text into the active app. Without it, ZenVoice still works — the transcript is copied to your clipboard instead, and you paste manually.",
            tags: "accessibility permission paste insert"
        ),
        ZenFAQ(
            id: 5,
            question: "What happens if transcription fails mid-sentence?",
            answer:
                "Anything usable lands in the Recovery Inbox (History → Recovery) with Copy, Retry, and Delete actions. Temporary audio is deleted after every attempt either way.",
            tags: "fail crash recovery partial lost"
        ),
        ZenFAQ(
            id: 6,
            question: "How does Hinglish mode work?",
            answer:
                "With the verified Hinglish Apex model installed, the Hinglish profile writes Hindi-English speech in Latin script the way you'd type it. Other multilingual models are not offered for Hinglish because they lose code-switched English words.",
            tags: "hinglish hindi language apex latin"
        ),
        ZenFAQ(
            id: 7,
            question: "What does Instant Refine actually change?",
            answer:
                "Clean removes fillers, repeated words, and spoken restarts — never meaning. Agent Prompt formats your speech as a structured prompt. Both options run entirely on this Mac.",
            tags: "refine clean agent rewrite grammar"
        ),
        ZenFAQ(
            id: 8,
            question: "Which model should I download?",
            answer:
                "Open Models — ZenVoice measures this Mac and marks a recommendation. Fast favors latency, Balanced is the best accuracy per second for most machines, High Accuracy is the multilingual pick.",
            tags: "model download recommend fast balanced accuracy"
        ),
        ZenFAQ(
            id: 9,
            question: "Can I correct a word it keeps getting wrong?",
            answer:
                "Yes. Voice Profile → correction rules: add \"what I said → what I meant\". Rules are encrypted and deletable one by one, independent of History.",
            tags: "correction wrong word fix rules dictionary"
        ),
        ZenFAQ(
            id: 10,
            question: "How do I delete everything?",
            answer:
                "Privacy shows a live inventory of everything stored — encrypted transcripts, recovery audio, correction rules, downloaded models — each with its own delete control. There is no hidden data.",
            tags: "delete erase remove data reset"
        )
    ]

    private var filteredFAQs: [ZenFAQ] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return Self.faqs }
        return Self.faqs.filter {
            $0.question.lowercased().contains(query)
                || $0.answer.lowercased().contains(query)
                || $0.tags.contains(query)
        }
    }

    var body: some View {
        ZenScreen(
            title: "Help & FAQ",
            subtitle: "Short answers, no tickets."
        ) {
            quickActions
            cheatSheet
            faqCard
            aboutCard
        }
    }

    private var quickActions: some View {
        ZenCard {
            HStack(spacing: 12) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.accentMuted)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replay the setup guide")
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        "The same steps you saw on first launch — permissions, shortcut, language, model."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                Spacer()
                Button("Replay") {
                    onboardingViewModel.show()
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }
        }
    }

    private var cheatSheet: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Shortcut cheat-sheet")
                    .font(ZenDesign.Typography.sectionTitle)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .padding(.bottom, 10)

                cheatRow(
                    "Start / stop dictation",
                    viewModel.currentShortcut.displayName
                )
                Divider().overlay(ZenDesign.Semantic.border)
                cheatRow(
                    "Private dictation",
                    viewModel.privateModeShortcut.displayName
                )
                Divider().overlay(ZenDesign.Semantic.border)
                cheatRow(
                    "Paste latest dictation",
                    viewModel.pasteLastShortcut.displayName
                )
                Divider().overlay(ZenDesign.Semantic.border)

                HStack {
                    Text("Change any of these")
                        .font(ZenDesign.Typography.body)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    Spacer()
                    Button("Open Shortcuts") {
                        openShortcuts()
                    }
                    .buttonStyle(.plain)
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.accent)
                }
                .frame(minHeight: 40)
            }
        }
    }

    private func cheatRow(_ title: String, _ combo: String) -> some View {
        HStack {
            Text(title)
                .font(ZenDesign.Typography.body)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Spacer()
            Text(combo)
                .font(ZenDesign.Typography.mono)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(ZenDesign.Semantic.surfaceRaised)
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 5,
                                style: .continuous
                            )
                            .strokeBorder(ZenDesign.Semantic.borderStrong)
                        }
                }
        }
        .frame(minHeight: 40)
    }

    private var faqCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Frequently asked")
                        .font(ZenDesign.Typography.sectionTitle)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Spacer()
                    Text("\(filteredFAQs.count) of \(Self.faqs.count)")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    TextField(
                        "Search answers — try “private”, “model”, “hinglish”…",
                        text: $searchText
                    )
                    .textFieldStyle(.plain)
                    .font(ZenDesign.Typography.body)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
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

                if filteredFAQs.isEmpty {
                    VStack(spacing: 6) {
                        Text("No answer found")
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text("Try a different word — or read the documentation in the repository.")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(filteredFAQs) { faq in
                            if faq.id != filteredFAQs.first?.id {
                                Divider().overlay(ZenDesign.Semantic.border)
                            }
                            faqRow(faq)
                        }
                    }
                }
            }
        }
    }

    private func faqRow(_ faq: ZenFAQ) -> some View {
        let isExpanded = expandedFAQs.contains(faq.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded {
                    expandedFAQs.remove(faq.id)
                } else {
                    expandedFAQs.insert(faq.id)
                }
            } label: {
                HStack {
                    Text(faq.question)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(faq.question)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Text(faq.answer)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 560, alignment: .leading)
            }
        }
    }

    private var aboutCard: some View {
        ZenCard {
            HStack(spacing: 12) {
                ZenBrandMark(size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZenVoice")
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(aboutDetail)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var aboutDetail: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return "Version \(version ?? "dev") · macOS 14+ · Apple Silicon · local-first"
    }
}
