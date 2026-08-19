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

        /// Filled glyphs throughout. Mixing outline and filled symbols in one
        /// rail makes the outlined ones read as disabled.
        var icon: String {
            switch self {
            case .home:
                return "house.fill"
            case .dictation:
                return "waveform"
            case .languagesAndModels:
                return "globe"
            case .formatting:
                return "wand.and.stars"
            case .commands:
                return "terminal.fill"
            case .personal:
                return "character.book.closed.fill"
            case .history:
                return "clock.fill"
            case .privacy:
                return "lock.shield.fill"
            case .help:
                return "questionmark.circle.fill"
            }
        }

        /// Four labelled groups plus an unlabelled Home, which is the shape
        /// the approved design specifies: what you set up, what you use, what
        /// it recorded, and where to get help. The previous rail gave all nine
        /// entries their own one-item heading, so the headings carried no
        /// information — every label was just the row beneath it, restated.
        static let groups: [(title: String?, sections: [Section])] = [
            (nil, [.home]),
            (
                "Configure",
                [.dictation, .languagesAndModels, .formatting, .personal]
            ),
            ("Use", [.commands]),
            ("Activity", [.history]),
            ("Help", [.privacy, .help])
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
    @State private var hoveredSection: Section?
    @State private var showsCommandPalette = false
    /// Shared namespace for the sidebar's selection highlight, so it slides
    /// between rows instead of cross-fading in place.
    @Namespace private var navSelection
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
                .background(ZenDesign.Semantic.canvas)
            } else {
                // The sidebar runs the full height of the window, under the
                // traffic lights, and the content column carries its own top
                // bar. A single title bar spanning both would cut the sidebar
                // material off below the window's rounded top corners.
                HStack(spacing: 0) {
                    sidebar
                    ZStack(alignment: .top) {
                        // The window is created with a clear background, so
                        // this column has to bring its own material — without
                        // it the translucent canvas above would be showing
                        // straight through to an unblurred desktop.
                        //
                        // `.underWindowBackground` rather than the sidebar's
                        // material: it is the heavier of the two, which is
                        // exactly the hierarchy wanted. The structural column
                        // (sidebar) reads as the thinner, more transparent
                        // glass; the content it frames sits on something more
                        // solid, so text has a stable surface to live on.
                        ZenVisualEffect(material: .underWindowBackground)

                        // A *translucent* tint over that material, not an
                        // opaque fill. That single point of alpha is what keeps
                        // a trace of the desktop under the page and stops the
                        // window reading as a rectangle of dead grey pasted
                        // onto the screen.
                        ZenDesign.Semantic.canvas

                        content
                            // Sections cross-fade and rise a few points rather
                            // than cutting. The offset is small on purpose: it
                            // says "this replaced that" without the page
                            // appearing to physically travel, which at this
                            // size would read as a slide-in animation from a
                            // web framework.
                            .id(selection)
                            .transition(
                                .opacity.combined(
                                    with: .offset(y: 6)
                                )
                            )
                            .padding(.top, ZenDesign.Layout.titleBar)

                        topBar
                    }
                    .animation(
                        ZenDesign.Motion.standard(reduceMotion),
                        value: selection
                    )
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
        // Deliberately no window-wide background: an opaque fill here would
        // sit behind the sidebar's `behindWindow` material and flatten it to
        // a plain grey panel. Each column paints its own surface instead.
        //
        // One tint for the whole window. Native controls — switches, pop-up
        // buttons, steppers, text selection — default to the *system* accent,
        // which is blue on a stock Mac. Tinting them individually meant every
        // new control shipped blue until someone noticed; a handful already
        // had, so the Formatting screen mixed blue switches with green ones.
        .tint(ZenDesign.Semantic.accent)
        .frame(minWidth: 940, minHeight: 660)
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

    /// Top bar of the content column: the app's name on the left, one capsule
    /// cluster of global actions on the right.
    ///
    /// It sits *beside* the sidebar rather than above it, so the traffic
    /// lights land on the sidebar material and the window keeps a single
    /// unbroken vertical edge between the two columns.
    private var topBar: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            // The wordmark, not a page title. The page states its own name at
            // display size a few points below this, and the sidebar states it a
            // third time — three labels for one fact was the clearest thing
            // wrong with the old header.
            ZenBrandMark(size: 18)
            Text("ZenVoice")
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)

            Spacer()

            ZenToolbarCluster {
                ZenToolbarButton(
                    systemImage: appState.phase.statusIcon,
                    title: appState.phase.label,
                    label: "Status: \(appState.phase.label)",
                    tint: appState.phase.statusTint,
                    action: {}
                )
                .disabled(true)
                ZenToolbarDivider()
                ZenToolbarButton(
                    systemImage: "command",
                    label: "Open command palette"
                ) {
                    showsCommandPalette = true
                }
                ZenToolbarDivider()
                ZenToolbarButton(
                    systemImage: selectedAppearance.systemImage,
                    label: appearanceButtonLabel
                ) {
                    appearance = nextAppearance.rawValue
                }
            }

            dictateButton
        }
        .padding(.horizontal, ZenDesign.Spacing.xl)
        .frame(height: ZenDesign.Layout.titleBar)
        .frame(maxWidth: .infinity)
    }

    private var dictateButton: some View {
        let isListening = appState.phase == .listening
        return Button(action: toggleRecording) {
            HStack(spacing: 6) {
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(isListening ? "Stop" : "Dictate")
                    .font(ZenDesign.Typography.captionStrong)
            }
            // Both fills are deep enough to carry white, so the label colour
            // does not have to move when the fill switches to red.
            .foregroundStyle(
                isListening
                    ? ZenDesign.Semantic.textOnDanger
                    : ZenDesign.Semantic.textOnAccent
            )
            .padding(.horizontal, 14)
            .frame(height: ZenDesign.Layout.control)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isListening
                            ? ZenDesign.Semantic.danger
                            : ZenDesign.Semantic.accentFill
                    )
                    // The one saturated object in the chrome, so it gets a
                    // coloured shadow rather than a black one — a lit control
                    // spills its own colour onto what it sits on, and this is
                    // what separates a primary action from a green rectangle.
                    .shadow(
                        color: (isListening
                            ? ZenDesign.Semantic.danger
                            : ZenDesign.Semantic.accentFill).opacity(0.35),
                        radius: 8,
                        y: 3
                    )
            }
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressableStyle())
        .animation(ZenDesign.Motion.standard(reduceMotion), value: isListening)
        .accessibilityLabel(
            isListening ? "Stop dictating" : "Start dictating"
        )
    }

    /// Appearance cycles System → Light → Dark on click.
    ///
    /// A three-way segmented control used to sit in the sidebar footer, which
    /// spent a permanent 44pt of navigation space on a setting most people
    /// touch once. One toolbar button that names both its current value and
    /// its next one carries the same information.
    private var nextAppearance: ZenAppearance {
        switch selectedAppearance {
        case .system:
            return .light
        case .light:
            return .dark
        case .dark:
            return .system
        }
    }

    private var appearanceButtonLabel: String {
        "Appearance: \(selectedAppearance.title). "
            + "Switch to \(nextAppearance.title)."
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(
                    Array(Section.groups.enumerated()),
                    id: \.offset
                ) { index, group in
                    if let title = group.title {
                        Text(title.uppercased())
                            .font(ZenDesign.Typography.navGroup)
                            .tracking(ZenDesign.Tracking.eyebrow)
                            // Secondary, not tertiary. These headings sit on a
                            // translucent panel over whatever wallpaper is
                            // behind the window; at tertiary they vanished
                            // against a light one.
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                            .padding(.horizontal, 10)
                            .padding(.top, index == 0 ? 4 : 20)
                            .padding(.bottom, 5)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(group.sections) { section in
                        sidebarItem(section)
                    }
                }
            }
            .padding(.horizontal, 10)
            // Clears the traffic lights, which the window draws over this
            // column rather than over a separate title bar.
            .padding(.top, ZenDesign.Layout.titleBar)
            .padding(.bottom, ZenDesign.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(
                ZenDesign.Motion.standard(reduceMotion),
                value: selection
            )
        }
        .scrollIndicators(.hidden)
        .frame(width: ZenDesign.Layout.sidebarWidth)
        .background {
            ZenVisualEffect(material: .sidebar)
                .overlay(ZenDesign.Semantic.sidebar)
        }
        // A single hairline, and it is the *only* hard edge in the window.
        // Two columns of different material meeting need one line to say
        // where; everything else here is separated by light and value.
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ZenDesign.Semantic.border)
                .frame(width: 1)
        }
    }

    private func sidebarItem(_ section: Section) -> some View {
        let selected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(ZenDesign.Typography.navIcon)
                    .frame(width: ZenDesign.Layout.navIcon)
                    // Monochrome unless selected. Every one of these nine
                    // glyphs used to be jade at rest, which is the single
                    // change that most flattened the old rail: with all nine
                    // accented, the accent on the *selected* one carried no
                    // information, so the active row had to be found by
                    // reading rather than by looking.
                    .foregroundStyle(
                        selected
                            ? ZenDesign.Component.selectedNavigationIcon
                            : ZenDesign.Semantic.textTertiary
                    )
                Text(section.rawValue)
                    .font(
                        selected
                            ? ZenDesign.Typography.navRowSelected
                            : ZenDesign.Typography.navRow
                    )
                    .foregroundStyle(
                        selected
                            ? ZenDesign.Component.selectedNavigationLabel
                            : ZenDesign.Semantic.textSecondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if section == .history,
                   historyViewModel.recoveryCount > 0 {
                    Text("\(historyViewModel.recoveryCount)")
                        .font(ZenDesign.Typography.badge)
                        .foregroundStyle(ZenDesign.Semantic.accent)
                        .padding(.horizontal, 6)
                        .frame(height: 17)
                        .background {
                            Capsule().fill(ZenDesign.Semantic.accentMuted)
                        }
                        .accessibilityLabel(
                            "\(historyViewModel.recoveryCount) items in Recovery Inbox"
                        )
                }
            }
            .padding(.horizontal, 10)
            .frame(height: ZenDesign.Layout.navRow)
            .background {
                // The selection is one shape that *moves* between rows rather
                // than one that fades out here and in over there. Because the
                // move is a spring, clicking a third row part-way through
                // redirects the highlight from wherever it currently is — no
                // waiting for the first move to land, and no jump.
                ZStack {
                    if selected {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.medium,
                            style: .continuous
                        )
                        .fill(ZenDesign.Component.selectedNavigation)
                        .matchedGeometryEffect(
                            id: "nav-selection",
                            in: navSelection
                        )
                    } else if hoveredSection == section {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.medium,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.textPrimary.opacity(0.055))
                    }
                }
            }
            // The painted row is shorter than the clickable one so consecutive
            // rows nearly touch and the rail reads as one list, while the hit
            // frame still meets the 44pt target.
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressableStyle())
        .onHover { hovering in
            hoveredSection = hovering ? section : nil
        }
        .animation(ZenDesign.Motion.fast(reduceMotion), value: hoveredSection)
        .accessibilityLabel(section.rawValue)
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
    /// Whether the control is currently held. Drives the press scale, which has
    /// to live here rather than in each style so all three respond identically.
    var isPressed = false
    @ViewBuilder let background: Background

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // Feedback on press-*down*, not on the click completing. The
            // previous styles changed only their fill colour, which on a dark
            // surface is a few percent of luminance and effectively invisible;
            // scale is felt even when it is not consciously seen.
            .scaleEffect(
                isPressed && !reduceMotion
                    ? ZenDesign.Motion.pressScale
                    : 1
            )
            .animation(ZenDesign.Motion.fast(reduceMotion), value: isPressed)
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .contentShape(Rectangle())
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
                ZenDesign.Semantic.textPrimary
                    .opacity(configuration.isPressed ? 0.14 : 0.08)
            )
            .overlay(alignment: .top) {
                // The same lit top edge every raised surface in the window
                // carries, so a secondary button reads as the same material as
                // the card it sits on rather than as an outlined shape.
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            ZenDesign.Semantic.edgeHighlight,
                            .clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
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
            // `accentFill`, not `accent`. These two weights exist precisely so
            // that a control carrying a white label uses the deep one — and
            // this style was reaching for the *foreground* weight, which in
            // dark mode is the light mint. White on that lands near 2.3:1, so
            // every primary button in the window was failing contrast while the
            // token that would have fixed it sat one line away.
            .fill(
                configuration.isPressed
                    ? ZenDesign.Semantic.accentStrong
                    : ZenDesign.Semantic.accentFill
            )
            .shadow(
                color: ZenDesign.Semantic.accentFill.opacity(
                    configuration.isPressed ? 0.16 : 0.34
                ),
                radius: 8,
                y: 3
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

