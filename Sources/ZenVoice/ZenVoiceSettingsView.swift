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
    private enum Section: String, CaseIterable, Identifiable, Hashable {
        case home = "Home"
        case dictation = "Dictation"
        case languagesAndModels = "Language & Models"
        case personalization = "Personalization"
        case history = "History"
        case settings = "Settings"

        var id: String { rawValue }
        var toolbarTitle: String { rawValue }

        var icon: String {
            switch self {
            case .home:
                return "house"
            case .dictation:
                return "mic"
            case .languagesAndModels:
                return "globe"
            case .personalization:
                return "text.badge.star"
            case .history:
                return "clock.arrow.circlepath"
            case .settings:
                return "gearshape"
            }
        }

        static let groups: [(title: String?, sections: [Section])] = [
            (nil, [.home]),
            ("Configure", [.dictation, .languagesAndModels, .personalization]),
            ("Library", [.history]),
            (nil, [.settings]),
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsCommandPalette = false
    @State private var hoveredSection: Section?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .background(ZenDesign.Semantic.canvas)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                } detail: {
                    content
                        .id(selection)
                        .transition(.opacity)
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Text(selection.toolbarTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        ZenGlassContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                commandSearchButton
                                toolbarStatus
                                dictateToolbarButton
                            }
                        }
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
            }
        }
        // One violet tint drives native selection, focus, switches, links and
        // primary actions. Graphite remains the structural layer.
        .tint(ZenDesign.Semantic.accentFill)
        .frame(minWidth: 900, minHeight: 640)
        .preferredColorScheme(ZenAppearance.colorScheme)
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
        return sections + models + actions
    }


    private func sectionKeywords(_ section: Section) -> String {
        switch section {
        case .home:
            return "overview status ready start today usage"
        case .dictation:
            return "hotkey microphone audio overlay waveform doctor shortcut"
        case .languagesAndModels:
            return "language hinglish model engine whisper parakeet nemotron cohere"
        case .personalization:
            return "formatting vocabulary app rules commands corrections cloud"
        case .history:
            return "transcripts recordings insights audio search export"
        case .settings:
            return "privacy permissions data support updates about"
        }
    }

    private var commandSearchButton: some View {
        Button {
            showsCommandPalette = true
        } label: {
            Image(systemName: "slider.horizontal.3")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ZenDesign.Semantic.textSecondary)
            .frame(width: 28, height: 28)
            .zenGlassSurface(
                cornerRadius: ZenDesign.Radius.small,
                interactive: true
            )
        }
        .buttonStyle(ZenPressButtonStyle())
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Search commands")
        .help("Search commands (⌘K)")
    }

    private var toolbarStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.phase.statusTint)
                .frame(width: 6, height: 6)
            Text(appState.phase.label)
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .zenGlassSurface(
            cornerRadius: ZenDesign.Radius.pill,
            tint: appState.phase.statusTint
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(appState.phase.label)")
    }

    private var dictateToolbarButton: some View {
        let isListening = appState.phase == .listening
        return Button(action: toggleRecording) {
            HStack(spacing: 6) {
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                Text(isListening ? "Stop" : "Dictate")
                    .font(ZenDesign.Typography.captionStrong)
            }
            .foregroundStyle(
                isListening
                    ? ZenDesign.Semantic.textOnDanger
                    : ZenDesign.Semantic.textOnAccent
            )
            .padding(.horizontal, 11)
            .frame(height: 28)
            .zenGlassSurface(
                cornerRadius: ZenDesign.Radius.pill,
                tint: isListening
                    ? ZenDesign.Semantic.danger
                    : ZenDesign.Semantic.accentFill,
                interactive: true
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ZenPressButtonStyle(cornerRadius: ZenDesign.Radius.pill)
        )
        .accessibilityLabel(
            isListening ? "Stop dictating" : "Start dictating"
        )
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZenBrandMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ZenVoice")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text("On-device dictation")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ZenDesign.Spacing.sm)
            .padding(.vertical, ZenDesign.Spacing.sm)

            List {
                ForEach(
                    Array(Section.groups.enumerated()),
                    id: \.offset
                ) { _, group in
                    SwiftUI.Section {
                        ForEach(group.sections) { section in
                            Button {
                                selection = section
                            } label: {
                                sidebarLabel(section)
                            }
                            .buttonStyle(ZenPressButtonStyle())
                            .onHover { hovering in
                                if hovering {
                                    hoveredSection = section
                                } else if hoveredSection == section {
                                    hoveredSection = nil
                                }
                            }
                            .listRowBackground(
                                RoundedRectangle(
                                    cornerRadius: ZenDesign.Radius.small,
                                    style: .continuous
                                )
                                .fill(
                                    selection == section
                                        ? ZenDesign.Component.selectedNavigation
                                        : hoveredSection == section
                                            ? ZenDesign.Semantic.surfaceRaised.opacity(0.5)
                                            : Color.clear
                                )
                                .animation(
                                    ZenDesign.Motion.fast(reduceMotion),
                                    value: hoveredSection
                                )
                            )
                            .accessibilityAddTraits(
                                selection == section ? .isSelected : []
                            )
                        }
                    } header: {
                        if let title = group.title {
                            Text(title)
                                .font(ZenDesign.Typography.navGroup)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background {
            ZenMaterialSurface(
                material: .sidebar,
                tint: ZenDesign.Semantic.sidebar.opacity(0.88),
                fallback: ZenDesign.Semantic.sidebar
            )
                .ignoresSafeArea()
        }
        .navigationSplitViewColumnWidth(
            min: 220,
            ideal: ZenDesign.Layout.sidebarWidth,
            max: 300
        )
    }

    private func sidebarLabel(_ section: Section) -> some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            Image(systemName: section.icon)
                .font(ZenDesign.Typography.navIcon)
                .foregroundStyle(
                    selection == section
                        ? ZenDesign.Component.selectedNavigationIcon
                        : ZenDesign.Semantic.textTertiary
                )
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(section.rawValue)
                .font(
                    selection == section
                        ? ZenDesign.Typography.navRowSelected
                        : ZenDesign.Typography.navRow
                )
                .foregroundStyle(
                    selection == section
                        ? ZenDesign.Component.selectedNavigationLabel
                        : ZenDesign.Semantic.textSecondary
                )
                .lineLimit(1)
            Spacer(minLength: 4)
            if section == .history,
               historyViewModel.recoveryCount > 0 {
                Text("\(historyViewModel.recoveryCount)")
                    .font(ZenDesign.Typography.badge)
                    .foregroundStyle(ZenDesign.Semantic.textOnAccent)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 18)
                    .background {
                        Capsule().fill(ZenDesign.Semantic.accentFill)
                    }
                    .accessibilityLabel(
                        "\(historyViewModel.recoveryCount) items in Recovery Inbox"
                    )
            }
        }
        .frame(minHeight: 28)
        .accessibilityLabel(section.rawValue)
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
                    case .audio, .shortcuts:
                        selection = .dictation
                    case .models, .languages:
                        selection = .languagesAndModels
                    case .history, .insights:
                        selection = .history
                    case .help:
                        selection = .settings
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
        case .personalization:
            PersonalScreen(
                viewModel: viewModel,
                cloudAIViewModel: cloudAIViewModel,
                voiceProfileViewModel: voiceProfileViewModel,
                applicationProfileViewModel: applicationProfileViewModel
            )
        case .history:
            HistoryContainerScreen(
                historyViewModel: historyViewModel,
                audioHistoryViewModel: audioHistoryViewModel,
                insightsViewModel: insightsViewModel
            )
        case .settings:
            HelpAndAboutScreen(
                viewModel: viewModel,
                updatesViewModel: updatesViewModel,
                onboardingViewModel: onboardingViewModel,
                historyViewModel: historyViewModel,
                voiceProfileViewModel: voiceProfileViewModel,
                modelManagerViewModel: modelManagerViewModel,
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
        case .awaitingCloudReview:
            return "cloud"
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
        case .awaitingCloudReview:
            return ZenDesign.Semantic.accent
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

/// Shared geometry for the three button styles.
///
/// The painted control stays visually compact, but the frame the user can
/// actually hit is `Layout.hitTarget` tall. Drawing a 44pt box would make a
/// dense settings window look like a touch UI; making the *target* 44pt costs
/// nothing visually and is what the approved design asks for.
private struct ZenButtonShape<Background: View>: View {
    let label: AnyView
    let minWidth: CGFloat?
    let height: CGFloat
    let isPressed: Bool
    @ViewBuilder let background: Background
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .font(ZenDesign.Typography.button)
            // A button label never wraps. The painted background is a fixed
            // `height`, so a label allowed to run onto a second line is drawn
            // straight through the button's own border — "Replay setup guide"
            // broke onto two lines and spilled out of its rounded rect. The
            // button takes the width its label needs instead.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 13)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background { background }
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .strokeBorder(
                    isFocused && isEnabled
                        ? ZenDesign.Component.focusRing
                        : Color.clear,
                    lineWidth: 2
                )
                .padding(-2)
                .allowsHitTesting(false)
            }
            .scaleEffect(
                isPressed && isEnabled && !reduceMotion ? 0.98 : 1
            )
            .opacity(isEnabled ? (isPressed ? 0.88 : 1) : 0.45)
            .animation(
                ZenDesign.Motion.fast(reduceMotion),
                value: isPressed
            )
            .animation(
                ZenDesign.Motion.fast(reduceMotion),
                value: isFocused
            )
    }
}

struct ZenSecondaryButtonStyle: ButtonStyle {
    var minWidth: CGFloat? = nil
    var height: CGFloat = ZenDesign.Layout.control

    func makeBody(configuration: Configuration) -> some View {
        ZenButtonShape(
            label: AnyView(
                configuration.label
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
            ),
            minWidth: minWidth,
            height: height,
            isPressed: configuration.isPressed
        ) {
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
        ZenButtonShape(
            label: AnyView(
                configuration.label
                    .foregroundStyle(ZenDesign.Semantic.textOnAccent)
            ),
            minWidth: minWidth,
            height: ZenDesign.Layout.control,
            isPressed: configuration.isPressed
        ) {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.small,
                style: .continuous
            )
            // `accentStrong` moves the right way in both appearances:
            // darker than `accent` in light, brighter in dark — always away
            // from the label colour, never toward it. The regression this
            // guards against was a `gold500` alias that resolved to `rust400`,
            // *lighter* than the resting accent in light mode, so pressing the
            // button lifted its background to roughly 2.4:1 against the label
            // and the text vanished at the moment of the click.
            .fill(
                configuration.isPressed
                    ? ZenDesign.Semantic.accentStrong
                    : ZenDesign.Semantic.accentFill
            )
        }
    }
}

struct ZenDestructiveButtonStyle: ButtonStyle {
    var minWidth: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        ZenButtonShape(
            label: AnyView(
                configuration.label
                    .foregroundStyle(ZenDesign.Semantic.textOnDanger)
            ),
            minWidth: minWidth,
            height: ZenDesign.Layout.control,
            isPressed: configuration.isPressed
        ) {
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
