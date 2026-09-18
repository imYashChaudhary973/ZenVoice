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
    case history
    case insights
    case shortcuts
    case help
}

struct ZenVoiceSettingsView: View {
    private enum Section: String, CaseIterable, Identifiable, Hashable {
        case home = "General"
        case dictation = "Dictation"
        case models = "Models"
        case personalisation = "Personalisation"
        case history = "History"
        case updates = "Updates"
        case settings = "Settings"

        var id: String { rawValue }

        /// One gradient squircle per section; no two adjacent sections share
        /// a similar hue.
        var tileGradient: LinearGradient {
            switch self {
            case .home: return ZenDesign.Gradient.violet
            case .dictation: return ZenDesign.Gradient.rose
            case .models: return ZenDesign.Gradient.pink
            case .personalisation: return ZenDesign.Gradient.orchid
            case .history: return ZenDesign.Gradient.gold
            case .updates: return ZenDesign.Gradient.amber
            case .settings: return ZenDesign.Gradient.indigo
            }
        }

        var icon: String {
            switch self {
            case .home:
                return "slider.horizontal.3"
            case .dictation:
                return "mic"
            case .models:
                return "cpu"
            case .personalisation:
                return "text.badge.star"
            case .history:
                return "clock.arrow.circlepath"
            case .updates:
                return "arrow.triangle.2.circlepath"
            case .settings:
                return "gearshape"
            }
        }
    }

    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var audioHistoryViewModel: AudioHistoryViewModel
    @ObservedObject var updatesViewModel: UpdatesViewModel
    @ObservedObject var insightsViewModel: InsightsViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var onboardingViewModel:
        OnboardingViewModel
    @ObservedObject var appState: AppState
    @State private var selection: Section = .home
    @State private var modelMismatch: ModelMismatchAlert?
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
            } else {
                // Plain HStack columns. NavigationSplitView's bridged layout
                // mispositions content ~44pt above the window in this
                // translucent configuration; every visual here is custom
                // already, so the native split chrome buys nothing.
                HStack(alignment: .top, spacing: 0) {
                    sidebar
                        .frame(width: ZenDesign.Layout.sidebarWidth)
                    Rectangle()
                        .fill(ZenDesign.Semantic.border)
                        .frame(width: 1)
                        .ignoresSafeArea()
                    VStack(spacing: 0) {
                        content
                            .id(selection)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // The titlebar zone over the detail pane is empty glass
                    // (the traffic lights sit over the sidebar) — extend the
                    // column through it so the page title doesn't float 50pt
                    // below the window edge.
                    .ignoresSafeArea(edges: .top)
                }
            }
        }
        // The translucent dark glass shell. One layer behind everything:
        // sidebar and detail panes both ride it; only their tints differ.
        .background(ZenWindowGlass())
        // One pink tint drives native selection, focus, switches, links and
        // primary actions. Charcoal remains the structural layer.
        .tint(ZenDesign.Semantic.accentFill)
        .frame(minWidth: 900, minHeight: 640)
        // The dark glass system is appearance-independent: fixed dark values,
        // wallpaper bleeding through the shell.
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        ScrollView {
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
                // Clears the traffic lights with a snug gap — the lights end
                // ~24pt into the transparent titlebar over the sidebar.
                .padding(.top, 24)

                VStack(spacing: 2) {
                    ForEach(Section.allCases) { section in
                        Button {
                            selection = section
                        } label: {
                            sidebarLabel(section)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ZenPressButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                hoveredSection = section
                            } else if hoveredSection == section {
                                hoveredSection = nil
                            }
                        }
                        .background(
                            RoundedRectangle(
                                cornerRadius: ZenDesign.Radius.bar,
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
                            .animation(
                                ZenDesign.Motion.fast(reduceMotion),
                                value: selection
                            )
                        )
                        .accessibilityAddTraits(
                            selection == section ? .isSelected : []
                        )
                    }
                }
                .padding(.horizontal, ZenDesign.Spacing.sm)
                .padding(.bottom, ZenDesign.Spacing.lg)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        // The sidebar rides on the shared window glass with a slightly
        // lighter tint than the content pane — a second material would blur
        // the glass instead of the wallpaper. Only the background may ignore
        // the safe area; the content lays out inside it.
        .background {
            ZenDesign.Semantic.sidebar.opacity(0.35)
                .ignoresSafeArea()
        }
    }

    private func sidebarLabel(_ section: Section) -> some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            ZenGradientTile(
                systemImage: section.icon,
                gradient: section.tileGradient,
                size: ZenDesign.Layout.rowIcon
            )
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
                navigate: { destination in
                    switch destination {
                    case .audio, .shortcuts:
                        selection = .dictation
                    case .models:
                        selection = .models
                    case .history, .insights:
                        selection = .history
                    case .help:
                        selection = .settings
                    }
                }
            )
        case .dictation:
            DictationScreen(viewModel: viewModel)
        case .models:
            ZenScreen(
                icon: "cpu",
                title: "Models",
                subtitle: "Choose the on-device engine used for transcription."
            ) {
                ModelsScreen(
                    viewModel: modelManagerViewModel,
                    settingsViewModel: viewModel,
                    mismatchAlert: $modelMismatch
                )
            }
            .overlay {
                ModelMismatchToastOverlay(alert: $modelMismatch)
            }
        case .personalisation:
            PersonalScreen(
                viewModel: viewModel,
                voiceProfileViewModel: voiceProfileViewModel
            )
        case .history:
            HistoryContainerScreen(
                historyViewModel: historyViewModel,
                audioHistoryViewModel: audioHistoryViewModel,
                insightsViewModel: insightsViewModel
            )
        case .updates:
            ZenScreen(
                icon: "arrow.triangle.2.circlepath",
                title: "Updates",
                subtitle: "Check for new builds and how they are verified."
            ) {
                UpdatesScreen(viewModel: updatesViewModel)
            }
        case .settings:
            HelpAndAboutScreen(
                viewModel: viewModel,
                historyViewModel: historyViewModel,
                voiceProfileViewModel: voiceProfileViewModel,
                modelManagerViewModel: modelManagerViewModel,
                openModels: { selection = .models },
                openShortcuts: { selection = .dictation }
            )
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
///
/// The face is an Opensource UI 3D keycap. Press sinks one point and inverts
/// the inset; Reduce Motion keeps the shade swap and drops the travel.
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
            .offset(
                y: isPressed && isEnabled && !reduceMotion ? 1 : 0
            )
            .opacity(isEnabled ? 1 : 0.45)
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
            ZenKeycap(
                kind: .muted,
                isPressed: configuration.isPressed
            )
        }
    }
}

struct ZenPrimaryButtonStyle: ButtonStyle {
    var minWidth: CGFloat? = nil
    var height: CGFloat = ZenDesign.Layout.control
    func makeBody(configuration: Configuration) -> some View {
        ZenButtonShape(
            label: AnyView(
                configuration.label
                    .foregroundStyle(ZenDesign.Semantic.textOnAccent)
            ),
            minWidth: minWidth,
            height: height,
            isPressed: configuration.isPressed
        ) {
            // `accentStrong` moves the right way in both appearances:
            // darker than `accent` in light, brighter in dark — always away
            // from the label colour, never toward it. The regression this
            // guards against was a `gold500` alias that resolved to `rust400`,
            // *lighter* than the resting accent in light mode, so pressing the
            // button lifted its background to roughly 2.4:1 against the label
            // and the text vanished at the moment of the click.
            ZenKeycap(
                kind: .solid,
                isPressed: configuration.isPressed
            )
        }
    }
}

struct ZenDestructiveButtonStyle: ButtonStyle {
    var minWidth: CGFloat? = nil
    var height: CGFloat = ZenDesign.Layout.control

    func makeBody(configuration: Configuration) -> some View {
        ZenButtonShape(
            label: AnyView(
                configuration.label
                    .foregroundStyle(ZenDesign.Semantic.textOnDanger)
            ),
            minWidth: minWidth,
            height: height,
            isPressed: configuration.isPressed
        ) {
            ZenKeycap(
                kind: .danger,
                isPressed: configuration.isPressed
            )
        }
    }
}
