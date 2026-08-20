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

struct OverviewScreen: View {
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
            icon: "house.fill",
            title: "Overview",
            subtitle:
                "Everything runs on this Mac. Nothing to sign into, nothing to sync."
        ) {
            homeGrid
        }
    }

    private var homeGrid: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
            todayMetrics
            statusOverview
            // Two columns while both fit, one when they do not.
            //
            // This was a plain `HStack` with a fixed 320pt side column and a
            // `minWidth: 300` main column. A minimum width is a request, not a
            // constraint: the Actions card cannot shrink below the two buttons
            // it holds, so at the narrowest window the row needed about 690pt
            // in a 652pt pane and SwiftUI let it overflow — the card spilled
            // roughly 20pt past its column on each side and ran under the
            // Recent activity card beside it. `ViewThatFits` measures the
            // side-by-side arrangement against the space actually available
            // and stacks instead of overflowing.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ZenDesign.Spacing.lg) {
                    homeMainColumn
                    homeSideColumn
                        .frame(width: 320)
                }
                VStack(spacing: ZenDesign.Spacing.lg) {
                    homeMainColumn
                    homeSideColumn
                }
            }
        }
    }

    private var homeMainColumn: some View {
        VStack(spacing: ZenDesign.Spacing.lg) {
            quickActionsPanel
            permissionsPanel
            frequentAppsPanel
        }
    }

    // MARK: - Today

    /// Usage stays quiet until there is something useful to report. Once the
    /// user has dictated, one compact summary replaces four empty hero cards.
    @ViewBuilder
    private var todayMetrics: some View {
        let today = insightsViewModel.snapshot.today
        if today.dictationCount > 0 {
            ZenPanel(padding: ZenDesign.Spacing.md) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ZenDesign.Spacing.xl) {
                        metric(
                            today.wordCount.formatted(),
                            label: "words",
                            icon: "textformat"
                        )
                        metric(
                            formattedDuration(today.durationSeconds),
                            label: "speaking",
                            icon: "clock"
                        )
                        metric(
                            today.dictationCount.formatted(),
                            label: "sessions",
                            icon: "mic"
                        )
                        if let app = today.topApplicationName {
                            metric(app, label: "top app", icon: "macwindow")
                        }
                    }
                    VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                        metric(
                            today.wordCount.formatted(),
                            label: "words today",
                            icon: "textformat"
                        )
                        metric(
                            formattedDuration(today.durationSeconds),
                            label: "speaking time",
                            icon: "clock"
                        )
                        metric(
                            today.dictationCount.formatted(),
                            label: "sessions",
                            icon: "mic"
                        )
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func metric(
        _ value: String,
        label: String,
        icon: String
    ) -> some View {
        HStack(spacing: ZenDesign.Spacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(ZenDesign.Semantic.accent)
                .accessibilityHidden(true)
            Text(value)
                .font(ZenDesign.Typography.bodyStrong)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Text(label)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
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

    // MARK: - Status

    private var statusOverview: some View {
        ZenPanel(padding: ZenDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                HStack(spacing: ZenDesign.Spacing.sm) {
                    statusDot
                    Text(statusTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Spacer(minLength: ZenDesign.Spacing.md)
                    ZenBadge(
                        text: "Local · encrypted · on-device",
                        kind: .neutral,
                        systemImage: "lock.fill"
                    )
                }

                HStack(spacing: ZenDesign.Spacing.xs) {
                    statusItem(
                        "Shortcut",
                        value: viewModel.currentShortcut.displayName,
                        isKeycap: true
                    )
                    statusItem(
                        "Microphone",
                        value: microphoneDisplayName
                    )
                    statusItem(
                        "Language",
                        value: appState.languageProfile.displayName
                    )
                    statusItem("Model", value: modelDisplayName)
                }
            }
        }
    }

    /// Whether ZenVoice can actually do the thing this screen promises.
    ///
    /// Without Microphone there is nothing to transcribe; without
    /// Accessibility the text cannot be typed into the app the user is in and
    /// silently goes to the clipboard instead. Claiming "Ready to dictate" in
    /// either case is a promise the app cannot keep.
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
                return "Ready — text will go to the clipboard"
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

    private var statusDot: some View {
        Circle()
            .fill(statusTint)
            .frame(width: 9, height: 9)
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

    /// Height of the value line in a status tile.
    ///
    /// Pinned so a keycap tile and a text tile are the same height. A `ZenKbd`
    /// chip is 24pt and a line of `bodyStrong` is about 16, so with the row
    /// left to size itself the Shortcut tile stood 8pt taller than its three
    /// neighbours and pushed its own label off their baseline.
    private static let statusValueHeight: CGFloat = 24

    private func statusItem(
        _ label: String,
        value: String,
        isKeycap: Bool = false
    ) -> some View {
        ZenInsetRow {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .lineLimit(1)
                Group {
                    if isKeycap {
                        ZenKbdGroup(combo: value)
                    } else {
                        Text(value)
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(
                    height: Self.statusValueHeight,
                    alignment: .leading
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Side column

    private var homeSideColumn: some View {
        VStack(spacing: ZenDesign.Spacing.lg) {
            recentActivityPanel
            if historyViewModel.recoveryCount > 0 {
                recoveryNote
            }
            Spacer(minLength: 0)
        }
    }

    private var quickActionsPanel: some View {
        ZenCard(
            icon: "bolt.fill",
            title: "Actions",
            subtitle: "Start talking, or walk through setup again."
        ) {
            // Button labels never wrap, so a row of them has a hard minimum
            // width. Side by side while that fits, stacked when it does not —
            // otherwise the card is forced wider than its column.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ZenDesign.Spacing.sm) {
                    startDictatingButton
                    replaySetupButton
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                    startDictatingButton
                    replaySetupButton
                }
            }
        }
    }

    private var startDictatingButton: some View {
        Button(action: startDictation) {
            Label("Start dictating", systemImage: "mic.fill")
        }
        .buttonStyle(ZenPrimaryButtonStyle())
    }

    private var replaySetupButton: some View {
        Button("Replay setup guide", action: replaySetup)
            .buttonStyle(ZenSecondaryButtonStyle())
    }

    private var permissionsPanel: some View {
        ZenCard(
            icon: "checkmark.shield.fill",
            title: "Permissions",
            subtitle: "What macOS has to allow before ZenVoice can type."
        ) {
            VStack(spacing: ZenDesign.Spacing.xs) {
                permissionRow(
                    icon: "mic.fill",
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
                tintedIconChip(
                    icon,
                    tint: status.isAllowed
                        ? ZenDesign.Semantic.success
                        : ZenDesign.Semantic.warn
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(detail)
                        .font(ZenDesign.Typography.caption)
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
                    ZenBadge(
                        text: status.title,
                        kind: status.isAllowed ? .success : .warn,
                        systemImage: status.isAllowed ? "checkmark" : nil
                    )
                }
            }
            .frame(minHeight: 38)
        }
    }

    private var recentActivityPanel: some View {
        let recent = Array(historyViewModel.records.prefix(4))
        return ZenCard(
            icon: "clock.fill",
            title: "Recent activity",
            trailing: {
                Button("See all") { navigate(.history) }
                    .buttonStyle(ZenPressButtonStyle())
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.accent)
            },
            content: {
                VStack(spacing: ZenDesign.Spacing.xs) {
                    if recent.isEmpty {
                        ZenInsetRow {
                            HStack(spacing: ZenDesign.Spacing.sm) {
                                tintedIconChip(
                                    "text.bubble",
                                    tint: ZenDesign.Semantic.textTertiary
                                )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("No dictations yet")
                                        .font(
                                            ZenDesign.Typography.bodyStrong
                                        )
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textPrimary
                                        )
                                    Text("Your latest will appear here.")
                                        .font(ZenDesign.Typography.caption)
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textTertiary
                                        )
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 38)
                        }
                    } else {
                        ForEach(recent) { record in
                            Button {
                                navigate(.history)
                            } label: {
                                ZenInsetRow {
                                    HStack(spacing: ZenDesign.Spacing.sm) {
                                        tintedIconChip(
                                            "text.bubble.fill",
                                            tint: ZenDesign.Semantic.accent
                                        )
                                        Text(
                                            record.targetAppName
                                                ?? "Unknown app"
                                        )
                                        .font(ZenDesign.Typography.body)
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textPrimary
                                        )
                                        .lineLimit(1)
                                        Spacer(minLength: ZenDesign.Spacing.xs)
                                        Text(
                                            record.startedAt.formatted(
                                                .relative(presentation: .named)
                                            )
                                        )
                                        .font(ZenDesign.Typography.caption)
                                        .foregroundStyle(
                                            ZenDesign.Semantic.textTertiary
                                        )
                                        .lineLimit(1)
                                    }
                                    .frame(minHeight: 30)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(ZenPressButtonStyle())
                        }
                    }
                }
            }
        )
    }

    private var frequentAppsPanel: some View {
        let applications = Array(
            insightsViewModel.snapshot.topApplications.prefix(4)
        )
        return ZenCard(
            icon: "macwindow",
            title: "Frequently Used Apps",
            subtitle: "Where your dictation time goes."
        ) {
            if applications.isEmpty {
                ZenInsetRow {
                    Text("App usage appears after your first saved dictation.")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(applications) { application in
                        ZenMeterRow(
                            label: application.displayName,
                            percent: appShare(application.wordCount)
                        )
                    }
                }
            }
        }
    }

    private func appShare(_ wordCount: Int) -> Int {
        let total = max(1, insightsViewModel.snapshot.totalWordCount)
        return Int((Double(wordCount) / Double(total) * 100).rounded())
    }

    private func tintedIconChip(
        _ systemImage: String,
        tint: Color
    ) -> some View {
        ZenIconChip(systemImage: systemImage, size: 30, tint: tint)
    }

    private var recoveryNote: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.warn)
            Text(
                "\(historyViewModel.recoveryCount) item"
                    + (historyViewModel.recoveryCount == 1 ? "" : "s")
                    + " waiting in Recovery"
            )
            .font(ZenDesign.Typography.captionStrong)
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .lineLimit(1)
            Spacer(minLength: ZenDesign.Spacing.xs)
            Button("Review") {
                navigate(.history)
            }
            .buttonStyle(ZenPressButtonStyle())
            .font(ZenDesign.Typography.captionStrong)
            .foregroundStyle(ZenDesign.Semantic.warn)
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .frame(height: 46)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .fill(ZenDesign.Semantic.warnMuted)
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .strokeBorder(ZenDesign.Semantic.warn.opacity(0.3))
            }
        }
    }

    private var microphoneDisplayName: String {
        viewModel.selectedMicrophoneName
    }

    private var modelDisplayName: String {
        modelManagerViewModel.activeEngineDisplayName
    }
}
