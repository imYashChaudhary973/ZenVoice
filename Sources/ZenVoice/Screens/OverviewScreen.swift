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
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            todayUsageCard
            statusOverview
            HStack(alignment: .top, spacing: ZenDesign.Spacing.lg) {
                quickActionsPanel
                    .frame(minWidth: 260, maxWidth: .infinity)
                homeSideColumn
                    .frame(width: 300)
            }
        }
    }

    // MARK: - Today's usage

    private var todayUsageCard: some View {
        let today = insightsViewModel.snapshot.today
        return ZenPanel {
            HStack(spacing: 0) {
                todayStat(
                    "Words",
                    value: formattedCount(today.wordCount),
                    caption: today.wordCount == 1 ? "today" : "today"
                )
                Divider().overlay(ZenDesign.Semantic.border)
                todayStat(
                    "Dictations",
                    value: formattedCount(today.dictationCount),
                    caption: today.dictationCount == 1 ? "session" : "sessions"
                )
                Divider().overlay(ZenDesign.Semantic.border)
                todayStat(
                    "Time",
                    value: formattedDuration(today.durationSeconds),
                    caption: "spoken"
                )
                Divider().overlay(ZenDesign.Semantic.border)
                todayStat(
                    "Top app",
                    value: today.topApplicationName ?? "—",
                    caption: today.hasActivity ? "most words" : "no activity"
                )
            }
            .padding(.vertical, ZenDesign.Spacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Today's usage. \(today.pillSummary)."))
    }

    private func todayStat(
        _ label: String,
        value: String,
        caption: String
    ) -> some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
            Text(label.uppercased())
                .font(ZenDesign.Typography.metricCaption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            Text(value)
                .font(ZenDesign.Typography.metric)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(caption)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ZenDesign.Spacing.md)
    }

    private func formattedCount(_ count: Int) -> String {
        String(count)
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
        ZenPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: ZenDesign.Spacing.sm) {
                    statusDot
                    Text(statusTitle)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Spacer()
                    Text("Local · encrypted · on-device")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                .padding(.bottom, ZenDesign.Spacing.sm)

                HStack(spacing: 0) {
                    statusItem("Shortcut", value: viewModel.currentShortcut.displayName, isKeycap: true)
                    Divider().overlay(ZenDesign.Semantic.border)
                    statusItem("Microphone", value: microphoneDisplayName)
                    Divider().overlay(ZenDesign.Semantic.border)
                    statusItem("Language", value: appState.languageProfile.displayName)
                    Divider().overlay(ZenDesign.Semantic.border)
                    statusItem("Model", value: modelDisplayName)
                }
                .frame(height: 54)
                .background(ZenDesign.Semantic.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: ZenDesign.Radius.small, style: .continuous))
            }
            .padding(ZenDesign.Spacing.md)
        }
    }

    private var statusTitle: String {
        switch appState.phase {
        case .idle:
            return "Ready to dictate"
        case .listening:
            return "Listening"
        case .transcribing:
            return "Transcribing"
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
            .frame(width: 8, height: 8)
    }

    private var statusTint: Color {
        switch appState.phase {
        case .idle, .success:
            return ZenDesign.Semantic.success
        case .listening:
            return ZenDesign.Semantic.accent
        case .transcribing, .inserting:
            return ZenDesign.Semantic.warn
        case .error:
            return ZenDesign.Semantic.danger
        }
    }

    private func statusItem(_ label: String, value: String, isKeycap: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            if isKeycap {
                ZenKbdGroup(combo: value)
            } else {
                Text(value)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ZenDesign.Spacing.md)
    }

    // MARK: - Side column

    private var homeSideColumn: some View {
        VStack(spacing: ZenDesign.Spacing.md) {
            permissionsPanel
            recentActivityPanel
            if historyViewModel.recoveryCount > 0 {
                recoveryNote
            }
        }
    }

    private var quickActionsPanel: some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                miniTitle("Actions")
                HStack(spacing: ZenDesign.Spacing.sm) {
                    Button(action: startDictation) {
                        Label("Start dictating", systemImage: "mic")
                            .fixedSize()
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())

                    Button("Replay setup guide", action: replaySetup)
                        .buttonStyle(ZenSecondaryButtonStyle())
                }
            }
            .padding(ZenDesign.Spacing.md)
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
            .padding(.bottom, ZenDesign.Spacing.sm)
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        granted: Bool
    ) -> some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            tintedIconChip(icon, tint: granted ? ZenDesign.Semantic.success : ZenDesign.Semantic.warn)
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
        .padding(.horizontal, ZenDesign.Spacing.md)
        .frame(height: 40)
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
                        .padding(.horizontal, ZenDesign.Spacing.md)
                        .padding(.bottom, ZenDesign.Spacing.sm)
                } else {
                    ForEach(recent) { record in
                        Button {
                            navigate(.history)
                        } label: {
                            HStack(spacing: ZenDesign.Spacing.sm) {
                                tintedIconChip("text.bubble", tint: ZenDesign.Semantic.accent)
                                Text(record.targetAppName ?? "Unknown app")
                                    .font(ZenDesign.Typography.body)
                                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(
                                    record.startedAt.formatted(
                                        .relative(presentation: .named)
                                    )
                                )
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                                .lineLimit(1)
                            }
                            .padding(.horizontal, ZenDesign.Spacing.md)
                            .frame(height: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, ZenDesign.Spacing.sm)
        }
    }

    private func tintedIconChip(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.12))
            }
    }

    private func miniTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(ZenDesign.Typography.sectionTitle)
            .tracking(1.5)
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
            .padding(.horizontal, ZenDesign.Spacing.md)
            .padding(.top, ZenDesign.Spacing.sm)
            .padding(.bottom, ZenDesign.Spacing.xs)
    }

    private var recoveryNote: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            tintedIconChip("exclamationmark.triangle", tint: ZenDesign.Semantic.warn)
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
        .foregroundStyle(ZenDesign.Semantic.warn)
        .padding(.horizontal, ZenDesign.Spacing.md)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: ZenDesign.Radius.medium)
                .fill(ZenDesign.Semantic.warnMuted)
                .overlay {
                    RoundedRectangle(cornerRadius: ZenDesign.Radius.medium)
                        .strokeBorder(
                            ZenDesign.Semantic.warn.opacity(0.18)
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
}
