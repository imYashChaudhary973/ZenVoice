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

enum OverviewDestination {
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
        case dictation = "Dictation"
        case languagesAndModels = "Languages & Models"
        case formatting = "Formatting"
        case commands = "Commands"
        case personal = "Personal"
        case history = "History"
        case privacy = "Privacy & Data"
        case help = "Help & About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home:
                return "house"
            case .dictation:
                return "mic"
            case .languagesAndModels:
                return "globe"
            case .formatting:
                return "wand.and.stars"
            case .commands:
                return "command"
            case .personal:
                return "person.crop.circle"
            case .history:
                return "clock.arrow.circlepath"
            case .privacy:
                return "hand.raised"
            case .help:
                return "questionmark.circle"
            }
        }

        /// Phase 6 navigation: nine entries, no duplicates.
        static let groups: [(title: String?, sections: [Section])] = [
            (nil, [.home]),
            ("Dictation", [.dictation]),
            ("Speech", [.languagesAndModels]),
            ("Refinement", [.formatting]),
            ("Control", [.commands]),
            ("Personal", [.personal]),
            ("Your data", [.history]),
            ("Security", [.privacy]),
            ("Support", [.help])
        ]
    }

    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var audioHistoryViewModel: AudioHistoryViewModel
    @ObservedObject var cloudAIViewModel: CloudAIViewModel
    @ObservedObject var updatesViewModel: UpdatesViewModel
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
    @State private var showsCommandPalette = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ZenAppearance.storageKey)
    private var appearance = ZenAppearance.system.rawValue

    private var selectedAppearance: ZenAppearance {
        ZenAppearance.resolved(appearance)
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
                    titleBar
                    HStack(spacing: 0) {
                        sidebar
                        content
                    }
                }
                .overlay {
                    if showsCommandPalette {
                        ZenCommandPalette(commands: paletteCommands) {
                            showsCommandPalette = false
                        }
                    }
                }
                .animation(
                    ZenDesign.Motion.fast(reduceMotion),
                    value: showsCommandPalette
                )
                .background {
                    Button("Open command palette") {
                        showsCommandPalette.toggle()
                    }
                    .keyboardShortcut("k", modifiers: .command)
                    .buttonStyle(.plain)
                    .opacity(0)
                    .accessibilityHidden(true)
                }
            }
        }
        .background(ZenDesign.Semantic.canvas)
        .frame(minWidth: 900, minHeight: 640)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .onAppear {
            viewModel.refreshSystemStatus()
        }
    }

    /// Everything ⌘K can reach: every settings screen, one entry per
    /// speech model, and the handful of global actions.
    private var paletteCommands: [ZenCommand] {
        let sections = Section.allCases.map { section in
            ZenCommand(
                id: "section-\(section.id)",
                title: section.rawValue,
                subtitle: "Go to",
                icon: section.icon,
                keywords: sectionKeywords(section)
            ) {
                selection = section
            }
        }
        let models = modelManagerViewModel.models.map { model in
            ZenCommand(
                id: "model-\(model.id)",
                title: model.displayName,
                subtitle: modelManagerViewModel.isInstalled(model)
                    ? "Model · installed"
                    : "Model · available",
                icon: "cpu",
                keywords: "model speech download \(model.id)"
            ) {
                selection = .languagesAndModels
            }
        }
        let actions = [
            ZenCommand(
                id: "action-dictate",
                title: "Start dictating",
                subtitle: "Action",
                icon: "mic",
                keywords: "record speak voice start",
                action: toggleRecording
            ),
            ZenCommand(
                id: "action-replay-setup",
                title: "Replay setup guide",
                subtitle: "Action",
                icon: "arrow.counterclockwise",
                keywords: "onboarding first run welcome",
                action: onboardingViewModel.show
            ),
        ]
        let appearances = ZenAppearance.allCases.map { option in
            ZenCommand(
                id: "appearance-\(option.rawValue)",
                title: "\(option.title) appearance",
                subtitle: option == selectedAppearance
                    ? "Appearance · current"
                    : "Appearance",
                icon: option.systemImage,
                keywords: "theme dark light system mode appearance"
            ) {
                appearance = option.rawValue
            }
        }
        return sections + models + actions + appearances
    }

    private func sectionKeywords(_ section: Section) -> String {
        switch section {
        case .home:
            return "overview status ready start today usage"
        case .dictation:
            return "hotkey microphone audio overlay waveform doctor"
        case .languagesAndModels:
            return "language hinglish english multilingual model whisper parakeet"
        case .formatting:
            return "refine clean smart cloud filler punctuation format"
        case .commands:
            return "command mode voice control write mode rewrite"
        case .personal:
            return "your words per-app rules corrections vocabulary"
        case .history:
            return "transcripts audio recordings insights stats search"
        case .privacy:
            return "permissions data delete encrypted inventory"
        case .help:
            return "faq questions support cheat sheet about version update"
        }
    }

    private var titleBar: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            HStack(spacing: 7) {
                ZenBrandMark(size: 22)
                Text("ZenVoice")
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
            }
            .frame(width: 224, alignment: .leading)
            .padding(.leading, 12)

            HStack(spacing: ZenDesign.Spacing.xs) {
                Image(systemName: appState.phase.statusIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(appState.phase.statusTint)
                Text(appState.phase.label)
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }

            Spacer()

            HStack(spacing: ZenDesign.Spacing.xs) {
                titleAction("command", label: "Command palette", action: { showsCommandPalette = true })
                    .accessibilityLabel("Open command palette")
                let isListening = appState.phase == .listening
                Button(action: toggleRecording) {
                    HStack(spacing: 5) {
                        Image(systemName: isListening ? "stop.fill" : "mic")
                            .font(.system(size: 11, weight: .medium))
                        Text(isListening ? "Stop" : "Dictate")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(ZenDesign.Semantic.textOnAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(
                            isListening
                                ? ZenDesign.Semantic.danger
                                : ZenDesign.Semantic.accent
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isListening ? "Stop dictating" : "Start dictating"
                )
            }
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(ZenDesign.Semantic.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ZenDesign.Semantic.border)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private func titleAction(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(ZenDesign.Semantic.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: ZenDesign.Radius.small, style: .continuous)
                    .fill(ZenDesign.Semantic.surfaceRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: ZenDesign.Radius.small, style: .continuous)
                            .strokeBorder(ZenDesign.Semantic.borderStrong, lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(
                        Array(Section.groups.enumerated()),
                        id: \.offset
                    ) { index, group in
                        if let title = group.title {
                            Text(title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                                .padding(.horizontal, 6)
                                .padding(.top, index == 0 ? 6 : 18)
                                .padding(.bottom, 4)
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
                ForEach(ZenAppearance.allCases) { option in
                    appearanceButton(option)
                }
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
        .padding(.horizontal, 8)
        .padding(.top, 10)
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
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(
                        selection == section
                            ? ZenDesign.Semantic.textPrimary
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
                        .foregroundStyle(ZenDesign.Semantic.textOnAccent)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ZenDesign.Semantic.accent)
                        }
                        .accessibilityLabel(
                            "\(historyViewModel.recoveryCount) items in Recovery Inbox"
                        )
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
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
        _ option: ZenAppearance
    ) -> some View {
        let selected = selectedAppearance == option
        return Button {
            appearance = option.rawValue
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(option.title)
                    .font(ZenDesign.Typography.captionStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
        .accessibilityLabel("\(option.title) appearance")
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
                        selection = .dictation
                    case .models:
                        selection = .languagesAndModels
                    case .languages:
                        selection = .languagesAndModels
                    case .history:
                        selection = .history
                    case .insights:
                        selection = .history
                    case .shortcuts:
                        selection = .dictation
                    case .help:
                        selection = .help
                    }
                }
            )
        case .dictation:
            DictationScreen(viewModel: viewModel)
        case .languagesAndModels:
            LanguagesAndModelsScreen(
                viewModel: viewModel,
                modelManagerViewModel: modelManagerViewModel
            )
        case .formatting:
            FormattingScreen(
                viewModel: viewModel,
                cloudAIViewModel: cloudAIViewModel
            )
        case .commands:
            CommandsScreen(viewModel: viewModel)
        case .personal:
            PersonalScreen(
                viewModel: viewModel,
                voiceProfileViewModel: voiceProfileViewModel,
                applicationProfileViewModel: applicationProfileViewModel
            )
        case .history:
            HistoryContainerScreen(
                historyViewModel: historyViewModel,
                audioHistoryViewModel: audioHistoryViewModel,
                insightsViewModel: insightsViewModel
            )
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
            HelpAndAboutScreen(
                viewModel: viewModel,
                updatesViewModel: updatesViewModel,
                onboardingViewModel: onboardingViewModel,
                openShortcuts: { selection = .dictation }
            )
        }
    }

}

private extension AppState.Phase {
    var statusIcon: String {
        switch self {
        case .idle:
            return "circle.fill"
        case .listening:
            return "waveform"
        case .transcribing:
            return "cpu"
        case .inserting:
            return "arrow.down.doc"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var statusTint: Color {
        switch self {
        case .idle:
            return ZenDesign.Semantic.success
        case .listening:
            return ZenDesign.Semantic.accent
        case .transcribing, .inserting:
            return ZenDesign.Semantic.warn
        case .success:
            return ZenDesign.Semantic.success
        case .error:
            return ZenDesign.Semantic.danger
        }
    }
}

struct ErrorBanner: View {
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
                // `accentStrong` moves the right way in both appearances:
                // darker than `accent` in light, brighter in dark. The old
                // `gold500` alias resolved to `rust400` after the rename, which
                // is *lighter* than the resting accent in light mode — so
                // pressing the primary button lifted its background to roughly
                // 2.4:1 against near-white `textOnAccent` and the label became
                // unreadable at the moment of the click.
                .fill(
                    configuration.isPressed
                        ? ZenDesign.Semantic.accentStrong
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

