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
    @ObservedObject var refinementModelManagerViewModel:
        RefinementModelManagerViewModel
    @ObservedObject var applicationProfileViewModel:
        ApplicationProfileViewModel
    @ObservedObject var onboardingViewModel:
        OnboardingViewModel
    @ObservedObject var appState: AppState
    @State private var selection: Section = .home
    @AppStorage("zenvoice.appearance") private var appearance = "dark"

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
                HStack(spacing: 0) {
                    sidebar
                    content
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                brandLogo(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ZenVoice")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Local voice, refined")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)

            ForEach(
                Array(Section.groups.enumerated()),
                id: \.offset
            ) { index, group in
                if let title = group.title {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.top, index == 0 ? 0 : 16)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.sections) { section in
                    sidebarItem(section)
                }
            }

            Spacer(minLength: 16)

            Button {
                appearance = prefersDarkAppearance ? "light" : "dark"
            } label: {
                HStack(spacing: 9) {
                    Image(
                        systemName: prefersDarkAppearance
                            ? "sun.max.fill" : "moon.fill"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 15)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    Text(prefersDarkAppearance ? "Light mode" : "Dark mode")
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                prefersDarkAppearance
                    ? "Switch to Light mode"
                    : "Switch to Dark mode"
            )

            HStack(spacing: 7) {
                Circle()
                    .fill(ZenDesign.Semantic.success)
                    .frame(width: 6, height: 6)
                    .shadow(
                        color: ZenDesign.Semantic.success.opacity(0.55),
                        radius: 4
                    )
                Text("Processing stays local")
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.success)
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 16)
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
                            ? ZenDesign.Semantic.textPrimary
                            : ZenDesign.Semantic.textSecondary
                    )
                Spacer()
                if section == .history,
                   historyViewModel.recoveryCount > 0 {
                    Text("\(historyViewModel.recoveryCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.warn)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background {
                            Capsule().fill(ZenDesign.Semantic.warnMuted)
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
                modelViewModel: refinementModelManagerViewModel
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
                refinementModelManagerViewModel:
                    refinementModelManagerViewModel
            )
        case .help:
            HelpScreen(
                viewModel: viewModel,
                onboardingViewModel: onboardingViewModel,
                openShortcuts: { selection = .shortcuts }
            )
        }
    }

    @ViewBuilder
    private func brandLogo(size: CGFloat) -> some View {
        if let logo = BrandAssets.zenLogo {
            Image(nsImage: logo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: size * 0.25,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: size * 0.25,
                        style: .continuous
                    )
                    .strokeBorder(
                        ZenDesign.Semantic.accent.opacity(0.28),
                        lineWidth: 1
                    )
                }
        } else {
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: size, height: size)
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
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(ZenDesign.Semantic.accent)
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
                "64 more languages live in Languages. Hinglish and auto-detect use the Multilingual model — the next step recommends the right download."
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
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "MICROPHONE",
                    title: "Audio",
                    subtitle:
                        "Choose a microphone and verify its signal before dictating."
                )

                ZenCard {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Input device")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(viewModel.selectedMicrophoneName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }
                            Spacer()
                            StatusPill(
                                title:
                                    viewModel.selectedMicrophoneUID == nil
                                        ? "Follows macOS"
                                        : "Pinned",
                                isPositive: true
                            )
                        }

                        Button {
                            viewModel.selectMicrophone(nil)
                        } label: {
                            microphoneRow(
                                name: "System Default",
                                detail:
                                    "Follow the current macOS input automatically.",
                                selected:
                                    viewModel.selectedMicrophoneUID == nil,
                                badge: "RECOMMENDED"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            viewModel.audioDoctorState == .running
                        )

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        if viewModel.microphones.isEmpty {
                            Text("No connected microphones were found.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.danger
                                )
                                .padding(.vertical, 8)
                        } else {
                            ForEach(viewModel.microphones) { microphone in
                                Button {
                                    viewModel.selectMicrophone(microphone.id)
                                } label: {
                                    microphoneRow(
                                        name: microphone.name,
                                        detail: microphoneDetail(microphone),
                                        selected:
                                            viewModel.selectedMicrophoneUID
                                                == microphone.id,
                                        badge:
                                            microphone.isDefault
                                                ? "DEFAULT"
                                                : nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(
                                    !microphone.isConnected
                                        || viewModel.audioDoctorState
                                            == .running
                                )
                            }
                        }
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 13) {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: ZenDesign.Radius.small,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                                Image(systemName: "waveform.badge.magnifyingglass")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.accent
                                    )
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Audio Doctor")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(viewModel.audioDoctorState.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(
                                        audioDoctorTint
                                    )
                            }
                            Spacer()
                            Button(
                                viewModel.audioDoctorState == .running
                                    ? "Testing…"
                                    : "Run 3-second test",
                                action: viewModel.runAudioDoctor
                            )
                            .buttonStyle(ZenPrimaryButtonStyle())
                            .disabled(
                                viewModel.audioDoctorState == .running
                            )
                        }

                        ProgressView(value: viewModel.audioDoctorLevel)
                            .progressViewStyle(.linear)
                            .tint(audioDoctorTint)
                            .accessibilityLabel("Microphone signal level")
                            .accessibilityValue(
                                "\(Int((viewModel.audioDoctorLevel * 100).rounded())) percent"
                            )

                        HStack(spacing: 16) {
                            PrivacyFact(
                                icon: "speaker.slash",
                                text:
                                    "The temporary test recording is deleted immediately."
                            )
                            PrivacyFact(
                                icon: "network.slash",
                                text: "No test audio leaves this Mac."
                            )
                        }
                    }
                }

                ZenCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Safe disconnection")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text(
                            "If a pinned microphone disconnects during dictation, ZenVoice stops safely and follows your recovery-audio privacy setting."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
        .onAppear {
            viewModel.refreshMicrophones()
        }
    }

    private var audioDoctorTint: Color {
        switch viewModel.audioDoctorState {
        case .passed:
            return ZenDesign.Semantic.success
        case .quiet, .failed:
            return ZenDesign.Semantic.danger
        case .idle, .running:
            return ZenDesign.Semantic.accent
        }
    }

    private func microphoneDetail(_ microphone: MicrophoneDevice) -> String {
        if !microphone.isConnected {
            return "Disconnected"
        }
        if microphone.isInUseByAnotherApplication {
            return "Connected • also in use by another app"
        }
        return microphone.isDefault
            ? "Connected • current macOS default"
            : "Connected"
    }

    private func microphoneRow(
        name: String,
        detail: String,
        selected: Bool,
        badge: String?
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    selected ? "checkmark.circle.fill" : "circle"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(
                selected
                    ? ZenDesign.Semantic.success
                    : ZenDesign.Semantic.textTertiary
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.small,
                style: .continuous
            )
            .fill(
                selected
                    ? ZenDesign.Semantic.accentMuted
                    : Color.clear
            )
        }
        .contentShape(Rectangle())
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "LOCAL LANGUAGE PROFILES",
                    title: "Languages",
                    subtitle:
                        "Choose what you speak and how ZenVoice writes it. English stays explicit unless you select automatic detection."
                )

                if let error = viewModel.languageError {
                    ErrorBanner(message: error)
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("QUICK PROFILES")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                        HStack(spacing: 10) {
                            profileButton(
                                title: "English",
                                detail: "English speech → English",
                                selected:
                                    viewModel.languageProfile == .english,
                                action: viewModel.useEnglishProfile
                            )
                            profileButton(
                                title: "Hinglish",
                                detail: "Hindi + English → Latin script",
                                selected:
                                    viewModel.languageProfile == .hinglish,
                                action: viewModel.useHinglishProfile
                            )
                            profileButton(
                                title: "Auto",
                                detail: "Detect one language per dictation",
                                selected:
                                    viewModel.languageProfile
                                        .inputLanguageCode
                                        == LanguageProfile.automaticCode,
                                action: viewModel.useAutomaticProfile
                            )
                        }
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Output")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(
                                    viewModel.languageProfile.outputMode.detail
                                )
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            }
                            Spacer()
                            StatusPill(
                                title:
                                    viewModel.languageProfile.displayName,
                                isPositive: true
                            )
                        }

                        Picker(
                            "Output mode",
                            selection: Binding(
                                get: {
                                    viewModel.languageProfile.outputMode
                                },
                                set: viewModel.setOutputMode
                            )
                        ) {
                            ForEach(TranscriptionOutputMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Transcription output mode")

                        if viewModel.languageProfile.requiresMultilingualModel {
                            Label(
                                "This profile requires a Multilingual model.",
                                systemImage: "cpu"
                            )
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.accent
                            )
                        } else {
                            Label(
                                "English-only and Multilingual models are compatible.",
                                systemImage: "checkmark.shield"
                            )
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.success
                            )
                        }
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Spoken language")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(
                                    "\(LanguageCatalog.languages.count) explicit local languages"
                                )
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            }
                            Spacer()
                            TextField("Search languages", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 190)
                        }

                        Button {
                            viewModel.useAutomaticProfile()
                        } label: {
                            languageRow(
                                name: "Automatic detection",
                                nativeName:
                                    "Useful for unknown input; less reliable for short phrases",
                                badge: "AUTO",
                                selected:
                                    viewModel.languageProfile
                                        .inputLanguageCode
                                        == LanguageProfile.automaticCode
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        LazyVStack(spacing: 4) {
                            ForEach(visibleLanguages) { language in
                                Button {
                                    viewModel.setInputLanguage(language.code)
                                } label: {
                                    languageRow(
                                        name: language.displayName,
                                        nativeName: language.nativeName,
                                        badge:
                                            language.supportLevel.displayName,
                                        selected:
                                            viewModel.languageProfile
                                                .inputLanguageCode
                                                == language.code
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Text(
                    "Language quality varies by model and language. Preview languages are available now but need broader real-microphone validation before a public release."
                )
                .font(.system(size: 12))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
    }

    private func profileButton(
        title: String,
        detail: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ZenDesign.Semantic.success)
                    }
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(2)
            }
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
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
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .strokeBorder(
                        selected
                            ? ZenDesign.Semantic.accent.opacity(0.45)
                            : ZenDesign.Semantic.border,
                        lineWidth: 1
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func languageRow(
        name: String,
        nativeName: String,
        badge: String,
        selected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    selected ? "checkmark.circle.fill" : "circle"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(
                selected
                    ? ZenDesign.Semantic.success
                    : ZenDesign.Semantic.textTertiary
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(nativeName)
                    .font(.system(size: 12))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(badge.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.small,
                style: .continuous
            )
            .fill(
                selected
                    ? ZenDesign.Semantic.accentMuted
                    : Color.clear
            )
        }
        .contentShape(Rectangle())
    }
}

private struct ModelsScreen: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    @State private var modelPendingRemoval: VerifiedModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "VERIFIED LOCAL MODELS",
                    title: "Models",
                    subtitle:
                        "Choose an approved Whisper model. Downloads are pinned and SHA-256 verified."
                )

                ZenCard {
                    HStack(spacing: 14) {
                        Image(systemName: "laptopcomputer.and.arrow.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(ZenDesign.Semantic.accent)
                            .frame(width: 46, height: 46)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: ZenDesign.Radius.small,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recommendation for this Mac")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text(viewModel.hardwareProfile.summary)
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            Text(
                                "\(ModelRecommendationEngine.recommendedTier(for: viewModel.hardwareProfile).displayName) is the default recommendation. Language remains your choice."
                            )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                        }
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 11) {
                        PrivacyFact(
                            icon: "checkmark.shield.fill",
                            text:
                                "Only official whisper.cpp conversions from the pinned catalogue are offered."
                        )
                        PrivacyFact(
                            icon: "network.slash",
                            text:
                                "After download, transcription runs locally with no account or API key."
                        )
                        PrivacyFact(
                            icon: "doc.text.magnifyingglass",
                            text:
                                "Publisher, revision, license, size, and checksum are recorded for every model."
                        )
                    }
                }

                if viewModel.isVerifying {
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Verifying installed models…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                ForEach(ModelPerformanceTier.allCases, id: \.self) { tier in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tier.displayName.uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )

                        ForEach(
                            viewModel.models.filter { $0.tier == tier }
                        ) { model in
                            ModelRow(
                                model: model,
                                isInstalled: viewModel.isInstalled(model),
                                isSelected: viewModel.isSelected(model),
                                isLanguageCompatible:
                                    viewModel.isLanguageCompatible(model),
                                isDownloading:
                                    viewModel.downloadingModelID == model.id,
                                downloadProgress:
                                    viewModel.downloadProgress,
                                isVerifyingDownload:
                                    viewModel.isVerifyingDownload,
                                recommendation:
                                    viewModel.recommendation(for: model),
                                benchmark:
                                    viewModel.benchmarkSummary(for: model),
                                download: { viewModel.download(model) },
                                cancel: viewModel.cancelDownload,
                                select: { viewModel.select(model) },
                                remove: {
                                    modelPendingRemoval = model
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
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
}

private struct ModelRow: View {
    let model: VerifiedModel
    let isInstalled: Bool
    let isSelected: Bool
    let isLanguageCompatible: Bool
    let isDownloading: Bool
    let downloadProgress: Double?
    let isVerifyingDownload: Bool
    let recommendation: ModelRecommendation
    let benchmark: ModelBenchmarkSummary?
    let download: () -> Void
    let cancel: () -> Void
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        ZenCard(padding: 10) {
            ViewThatFits(in: .horizontal) {
                wideLayout
                    .frame(minWidth: 720)
                compactLayout
            }
        }
    }

    private var wideLayout: some View {
        HStack(spacing: 14) {
            modelIdentity
            Spacer(minLength: 12)
            recommendationStatus
                .frame(width: 116, alignment: .trailing)
            actionGroup
                .frame(width: 190, alignment: .trailing)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            modelIdentity
            HStack(spacing: 12) {
                recommendationStatus
                Spacer()
                actionGroup
            }
        }
    }

    private var modelIdentity: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(ZenDesign.Semantic.accentMuted)
                Image(
                    systemName:
                        model.languageCapability == .multilingual
                            ? "globe"
                            : "character.book.closed"
                )
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(model.displayName)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(
                            ZenDesign.Semantic.textPrimary
                        )
                    Text(model.languageCapability.displayName)
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(
                                ZenDesign.Semantic.surfaceRaised
                            )
                        )
                }
                Text(supportingDetail)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var recommendationStatus: some View {
        if isSelected {
            StatusPill(title: "In use", isPositive: true)
        } else if !isLanguageCompatible {
            StatusPill(
                title: "English only",
                isPositive: false
            )
        } else {
            StatusPill(
                title: recommendation.title,
                isPositive:
                    recommendation.level == .recommended
                        || recommendation.level == .supported
            )
        }
    }

    @ViewBuilder
    private var actionGroup: some View {
        if isDownloading {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 5) {
                    ProgressView(value: downloadProgress ?? 0)
                        .progressViewStyle(.linear)
                        .frame(width: 78)
                    Text(
                        isVerifyingDownload
                            ? "Verifying…"
                            : "\(Int(((downloadProgress ?? 0) * 100).rounded()))%"
                    )
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                }
                Button("Cancel", action: cancel)
                    .buttonStyle(
                        ZenSecondaryButtonStyle(minWidth: 82)
                    )
            }
        } else if isInstalled {
            HStack(spacing: 8) {
                if !isSelected {
                    Button("Use", action: select)
                        .buttonStyle(
                            ZenPrimaryButtonStyle(minWidth: 66)
                        )
                        .disabled(!isLanguageCompatible)
                } else {
                    Color.clear
                        .frame(width: 66, height: 44)
                        .accessibilityHidden(true)
                }
                Button("Remove", action: remove)
                    .buttonStyle(
                        ZenSecondaryButtonStyle(minWidth: 82)
                    )
            }
        } else {
            Button("Download", action: download)
                .buttonStyle(
                    ZenPrimaryButtonStyle(minWidth: 100)
                )
                .disabled(
                    recommendation.level == .insufficientStorage
                )
        }
    }

    private var supportingDetail: String {
        let provenance =
            "\(model.formattedFileSize) • \(model.format) • \(model.license)"
            + " • pinned \(model.sourceRevision.prefix(8))"
            + " • SHA-256 verified"
        guard let benchmark else {
            return "\(provenance) • \(recommendation.rationale)"
        }
        return provenance
            + " • \(benchmark.sampleCount) local sample"
            + (benchmark.sampleCount == 1 ? "" : "s")
            + " • "
            + benchmark.averageRealtimeFactor.formatted(
                .number.precision(.fractionLength(2))
            )
            + "× realtime"
    }
}

private struct InstantRefineScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var modelViewModel:
        RefinementModelManagerViewModel
    @State private var modelPendingRemoval:
        VerifiedRefinementModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "LOCAL TEXT REFINEMENT",
                    title: "Instant Refine",
                    subtitle:
                        "Clean the local Whisper transcript before ZenVoice pastes it."
                )

                ZenCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.accent
                                )
                                .frame(width: 46, height: 46)
                                .background {
                                    RoundedRectangle(
                                        cornerRadius:
                                            ZenDesign.Radius.small,
                                        style: .continuous
                                    )
                                    .fill(
                                        ZenDesign.Semantic.accentMuted
                                    )
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Built-in refinement engine")
                                    .font(
                                        .system(
                                            size: 13,
                                            weight: .bold
                                        )
                                    )
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(
                                    "Runs on this Mac after transcription and before paste. No account, API key, or network request."
                                )
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                            }
                        }

                        Picker(
                            "Refinement mode",
                            selection: Binding(
                                get: { viewModel.instantRefineMode },
                                set: {
                                    viewModel.setInstantRefineMode($0)
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
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Instant Refine mode")

                        Text(viewModel.instantRefineMode.detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                    }
                }

                nextDictationContextCard

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("VERIFIED LOCAL MODELS")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                        Spacer()
                        Text(modelViewModel.hardwareProfile.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                    }

                    if modelViewModel.isVerifying {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Verifying refinement models…")
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                        }
                    }

                    if let error = modelViewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if viewModel.instantRefineMode == .localModel,
                       !modelViewModel.hasSelectedInstalledModel {
                        ErrorBanner(
                            message:
                                "No verified refinement model is selected. ZenVoice will safely fall back to Clean."
                        )
                    }

                    ForEach(modelViewModel.models) { model in
                        RefinementModelRow(
                            model: model,
                            isInstalled:
                                modelViewModel.isInstalled(model),
                            isSelected:
                                modelViewModel.isSelected(model),
                            isDownloading:
                                modelViewModel.downloadingModelID
                                    == model.id,
                            downloadProgress:
                                modelViewModel.downloadProgress,
                            isVerifyingDownload:
                                modelViewModel.isVerifyingDownload,
                            recommendation:
                                modelViewModel.recommendation(
                                    for: model
                                ),
                            download: {
                                modelViewModel.download(model)
                            },
                            cancel:
                                modelViewModel.cancelDownload,
                            select: {
                                modelViewModel.select(model)
                            },
                            remove: {
                                modelPendingRemoval = model
                            }
                        )
                    }
                }

                HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
                    exampleCard
                    safetyCard
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Live dictation",
                            systemImage: "captions.bubble"
                        )
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textPrimary
                        )
                        PrivacyToggleRow(
                            title: "Show stable phrase preview",
                            detail:
                                "Transcribe locally after a natural pause and show the stable phrase in ZenBar.",
                            isOn: Binding(
                                get: {
                                    viewModel.livePreviewEnabled
                                },
                                set:
                                    viewModel.setLivePreviewEnabled
                            )
                        )

                        PrivacyToggleRow(
                            title: "Paste stable phrases on pause",
                            detail:
                                "Experimental. Paste only when the original target app is still active; final stop remains the recovery boundary.",
                            isOn: Binding(
                                get: {
                                    viewModel.commitOnPauseEnabled
                                },
                                set:
                                    viewModel.setCommitOnPauseEnabled
                            )
                        )
                        .disabled(!viewModel.livePreviewEnabled)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
        .alert(
            "Remove refinement model?",
            isPresented: Binding(
                get: { modelPendingRemoval != nil },
                set: { if !$0 { modelPendingRemoval = nil } }
            ),
            presenting: modelPendingRemoval
        ) { model in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                modelViewModel.remove(model)
                modelPendingRemoval = nil
            }
        } message: { model in
            Text(
                "\(model.displayName) will be removed from this Mac. Clean refinement remains available."
            )
        }
    }

    private var nextDictationContextCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next dictation context")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(
                            "Add names, product terms, or the topic for one recording. It stays in memory and clears when recording starts."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(
                            ZenDesign.Semantic.textSecondary
                        )
                    }
                    Spacer()
                    Text(
                        "\(viewModel.sanitizedNextDictationContext.count)/\(NextDictationContext.maximumCharacterCount)"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                }

                TextEditor(text: $viewModel.nextDictationContext)
                    .font(.system(size: 12))
                    .foregroundStyle(
                        ZenDesign.Semantic.textPrimary
                    )
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 64, maxHeight: 82)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(ZenDesign.Component.shortcutBackground)
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
                    .onChange(
                        of: viewModel.nextDictationContext
                    ) { _, value in
                        let sanitized =
                            NextDictationContext.sanitized(value)
                        if sanitized.count
                            >= NextDictationContext
                                .maximumCharacterCount {
                            viewModel.nextDictationContext = sanitized
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
                    .font(.system(size: 11))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
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
        }
    }

    private var exampleCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("EXAMPLE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                Text("“Um, create the the local app with Swift.”")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        ZenDesign.Semantic.textSecondary
                    )
                Text("Create the local app with Swift.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        ZenDesign.Semantic.textPrimary
                    )
            }
        }
    }

    private var safetyCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("MEANING GUARD")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                PrivacyFact(
                    icon: "checkmark.shield.fill",
                    text:
                        "Rejects a refinement that removes too much of the original transcript."
                )
                PrivacyFact(
                    icon: "text.badge.checkmark",
                    text:
                        "Every accepted result is blocked from inventing new semantic words."
                )
            }
        }
    }
}

private struct RefinementModelRow: View {
    let model: VerifiedRefinementModel
    let isInstalled: Bool
    let isSelected: Bool
    let isDownloading: Bool
    let downloadProgress: Double?
    let isVerifyingDownload: Bool
    let recommendation: ModelRecommendation
    let download: () -> Void
    let cancel: () -> Void
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        ZenCard {
            HStack(spacing: 13) {
                Image(systemName: "text.badge.sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                    .frame(width: 42, height: 42)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.accentMuted)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(model.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(model.tier.displayName.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                    }
                    Text(
                        "\(model.formattedFileSize) • \(model.format) • \(model.license)"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(
                        ZenDesign.Semantic.textSecondary
                    )
                    Link(
                        "Publisher license",
                        destination: model.licenseDocumentURL
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                    Text(
                        "\(model.languageSummary) Pinned \(model.sourceRevision.prefix(8)) • SHA-256 verified."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    Text(recommendation.rationale)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                }

                Spacer()

                StatusPill(
                    title:
                        isSelected
                            ? "In use"
                            : recommendation.title,
                    isPositive:
                        isSelected
                            || recommendation.level == .recommended
                            || recommendation.level == .supported
                )

                if isDownloading {
                    VStack(alignment: .trailing, spacing: 5) {
                        ProgressView(value: downloadProgress ?? 0)
                            .progressViewStyle(.linear)
                            .frame(width: 82)
                        Text(
                            isVerifyingDownload
                                ? "Verifying…"
                                : "\(Int(((downloadProgress ?? 0) * 100).rounded()))%"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                    }
                    Button("Cancel", action: cancel)
                        .buttonStyle(ZenSecondaryButtonStyle())
                } else if isInstalled {
                    if !isSelected {
                        Button("Use", action: select)
                            .buttonStyle(ZenPrimaryButtonStyle())
                    }
                    Button("Remove", action: remove)
                        .buttonStyle(ZenSecondaryButtonStyle())
                } else {
                    Button("Download", action: download)
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .disabled(
                            recommendation.level
                                == .insufficientStorage
                        )
                }
            }
        }
    }
}

private struct OverviewScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var appState: AppState
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var insightsViewModel: InsightsViewModel
    let navigate: (OverviewDestination) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "ZenVoice",
                    title: "Home",
                    subtitle:
                        "Everything runs locally and is ready to dictate."
                )

                hero

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        readiness
                        activity
                    }
                    .frame(minWidth: 720)

                    VStack(spacing: 16) {
                        readiness
                        activity
                    }
                }

                recentDictations
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
        .onAppear {
            viewModel.refreshSystemStatus()
            historyViewModel.refresh()
            insightsViewModel.refresh()
        }
    }

    private var hero: some View {
        ZenCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    heroIdentity
                    Spacer(minLength: 20)
                    heroActions
                }
                .frame(minWidth: 590)

                VStack(alignment: .leading, spacing: 16) {
                    heroIdentity
                    heroActions
                }
            }
        }
    }

    private var heroIdentity: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .fill(ZenDesign.Semantic.accentMuted)
                Image(systemName: phaseIcon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.accent)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(phaseTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(phaseDetail)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(
                        ZenDesign.Semantic.textSecondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var heroActions: some View {
        HStack(spacing: 10) {
            Button {
                navigate(.shortcuts)
            } label: {
                Label(
                    viewModel.currentShortcut.displayName,
                    systemImage: "keyboard"
                )
            }
            .buttonStyle(
                ZenPrimaryButtonStyle(minWidth: 132)
            )

            Button("Help & FAQ") {
                navigate(.help)
            }
            .buttonStyle(
                ZenSecondaryButtonStyle(minWidth: 92)
            )
        }
    }

    private var readiness: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "Ready to dictate",
                    detail: readinessSummary
                )

                OverviewReadinessRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: overviewMicrophoneName,
                    status: viewModel.microphoneStatus.title,
                    isReady: viewModel.microphoneStatus == .allowed,
                    action: { navigate(.audio) }
                )
                Divider().overlay(ZenDesign.Semantic.border)
                OverviewReadinessRow(
                    icon: "cpu",
                    title: "Speech model",
                    detail: selectedModelName,
                    status:
                        viewModel.isLocalModelReady
                            ? "Ready"
                            : "Install",
                    isReady: viewModel.isLocalModelReady,
                    action: { navigate(.models) }
                )
                Divider().overlay(ZenDesign.Semantic.border)
                OverviewReadinessRow(
                    icon: "globe",
                    title: "Language",
                    detail: appState.languageProfile.displayName,
                    status: "Local",
                    isReady: true,
                    action: { navigate(.languages) }
                )
                Divider().overlay(ZenDesign.Semantic.border)
                OverviewReadinessRow(
                    icon: "keyboard",
                    title: "Shortcut",
                    detail: viewModel.currentShortcut.displayName,
                    status: "Customizable",
                    isReady: true,
                    action: { navigate(.shortcuts) }
                )
                Divider().overlay(ZenDesign.Semantic.border)
                OverviewReadinessRow(
                    icon: "hand.tap.fill",
                    title: "Hold to dictate",
                    detail:
                        viewModel.holdToDictateEnabled
                            ? "Hold \(viewModel.holdKey.displayName)"
                            : "Optional",
                    status: holdStatus,
                    isReady:
                        viewModel.holdToDictateEnabled
                            && viewModel.accessibilityStatus == .allowed,
                    isNeutral: !viewModel.holdToDictateEnabled,
                    action: { navigate(.shortcuts) }
                )
            }
        }
    }

    private var activity: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    sectionHeader(
                        title: "Local activity",
                        detail: historyStateDetail
                    )
                    Spacer()
                    Button("View insights") {
                        navigate(.insights)
                    }
                    .buttonStyle(.plain)
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.accent)
                }

                OverviewMetricRow(
                    title: "Dictations",
                    value:
                        insightsViewModel.snapshot.dictationCount
                            .formatted()
                )
                Divider().overlay(ZenDesign.Semantic.border)
                OverviewMetricRow(
                    title: "Words dictated",
                    value:
                        insightsViewModel.snapshot.totalWordCount
                            .formatted()
                )
                Divider().overlay(ZenDesign.Semantic.border)
                OverviewMetricRow(
                    title: "Average speed",
                    value: averageSpeed
                )
                Divider().overlay(ZenDesign.Semantic.border)
                OverviewMetricRow(
                    title: "Current streak",
                    value:
                        "\(insightsViewModel.snapshot.currentStreakDays) day"
                        + (
                            insightsViewModel.snapshot.currentStreakDays == 1
                                ? ""
                                : "s"
                        )
                )

                if !historyViewModel.historyEnabled {
                    Button("History settings") {
                        navigate(.history)
                    }
                    .buttonStyle(
                        ZenSecondaryButtonStyle()
                    )
                    .padding(.top, 14)
                }
            }
        }
    }

    private func sectionHeader(
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ZenDesign.Typography.sectionTitle)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Text(detail)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var recentDictations: some View {
        let recent = Array(historyViewModel.records.prefix(3))
        if !recent.isEmpty {
            ZenCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        sectionHeader(
                            title: "Recent dictations",
                            detail: "Stored encrypted on this Mac."
                        )
                        Spacer()
                        Button("View history") {
                            navigate(.history)
                        }
                        .buttonStyle(.plain)
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.accent)
                    }

                    ForEach(recent) { record in
                        if record.id != recent.first?.id {
                            Divider().overlay(ZenDesign.Semantic.border)
                        }
                        recentDictationRow(record)
                    }
                }
            }
        }
    }

    private func recentDictationRow(
        _ record: DictationRecord
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(record.targetAppName ?? "Unknown app")
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        record.startedAt.formatted(
                            .relative(presentation: .named)
                        )
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                Text(
                    record.finalTranscript
                        ?? record.rawTranscript
                        ?? "Transcript unavailable"
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 10)
            Text("\(record.wordCount) words")
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
        }
        .frame(minHeight: 46)
    }

    private var phaseIcon: String {
        switch appState.phase {
        case .listening:
            return "waveform.circle.fill"
        case .transcribing, .inserting:
            return "sparkles"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "record.circle"
        }
    }

    private var phaseTitle: String {
        switch appState.phase {
        case .idle:
            return "Ready when you are"
        case .listening:
            return "Listening now"
        case .transcribing:
            return "Transcribing locally"
        case .inserting:
            return "Inserting your text"
        case .success:
            return "Dictation inserted"
        case .error:
            return "Needs your attention"
        }
    }

    private var phaseDetail: String {
        switch appState.phase {
        case .idle:
            return
                "Move to any text field, press \(viewModel.currentShortcut.displayName), and speak."
        case .listening:
            return
                "Press \(viewModel.currentShortcut.displayName) again when you finish."
        case .transcribing, .inserting:
            return "ZenVoice is finishing the request on this Mac."
        case .success:
            return "Your latest dictation was completed successfully."
        case .error(let message):
            return message
        }
    }

    private var readinessSummary: String {
        let missingCount = [
            viewModel.microphoneStatus != .allowed,
            !viewModel.isLocalModelReady
        ]
        .filter { $0 }
        .count
        return missingCount == 0
            ? "Core dictation setup is complete."
            : "\(missingCount) setup item"
                + (missingCount == 1 ? "" : "s")
                + " need attention."
    }

    private var holdStatus: String {
        guard viewModel.holdToDictateEnabled else {
            return "Off"
        }
        return viewModel.accessibilityStatus == .allowed
            ? "Ready"
            : "Needs access"
    }

    private var historyStateDetail: String {
        if historyViewModel.historyEnabled {
            return "Calculated from encrypted History on this Mac."
        }
        if insightsViewModel.snapshot.dictationCount > 0 {
            return "History is paused. Existing totals remain local."
        }
        return "Turn on History to see private on-device totals."
    }

    private var averageSpeed: String {
        let speed = insightsViewModel.snapshot.weightedWordsPerMinute
        return speed > 0
            ? "\(Int(speed.rounded())) wpm"
            : "—"
    }

    private var selectedModelName: String {
        guard let selectedModelID = modelManagerViewModel.selectedModelID,
              let model = modelManagerViewModel.models.first(
                where: { $0.id == selectedModelID }
              ) else {
            return viewModel.isLocalModelReady
                ? "Local model"
                : "Not installed"
        }
        return model.displayName
    }

    private var overviewMicrophoneName: String {
        viewModel.selectedMicrophoneUID == nil
            ? "System Default"
            : viewModel.selectedMicrophoneName
    }
}

private struct OverviewReadinessRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: String
    let isReady: Bool
    var isNeutral = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
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
                Text(title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            StatusPill(
                title: status,
                isPositive: isReady,
                isNeutral: isNeutral
            )

            Button(action: action) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
            .accessibilityLabel("Open \(title) settings")
        }
        .frame(minHeight: 54)
    }
}

private struct OverviewMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(ZenDesign.Typography.body)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
            Spacer()
            Text(value)
                .font(ZenDesign.Typography.bodyStrong)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
        }
        .frame(minHeight: 42)
    }
}

private struct HistoryScreen: View {
    @ObservedObject var viewModel: HistoryViewModel
    @State private var confirmsDeleteAll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "LOCAL VAULT",
                    title: "History",
                    subtitle: "Review and copy dictations saved only on this Mac."
                )

                if !viewModel.hasMadeHistoryChoice {
                    consentCard
                } else {
                    historyControls

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if viewModel.filteredRecords.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedRecords, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(1.1)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textTertiary
                                    )

                                VStack(spacing: 0) {
                                    ForEach(
                                        Array(group.records.enumerated()),
                                        id: \.element.id
                                    ) { index, record in
                                        HistoryRecordRow(
                                            record: record,
                                            copy: { viewModel.copy(record) },
                                            retry: { viewModel.retry(record) },
                                            setCategory: {
                                                viewModel.setCategory(
                                                    $0,
                                                    for: record
                                                )
                                            },
                                            delete: { viewModel.delete(record) }
                                        )

                                        if index < group.records.count - 1 {
                                            Divider()
                                                .overlay(
                                                    ZenDesign.Semantic.border
                                                )
                                                .padding(.leading, 54)
                                        }
                                    }
                                }
                                .background {
                                    RoundedRectangle(
                                        cornerRadius: ZenDesign.Radius.medium,
                                        style: .continuous
                                    )
                                    .fill(ZenDesign.Component.cardBackground)
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius:
                                                ZenDesign.Radius.medium,
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
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
        .alert(
            "Delete all history?",
            isPresented: $confirmsDeleteAll
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                viewModel.deleteAll()
            }
        } message: {
            Text(
                "This removes every saved transcript and recovery recording from this Mac."
            )
        }
    }

    private var consentCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 15) {
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.accentMuted)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(ZenDesign.Semantic.accent)
                    }
                    .frame(width: 50, height: 50)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Keep a private local history?")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text("ZenVoice can save encrypted transcripts so an interrupted paste never loses your words.")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
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
        }
    }

    private var historyControls: some View {
        HStack(spacing: 12) {
            Picker("History view", selection: $viewModel.scope) {
                Text("All").tag(HistoryViewModel.Scope.all)
                Text("Recovery \(viewModel.recoveryCount)")
                    .tag(HistoryViewModel.Scope.recovery)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 170)
            .accessibilityLabel("History view")

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                TextField("Search transcripts or apps", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
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
                    .strokeBorder(ZenDesign.Semantic.border, lineWidth: 1)
                }
            }

            StatusPill(
                title: viewModel.historyEnabled ? "Saving" : "Paused",
                isPositive: viewModel.historyEnabled
            )

            Button("Delete All") {
                confirmsDeleteAll = true
            }
            .buttonStyle(ZenDestructiveButtonStyle())
            .disabled(viewModel.records.isEmpty)
        }
    }

    private var emptyState: some View {
        ZenCard {
            VStack(spacing: 10) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 25))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                Text(
                    viewModel.scope == .recovery
                        ? "Recovery Inbox is clear."
                        : viewModel.historyEnabled
                            ? "Your next dictation will appear here."
                            : "History saving is paused."
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(
                    viewModel.scope == .recovery
                        ? "Failed and usable partial dictations appear here with Copy, Retry, and Delete actions."
                        : viewModel.historyEnabled
                            ? "Nothing has been saved yet."
                            : "Existing records remain local until you delete them."
                )
                .font(.system(size: 12))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
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

private struct InsightsScreen: View {
    @ObservedObject var viewModel: InsightsViewModel
    @State private var showsShareCard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                HStack(alignment: .bottom) {
                    PageHeader(
                        eyebrow: "PRIVATE ANALYTICS",
                        title: "Insights",
                        subtitle:
                            "Understand your dictation habits from encrypted history on this Mac."
                    )
                    Spacer()
                    Button {
                        showsShareCard = true
                    } label: {
                        Label("Share Highlights", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(viewModel.snapshot.dictationCount == 0)
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                if viewModel.snapshot.dictationCount == 0 {
                    emptyState
                } else {
                    metrics
                    activity
                    HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
                        categoryBreakdown
                        topApplications
                    }
                    privacyNote
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
        .onAppear(perform: viewModel.refresh)
        .sheet(isPresented: $showsShareCard) {
            ShareHighlightSheet(summary: shareSummary)
        }
    }

    private var metrics: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            StatusCard(
                title: "Total words",
                value: viewModel.snapshot.totalWordCount.formatted()
            )
            StatusCard(
                title: "Average speed",
                value:
                    "\(Int(viewModel.snapshot.weightedWordsPerMinute.rounded())) WPM"
            )
            StatusCard(
                title: "Current streak",
                value:
                    "\(viewModel.snapshot.currentStreakDays) day"
                    + (viewModel.snapshot.currentStreakDays == 1 ? "" : "s")
            )
            StatusCard(
                title: "Apps used",
                value: viewModel.snapshot.distinctApplicationCount.formatted()
            )
        }
    }

    private var activity: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last 7 days")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text(
                            "\(viewModel.snapshot.dictationCount) dictations · "
                                + "\(viewModel.snapshot.longestStreakDays)-day best streak"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }
                    Spacer()
                    Text("Local calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(viewModel.snapshot.recentActivity) { day in
                        VStack(spacing: 7) {
                            Text(day.wordCount.formatted())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            RoundedRectangle(
                                cornerRadius: 4,
                                style: .continuous
                            )
                            .fill(
                                day.wordCount > 0
                                    ? ZenDesign.Semantic.accent
                                    : ZenDesign.Semantic.surfaceRaised
                            )
                            .frame(
                                height: activityHeight(for: day.wordCount)
                            )
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 94, alignment: .bottom)
            }
        }
    }

    private var categoryBreakdown: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Work by category")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                ForEach(viewModel.snapshot.categories) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Image(systemName: insight.category.icon)
                                .foregroundStyle(ZenDesign.Semantic.accent)
                                .frame(width: 14)
                            Text(insight.category.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            Spacer()
                            Text("\(insight.wordCount) words")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                        }
                        ProgressView(
                            value: Double(insight.wordCount),
                            total: Double(maxCategoryWords)
                        )
                        .tint(ZenDesign.Semantic.accent)
                    }
                }
            }
        }
    }

    private var topApplications: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Most-used apps")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                if viewModel.snapshot.topApplications.isEmpty {
                    Text("No application context has been saved yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                } else {
                    ForEach(
                        Array(
                            viewModel.snapshot.topApplications.enumerated()
                        ),
                        id: \.element.id
                    ) { index, app in
                        HStack(spacing: 9) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                    .lineLimit(1)
                                Text(
                                    "\(app.dictationCount) dictations · "
                                        + "\(app.wordCount) words"
                                )
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(ZenDesign.Semantic.success)
            Text(
                "Insights are calculated locally. ZenVoice stores app identity, not window titles, URLs, recipients, or surrounding text."
            )
            .font(.system(size: 12))
            .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }

    private var emptyState: some View {
        ZenCard {
            VStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 26))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                Text("Your local insights will appear here.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(
                    "Save a completed dictation to begin tracking words, speed, streaks, apps, and categories."
                )
                .font(.system(size: 12))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var maxCategoryWords: Int {
        max(1, viewModel.snapshot.categories.map(\.wordCount).max() ?? 1)
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

    private func activityHeight(for wordCount: Int) -> CGFloat {
        let maximum = max(
            1,
            viewModel.snapshot.recentActivity.map(\.wordCount).max() ?? 1
        )
        guard wordCount > 0 else {
            return 5
        }
        return 12 + 50 * CGFloat(wordCount) / CGFloat(maximum)
    }
}

private struct VoiceProfileScreen: View {
    @ObservedObject var viewModel: VoiceProfileViewModel
    @State private var heardPhrase = ""
    @State private var replacementPhrase = ""
    @State private var confirmsDeleteAllRules = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "LOCAL LANGUAGE PROFILE",
                    title: "Voice Profile",
                    subtitle:
                        "Teach ZenVoice your words and review language patterns from recent local history."
                )

                profileSummary

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                learningControls
                corrections

                HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
                    topWords
                    catchPhrases
                }

                HStack(spacing: 9) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundStyle(ZenDesign.Semantic.success)
                    Text(
                        "This is a language-usage profile, not a biometric voiceprint. ZenVoice does not identify or authenticate people."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
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

    private var profileSummary: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            StatusCard(
                title: "Analyzed",
                value:
                    "\(viewModel.snapshot.analyzedDictationCount) dictations"
            )
            StatusCard(
                title: "Most active",
                value: activeHourLabel
            )
            StatusCard(
                title: "Corrections",
                value:
                    "\(viewModel.snapshot.correctionRules.count) rules"
            )
        }
    }

    private var corrections: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal corrections")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        "Explicit whole-word replacements are encrypted and applied locally."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }

                HStack(spacing: 10) {
                    correctionField(
                        title: "WHEN ZENVOICE HEARS",
                        placeholder: "zen pens",
                        text: $heardPhrase
                    )
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    correctionField(
                        title: "REPLACE WITH",
                        placeholder: "ZenPense",
                        text: $replacementPhrase
                    )
                    Button("Add Rule") {
                        if viewModel.addRule(
                            source: heardPhrase,
                            replacement: replacementPhrase
                        ) {
                            heardPhrase = ""
                            replacementPhrase = ""
                        }
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(
                        heardPhrase.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            || replacementPhrase.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }

                if viewModel.snapshot.correctionRules.isEmpty {
                    Text(
                        "No personal corrections yet. Add only terms you want ZenVoice to replace automatically."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(
                                viewModel.snapshot.correctionRules.enumerated()
                            ),
                            id: \.element.id
                        ) { index, rule in
                            HStack(spacing: 10) {
                                Text(rule.source)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textTertiary
                                    )
                                Text(rule.replacement)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Spacer()
                                Text(
                                    "Used \(rule.usageCount) time"
                                        + (rule.usageCount == 1 ? "" : "s")
                                )
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                                Button {
                                    viewModel.deleteRule(rule)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(ZenDesign.Semantic.danger)
                            }
                            .padding(.vertical, 9)
                            if index
                                < viewModel.snapshot.correctionRules.count - 1 {
                                Divider().overlay(
                                    ZenDesign.Semantic.border
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var learningControls: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local learning controls")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textPrimary
                        )
                    Text(
                        "ZenVoice never learns silently. These controls affect only saved history and rules you explicitly created."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(
                        ZenDesign.Semantic.textSecondary
                    )
                }

                PrivacyToggleRow(
                    title: "Apply personal correction rules",
                    detail:
                        "Pause every encrypted replacement rule without deleting it.",
                    isOn: Binding(
                        get: {
                            viewModel.appliesCorrectionRules
                        },
                        set:
                            viewModel.setAppliesCorrectionRules
                    )
                )

                PrivacyToggleRow(
                    title: "Analyze saved history for patterns",
                    detail:
                        "Show frequent words, recurring phrases, and your most active hour. No new copy is stored.",
                    isOn: Binding(
                        get: { viewModel.analyzesHistory },
                        set: viewModel.setAnalyzesHistory
                    )
                )

                HStack {
                    Label(
                        "No background microphone listening or biometric voiceprint",
                        systemImage: "hand.raised.fill"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                    Spacer()
                    Button("Delete All Rules") {
                        confirmsDeleteAllRules = true
                    }
                    .buttonStyle(ZenDestructiveButtonStyle())
                    .disabled(
                        viewModel.snapshot.correctionRules.isEmpty
                    )
                }
            }
        }
    }

    private var topWords: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("Most-used words")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                if viewModel.snapshot.topWords.isEmpty {
                    emptyProfileText
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 70),
                                spacing: 8
                            )
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(viewModel.snapshot.topWords) { item in
                            HStack(spacing: 6) {
                                Text(item.text)
                                    .lineLimit(1)
                                Text("\(item.count)")
                                    .foregroundStyle(
                                        ZenDesign.Semantic.accent
                                    )
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background {
                                Capsule().fill(
                                    ZenDesign.Semantic.surfaceRaised
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var catchPhrases: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("Recurring phrases")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                if viewModel.snapshot.catchPhrases.isEmpty {
                    emptyProfileText
                } else {
                    ForEach(viewModel.snapshot.catchPhrases) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "quote.opening")
                                .foregroundStyle(
                                    ZenDesign.Semantic.accent
                                )
                            Text(item.text)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                                .lineLimit(1)
                            Spacer()
                            Text("×\(item.count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                        }
                    }
                }
            }
        }
    }

    private var emptyProfileText: some View {
        Text(
            viewModel.analyzesHistory
                ? "More saved dictations are needed."
                : "Pattern analysis is paused."
        )
            .font(.system(size: 12))
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
    }

    private var activeHourLabel: String {
        guard let hour = viewModel.snapshot.mostActiveHour,
              let date = Calendar.current.date(
                from: DateComponents(hour: hour)
              ) else {
            return "Not enough data"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func correctionField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 34)
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
                            ZenDesign.Semantic.border,
                            lineWidth: 1
                        )
                    }
                }
        }
    }
}

private struct ShortcutsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "CONTROLS",
                    title: "Shortcuts",
                    subtitle: "Choose a combination that feels natural on your keyboard."
                )

                ZenCard {
                    HStack(alignment: .center, spacing: 15) {
                        ZStack {
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                            .fill(ZenDesign.Semantic.accentMuted)
                            Image(
                                systemName:
                                    "rectangle.bottomthird.inset.filled"
                            )
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(ZenDesign.Semantic.accent)
                        }
                        .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show ZenVoice at all times")
                                .font(ZenDesign.Typography.sectionTitle)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text(
                                "When off, the bar appears when dictation starts and hides after your text is inserted."
                            )
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                        }

                        Spacer()

                        Toggle(
                            "Show ZenVoice at all times",
                            isOn: Binding(
                                get: {
                                    viewModel.showsZenVoiceAtAllTimes
                                },
                                set:
                                    viewModel
                                        .setShowsZenVoiceAtAllTimes
                            )
                        )
                        .labelsHidden()
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .center, spacing: 15) {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                                Image(systemName: "waveform.badge.mic")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(ZenDesign.Semantic.accent)
                            }
                            .frame(width: 46, height: 46)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start or stop dictation")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text("Works globally while ZenVoice is running.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }

                            Spacer()

                            ShortcutCaptureButton(
                                displayName:
                                    viewModel.currentShortcut.displayName,
                                isCapturing:
                                    viewModel.isCapturingShortcut,
                                action: {
                                    if viewModel.isCapturingShortcut {
                                        viewModel.cancelShortcutCapture()
                                    } else {
                                        viewModel.beginShortcutCapture()
                                    }
                                }
                            )
                        }

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        HStack(alignment: .center, spacing: 15) {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(ZenDesign.Semantic.accent)
                            }
                            .frame(width: 46, height: 46)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Paste last dictation")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text("Recovers your latest text without recording again.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }

                            Spacer()

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
                        }

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        HStack(alignment: .center, spacing: 15) {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                                Image(systemName: "eye.slash.fill")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(ZenDesign.Semantic.accent)
                            }
                            .frame(width: 46, height: 46)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Toggle Private Dictation")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text("Instantly stop saving transcripts and audio.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }

                            Spacer()

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
                        }

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 15) {
                                ZStack {
                                    RoundedRectangle(
                                        cornerRadius: 12,
                                        style: .continuous
                                    )
                                    .fill(ZenDesign.Semantic.accentMuted)
                                    Image(systemName: "hand.tap.fill")
                                        .font(
                                            .system(
                                                size: 19,
                                                weight: .semibold
                                            )
                                        )
                                        .foregroundStyle(
                                            ZenDesign.Semantic.accent
                                        )
                                }
                                .frame(width: 46, height: 46)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hold to dictate")
                                        .font(
                                            ZenDesign.Typography.sectionTitle
                                        )
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textPrimary
                                        )
                                    Text(
                                        "Hold one modifier key to record, then release it to finish."
                                    )
                                    .font(ZenDesign.Typography.caption)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                                }

                                Spacer()

                                Picker(
                                    "Hold key",
                                    selection: Binding(
                                        get: { viewModel.holdKey },
                                        set: viewModel.setHoldKey
                                    )
                                ) {
                                    ForEach(
                                        HoldKeyChoice.allCases,
                                        id: \.self
                                    ) { choice in
                                        Text(choice.displayName).tag(choice)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 138)

                                Toggle(
                                    "Hold to dictate",
                                    isOn: Binding(
                                        get: {
                                            viewModel.holdToDictateEnabled
                                        },
                                        set:
                                            viewModel
                                                .setHoldToDictateEnabled
                                    )
                                )
                                .labelsHidden()
                            }

                            if viewModel.holdToDictateEnabled,
                               viewModel.accessibilityStatus != .allowed {
                                HStack(spacing: 10) {
                                    Image(
                                        systemName:
                                            "exclamationmark.shield.fill"
                                    )
                                    Text(
                                        "Allow Accessibility so the hold key works in every app."
                                    )
                                    .font(ZenDesign.Typography.caption)
                                    Spacer()
                                    Button("Allow Access") {
                                        viewModel
                                            .requestAccessibilityAccess()
                                    }
                                    .buttonStyle(
                                        ZenSecondaryButtonStyle()
                                    )
                                }
                                .foregroundStyle(
                                    ZenDesign.Semantic.danger
                                )
                                .padding(.leading, 61)
                            }
                        }

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 18) {
                                shortcutHelp
                                Spacer(minLength: 12)
                                resetActions
                            }
                            .frame(minWidth: 650)

                            VStack(alignment: .leading, spacing: 12) {
                                shortcutHelp
                                resetActions
                            }
                        }
                    }
                }

                if let error = viewModel.shortcutError {
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
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

                ZenCard {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "lightbulb.max.fill")
                            .foregroundStyle(ZenDesign.Semantic.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Choose something memorable")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text("A two-modifier shortcut is less likely to conflict with shortcuts in other apps. ZenVoice keeps your choice on this Mac.")
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
    }

    private var shortcutHelp: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Create your own shortcut")
                .font(ZenDesign.Typography.bodyStrong)
                .foregroundStyle(
                    ZenDesign.Semantic.textPrimary
                )
            Text(
                "Select Change, then press one key with Command, Control, Option, or Shift. Press Escape to cancel."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(
                ZenDesign.Semantic.textSecondary
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resetActions: some View {
        HStack(spacing: 8) {
            Button("Reset Dictation") {
                viewModel.resetShortcut()
            }
            .buttonStyle(ZenSecondaryButtonStyle())

            Button("Reset Paste") {
                viewModel.resetPasteLastShortcut()
            }
            .buttonStyle(ZenSecondaryButtonStyle())

            Button("Reset Private") {
                viewModel.resetPrivateModeShortcut()
            }
            .buttonStyle(ZenSecondaryButtonStyle())
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
    @ObservedObject var refinementModelManagerViewModel:
        RefinementModelManagerViewModel
    @State private var confirmsDeleteRecoveryAudio = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "TRUST",
                    title: "Privacy & permissions",
                    subtitle: "See exactly what ZenVoice can access on your Mac."
                )

                privacyInventory

                ZenCard {
                    VStack(spacing: 0) {
                        PermissionRow(
                            icon: "mic.fill",
                            title: "Microphone",
                            detail: "Used only while a dictation is active.",
                            status: viewModel.microphoneStatus,
                            action: viewModel.requestMicrophoneAccess
                        )

                        Divider()
                            .overlay(ZenDesign.Semantic.border)
                            .padding(.leading, 54)

                        PermissionRow(
                            icon: "accessibility",
                            title: "Accessibility",
                            detail: "Used to paste text into the active app.",
                            status: viewModel.accessibilityStatus,
                            action: viewModel.requestAccessibilityAccess
                        )
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "externaldrive.badge.checkmark")
                                .foregroundStyle(ZenDesign.Semantic.accent)
                            Text("Local history")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Spacer()
                            StatusPill(
                                title: historyViewModel.historyEnabled
                                    ? "Saving"
                                    : "Paused",
                                isPositive: historyViewModel.historyEnabled
                            )
                        }

                        PrivacyToggleRow(
                            title: "Save encrypted transcripts",
                            detail: "Save successful and partial transcripts in your encrypted local vault.",
                            isOn: Binding(
                                get: { historyViewModel.historyEnabled },
                                set: historyViewModel.setHistoryEnabled
                            )
                        )

                        PrivacyToggleRow(
                            title: "Keep failed audio for 24 hours",
                            detail: "Only when no usable transcript was produced, so you can retry.",
                            isOn: Binding(
                                get: {
                                    historyViewModel.retainsFailedAudio
                                },
                                set:
                                    historyViewModel.setRetainsFailedAudio
                            )
                        )
                        .disabled(!historyViewModel.historyEnabled)

                        PrivacyToggleRow(
                            title: "Private Dictation mode",
                            detail: "While enabled, transcripts and audio are never saved.",
                            isOn: Binding(
                                get: {
                                    historyViewModel.privateModeEnabled
                                },
                                set:
                                    historyViewModel
                                        .setPrivateModeEnabled
                            )
                        )
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundStyle(ZenDesign.Semantic.accent)
                            Text("Local processing")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Spacer()
                            StatusPill(
                                title: viewModel.isLocalModelReady
                                    ? "Model ready"
                                    : "Model missing",
                                isPositive: viewModel.isLocalModelReady
                            )
                        }

                        PrivacyFact(
                            icon: "network.slash",
                            text: "No cloud transcription or account"
                        )
                        PrivacyFact(
                            icon: "waveform.path",
                            text: "Successful audio is deleted after transcription"
                        )
                        PrivacyFact(
                            icon: "clock.arrow.circlepath",
                            text: historyViewModel.historyEnabled
                                ? "Transcript history is encrypted on this Mac"
                                : "New transcript saving is paused"
                        )
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
        .onAppear {
            historyViewModel.refresh()
            voiceProfileViewModel.refresh()
            modelManagerViewModel.refresh()
            refinementModelManagerViewModel.refresh()
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
    }

    private var privacyInventory: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Local data inventory")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(
                            "Live counts from this Mac. No telemetry or cloud account."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(
                            ZenDesign.Semantic.textSecondary
                        )
                    }
                    Spacer()
                    Text("ZenVoice \(appVersion)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                }

                HStack(spacing: 10) {
                    inventoryValue(
                        "\(historyViewModel.savedTranscriptCount)",
                        label: "Encrypted transcripts"
                    )
                    inventoryValue(
                        "\(historyViewModel.recoveryAudioCount)",
                        label: "Recovery audio"
                    )
                    inventoryValue(
                        "\(voiceProfileViewModel.snapshot.correctionRules.count)",
                        label: "Correction rules"
                    )
                    inventoryValue(
                        "\(installedModelCount)",
                        label: "Local models"
                    )
                }

                HStack {
                    Label(
                        "Next-dictation context is memory-only and is never counted here.",
                        systemImage: "memorychip"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                    Spacer()
                    Button("Delete Recovery Audio") {
                        confirmsDeleteRecoveryAudio = true
                    }
                    .buttonStyle(ZenDestructiveButtonStyle())
                    .disabled(
                        historyViewModel.recoveryAudioCount == 0
                    )
                }
            }
        }
    }

    private func inventoryValue(
        _ value: String,
        label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(
                    ZenDesign.Semantic.textPrimary
                )
            Text(label)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(
                    ZenDesign.Semantic.textTertiary
                )
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var installedModelCount: Int {
        modelManagerViewModel.installedModelIDs.count
            + refinementModelManagerViewModel
                .installedModelIDs.count
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ZenDesign.Typography.button)
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .padding(.horizontal, 16)
            .frame(minWidth: minWidth)
            .frame(height: 44)
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
            .font(ZenDesign.Typography.button)
            .foregroundStyle(ZenDesign.Semantic.textOnAccent)
            .padding(.horizontal, 16)
            .frame(minWidth: minWidth)
            .frame(height: 44)
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
            .font(ZenDesign.Typography.button)
            .foregroundStyle(ZenDesign.Semantic.textOnAccent)
            .padding(.horizontal, 16)
            .frame(minWidth: minWidth)
            .frame(height: 44)
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
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "PER-APPLICATION BEHAVIOR",
                    title: "App Profiles",
                    subtitle:
                        "Give each app its own language, refinement, and voice-command behavior. Anything not set here uses your global settings."
                )

                applicationProfilesCard
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
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
                "With a Multilingual model installed, the Hinglish profile writes Hindi-English speech in Latin script the way you'd type it. You can also choose native Devanagari output or local English translation.",
            tags: "hinglish hindi language multilingual devanagari"
        ),
        ZenFAQ(
            id: 7,
            question: "What does Instant Refine actually change?",
            answer:
                "Clean removes fillers, repeated words, and spoken restarts — never meaning. Agent Prompt formats your speech as a structured prompt. Local Model uses a verified on-device model with a 5-second deadline, a no-invention guard, and automatic fallback to Clean.",
            tags: "refine clean agent model rewrite grammar"
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
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "SUPPORT",
                    title: "Help & FAQ",
                    subtitle:
                        "Answers first, setup second. Everything here works offline."
                )

                quickActions
                cheatSheet
                faqCard
                aboutCard
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .background(ZenDesign.Semantic.canvas)
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
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(ZenDesign.Semantic.accent)
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
