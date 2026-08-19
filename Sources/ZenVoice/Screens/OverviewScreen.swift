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

/// Home.
///
/// The page is organised around one question: *can I dictate right now, and
/// how?* Everything else on it is secondary and is laid out to look secondary.
///
/// This is the change from the previous revision, which opened with a display-
/// size **Today** heading over four usage statistics. That gave the loudest
/// object on the app's first screen to a word count — a number that is pleasant
/// to see and that nobody opens a dictation app to read — while the thing the
/// user actually came for, the shortcut and the state of the microphone, sat
/// below it in a quieter box. Purpose sets the hierarchy: the hero is now the
/// instrument, and the statistics are a single quiet strip underneath it.
struct OverviewScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var appState: AppState
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var insightsViewModel: InsightsViewModel
    let startDictation: () -> Void
    let replaySetup: () -> Void
    let navigate: (OverviewDestination) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZenScreen(
            icon: "house.fill",
            title: "Home",
            subtitle:
                "Everything runs on this Mac. Nothing to sign into, nothing to sync."
        ) {
            dictationHero
            todayStrip

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ZenDesign.Spacing.lg) {
                    setupColumn
                    recentActivityPanel
                        .frame(width: 340)
                }
                VStack(spacing: ZenDesign.Spacing.lg) {
                    setupColumn
                    recentActivityPanel
                }
            }
        }
        .onAppear {
            viewModel.refreshSystemStatus()
            historyViewModel.refresh()
            insightsViewModel.refresh()
        }
    }

    // MARK: - Hero

    /// The instrument. State, the shortcut that operates it, and the button
    /// that does the same thing for anyone who would rather click.
    private var dictationHero: some View {
        ZenPanel(padding: ZenDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: ZenDesign.Spacing.xl) {
                    VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                        // Live state, in words, at a size that can be read from
                        // across the desk. The dot is the only coloured mark in
                        // the block — and because it is the only one, its
                        // colour is worth reading.
                        HStack(spacing: 9) {
                            statusIndicator
                            Text(statusTitle)
                                .zenType(
                                    ZenDesign.Typography.pageTitle,
                                    tracking: ZenDesign.Tracking.pageTitle
                                )
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // While listening, the level meter replaces the
                        // shortcut hint: the shortcut has already been used, so
                        // repeating it is noise, and what the user needs
                        // instead is proof the microphone is hearing them.
                        if appState.phase == .listening {
                            WaveformView(model: appState.audioLevel)
                                .transition(.opacity)
                        } else {
                            HStack(spacing: ZenDesign.Spacing.xs) {
                                Text("Press")
                                    .zenType(
                                        ZenDesign.Typography.body,
                                        tracking: ZenDesign.Tracking.body
                                    )
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                                ZenKbdGroup(
                                    combo: viewModel.currentShortcut.displayName
                                )
                                Text("in any app.")
                                    .zenType(
                                        ZenDesign.Typography.body,
                                        tracking: ZenDesign.Tracking.body
                                    )
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }
                            .transition(.opacity)
                        }
                    }

                    Spacer(minLength: ZenDesign.Spacing.md)

                    VStack(alignment: .trailing, spacing: ZenDesign.Spacing.xs) {
                        Button(action: startDictation) {
                            Label(
                                appState.phase == .listening
                                    ? "Stop" : "Start dictating",
                                systemImage: appState.phase == .listening
                                    ? "stop.fill" : "mic.fill"
                            )
                        }
                        .buttonStyle(ZenPrimaryButtonStyle())

                        ZenBadge(
                            text: "Local · encrypted · on-device",
                            kind: .neutral,
                            systemImage: "lock.fill"
                        )
                    }
                }
                .animation(
                    ZenDesign.Motion.standard(reduceMotion),
                    value: appState.phase
                )

                // A hairline *inside* one card, separating the instrument from
                // its settings. This is the honest use of a rule: two regions
                // of one object. The previous revision instead put these facts
                // in four separately-bordered boxes, which claimed they were
                // four objects when they are one status line.
                Rectangle()
                    .fill(ZenDesign.Semantic.border)
                    .frame(height: 1)
                    .padding(.vertical, ZenDesign.Spacing.lg)

                HStack(spacing: 0) {
                    heroFact(
                        "Microphone",
                        value: viewModel.selectedMicrophoneName,
                        destination: .audio
                    )
                    heroFactDivider
                    heroFact(
                        "Language",
                        value: appState.languageProfile.displayName,
                        destination: .languages
                    )
                    heroFactDivider
                    heroFact(
                        "Model",
                        value: modelDisplayName,
                        destination: .models
                    )
                }
            }
        }
    }

    /// The status dot, with a halo while something is actually happening.
    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(statusTint.opacity(0.25))
                .frame(width: 22, height: 22)
                .opacity(isLive ? 1 : 0)
            Circle()
                .fill(statusTint)
                .frame(width: 10, height: 10)
        }
        .frame(width: 22, height: 22)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: statusTint)
        .accessibilityHidden(true)
    }

    private var isLive: Bool {
        switch appState.phase {
        case .listening, .transcribing, .inserting, .awaitingCloudReview:
            return true
        default:
            return false
        }
    }

    private var heroFactDivider: some View {
        Rectangle()
            .fill(ZenDesign.Semantic.border)
            .frame(width: 1, height: 26)
            .padding(.horizontal, ZenDesign.Spacing.md)
            .accessibilityHidden(true)
    }

    /// One fact about how dictation is currently configured, and a way to go
    /// and change it.
    ///
    /// These are buttons rather than labels because every one of them names a
    /// setting that lives on another screen — a control placed next to what it
    /// affects beats making the user go and find it.
    private func heroFact(
        _ label: String,
        value: String,
        destination: OverviewDestination
    ) -> some View {
        Button {
            navigate(destination)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .zenType(
                        ZenDesign.Typography.caption,
                        tracking: ZenDesign.Tracking.caption
                    )
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .lineLimit(1)
                Text(value)
                    .zenType(
                        ZenDesign.Typography.bodyStrong,
                        tracking: ZenDesign.Tracking.body
                    )
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressableStyle())
        .accessibilityLabel("\(label): \(value). Open settings.")
    }

    // MARK: - Today

    /// Today's usage as one quiet strip.
    ///
    /// Four numbers, no icons, no accent, no borders between them. They used to
    /// be the hero of this page at 22pt bold with a jade glyph beside each; a
    /// fact you glance at once a day does not need to be the largest thing on
    /// the screen, and four coloured icons in a row is the exact pattern that
    /// made the old window read as an analytics dashboard.
    private var todayStrip: some View {
        let today = insightsViewModel.snapshot.today
        let streak = insightsViewModel.snapshot.currentStreakDays

        return ZenPanel(padding: ZenDesign.Spacing.lg) {
            HStack(alignment: .center, spacing: 0) {
                todayFigure(
                    String(today.wordCount),
                    label: "words today"
                )
                todayFigure(
                    formattedDuration(today.durationSeconds),
                    label: "spoken"
                )
                todayFigure(
                    String(today.dictationCount),
                    label: today.dictationCount == 1 ? "session" : "sessions"
                )
                todayFigure(
                    today.topApplicationName ?? "—",
                    label: today.hasActivity ? "top app" : "no activity"
                )

                if streak > 0 {
                    ZenBadge(
                        text: "\(streak) day\(streak == 1 ? "" : "s")",
                        kind: .neutral,
                        systemImage: "flame.fill"
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Today's usage. \(today.pillSummary)."))
    }

    private func todayFigure(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 19, weight: .semibold).monospacedDigit())
                .tracking(-0.3)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .zenType(
                    ZenDesign.Typography.caption,
                    tracking: ZenDesign.Tracking.caption
                )
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 {
            return "\(total)s"
        }
        let minutes = total / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: - Status text

    /// Whether ZenVoice can actually do the thing this screen promises.
    ///
    /// Without Microphone there is nothing to transcribe; without Accessibility
    /// the text cannot be typed into the app the user is in and silently goes
    /// to the clipboard instead. Claiming "Ready to dictate" in either case is
    /// a promise the app cannot keep.
    private var isFullyReady: Bool {
        viewModel.microphoneStatus.isAllowed
            && viewModel.accessibilityStatus.isAllowed
    }

    private var statusTitle: String {
        switch appState.phase {
        case .idle:
            if !viewModel.microphoneStatus.isAllowed {
                return "Microphone access needed"
            }
            if !viewModel.accessibilityStatus.isAllowed {
                return "Ready — text goes to the clipboard"
            }
            return "Ready to dictate"
        case .listening:
            return "Listening"
        case .transcribing:
            return "Transcribing"
        case .awaitingCloudReview:
            return "Waiting for your cloud review"
        case .inserting:
            return "Inserting"
        case .success:
            return "Inserted"
        case .error(let message):
            return message
        }
    }

    private var statusTint: Color {
        switch appState.phase {
        case .idle:
            if !viewModel.microphoneStatus.isAllowed {
                return ZenDesign.Semantic.danger
            }
            return isFullyReady
                ? ZenDesign.Semantic.success
                : ZenDesign.Semantic.warn
        case .success:
            return ZenDesign.Semantic.success
        case .listening:
            return ZenDesign.Semantic.accent
        case .transcribing, .inserting:
            return ZenDesign.Semantic.warn
        case .awaitingCloudReview:
            return ZenDesign.Semantic.accent
        case .error:
            return ZenDesign.Semantic.danger
        }
    }

    // MARK: - Setup

    private var setupColumn: some View {
        VStack(spacing: ZenDesign.Spacing.lg) {
            permissionsPanel
            if historyViewModel.recoveryCount > 0 {
                recoveryNote
            }
        }
    }

    private var permissionsPanel: some View {
        ZenCard(
            icon: "checkmark.shield",
            title: "Permissions",
            subtitle: "What macOS has to allow before ZenVoice can type.",
            trailing: {
                Button("Replay setup", action: replaySetup)
                    .buttonStyle(ZenSecondaryButtonStyle())
            },
            content: {
                VStack(spacing: ZenDesign.Spacing.xs) {
                    permissionRow(
                        icon: "mic",
                        title: "Microphone",
                        detail: "So ZenVoice can hear you.",
                        status: viewModel.microphoneStatus,
                        action: viewModel.requestMicrophoneAccess
                    )
                    permissionRow(
                        icon: "accessibility",
                        title: "Accessibility",
                        detail: "So ZenVoice can type into other apps.",
                        status: viewModel.accessibilityStatus,
                        action: viewModel.requestAccessibilityAccess
                    )
                }
            }
        )
    }

    /// Shows the state *and* offers the fix.
    ///
    /// This panel used to be read-only: it told the user something was missing
    /// and then made them go and find Privacy & Data to do anything about it.
    private func permissionRow(
        icon: String,
        title: String,
        detail: String,
        status: SettingsViewModel.PermissionStatus,
        action: @escaping () -> Void
    ) -> some View {
        ZenInsetRow {
            HStack(spacing: ZenDesign.Spacing.sm) {
                // Colour here is genuine state, not decoration: green means
                // granted, amber means this is why dictation will not work.
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        status.isAllowed
                            ? ZenDesign.Semantic.success
                            : ZenDesign.Semantic.warn
                    )
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .zenType(
                            ZenDesign.Typography.bodyStrong,
                            tracking: ZenDesign.Tracking.body
                        )
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(detail)
                        .zenType(
                            ZenDesign.Typography.caption,
                            tracking: ZenDesign.Tracking.caption
                        )
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: ZenDesign.Spacing.xs)
                if let actionTitle = status.actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .accessibilityLabel(
                            "\(actionTitle) \(title) permission"
                        )
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.success)
                        .accessibilityLabel(status.title)
                }
            }
            .frame(minHeight: 36)
        }
    }

    // MARK: - Recent activity

    private var recentActivityPanel: some View {
        let recent = Array(historyViewModel.records.prefix(5))
        return ZenCard(
            icon: "clock",
            title: "Recent",
            trailing: {
                Button("See all") { navigate(.history) }
                    .buttonStyle(.plain)
                    .zenType(
                        ZenDesign.Typography.captionStrong,
                        tracking: ZenDesign.Tracking.caption
                    )
                    .foregroundStyle(ZenDesign.Semantic.accent)
            },
            content: {
                if recent.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No dictations yet")
                            .zenType(
                                ZenDesign.Typography.bodyStrong,
                                tracking: ZenDesign.Tracking.body
                            )
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text("Your latest will appear here.")
                            .zenType(
                                ZenDesign.Typography.caption,
                                tracking: ZenDesign.Tracking.caption
                            )
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, ZenDesign.Spacing.sm)
                } else {
                    // A plain list separated by inset hairlines — the macOS
                    // idiom — rather than five individually-bordered chips
                    // stacked with gaps. Five boxes in a column read as five
                    // unrelated objects; five rows read as one list.
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) {
                            index, record in
                            if index > 0 {
                                Rectangle()
                                    .fill(ZenDesign.Semantic.border)
                                    .frame(height: 1)
                            }
                            recentRow(record)
                        }
                    }
                }
            }
        )
    }

    private func recentRow(_ record: DictationRecord) -> some View {
        Button {
            navigate(.history)
        } label: {
            HStack(spacing: ZenDesign.Spacing.sm) {
                Text(record.targetAppName ?? "Unknown app")
                    .zenType(
                        ZenDesign.Typography.body,
                        tracking: ZenDesign.Tracking.body
                    )
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: ZenDesign.Spacing.xs)
                Text(
                    record.startedAt.formatted(
                        .relative(presentation: .named)
                    )
                )
                .zenType(
                    ZenDesign.Typography.caption,
                    tracking: ZenDesign.Tracking.caption
                )
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .lineLimit(1)
            }
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressableStyle())
    }

    private var recoveryNote: some View {
        ZenBanner(
            kind: .warn,
            icon: "exclamationmark.triangle.fill",
            text: "\(historyViewModel.recoveryCount) item"
                + (historyViewModel.recoveryCount == 1 ? "" : "s")
                + " waiting in Recovery."
        )
        .onTapGesture { navigate(.history) }
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
}
