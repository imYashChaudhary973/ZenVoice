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
            HStack(alignment: .top, spacing: 16) {
                quickActionsPanel
                    .frame(minWidth: 260, maxWidth: .infinity)
                homeSideColumn
                    .frame(width: 300)
            }
        }
    }

    /// Today's dictation totals. Private Dictation is excluded upstream —
    /// private recordings are never persisted, so they never reach insights.
    private var todayUsageCard: some View {
        let today = insightsViewModel.snapshot.today
        return ZenPanel {
            HStack(spacing: 0) {
                todayStat(
                    "Today",
                    value: "\(today.wordCount)",
                    caption: today.wordCount == 1 ? "word" : "words"
                )
                Divider().overlay(ZenDesign.Semantic.border)
                todayStat(
                    "Dictations",
                    value: "\(today.dictationCount)",
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
            .padding(.vertical, 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Today's usage. \(today.pillSummary)."))
    }

    private func todayStat(
        _ label: String,
        value: String,
        caption: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            Text(value)
                .font(ZenDesign.Typography.bodyStrong)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(caption)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
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

    private var statusOverview: some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(ZenDesign.Semantic.success)
                        .frame(width: 8, height: 8)
                    Text("Ready to dictate")
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Spacer()
                    Text("Local · encrypted · on-device")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                .padding(.bottom, 12)

                HStack(spacing: 0) {
                    statusItem("Shortcut", value: viewModel.currentShortcut.displayName, isKeycap: true)
                    Divider().overlay(ZenDesign.Semantic.border)
                    statusItem("Microphone", value: microphoneDisplayName)
                    Divider().overlay(ZenDesign.Semantic.border)
                    statusItem("Language", value: appState.languageProfile.displayName)
                    Divider().overlay(ZenDesign.Semantic.border)
                    statusItem("Model", value: modelDisplayName)
                }
                .frame(height: 52)
                .background(ZenDesign.Semantic.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: ZenDesign.Radius.small, style: .continuous))
            }
            .padding(ZenDesign.Spacing.md)
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

    private var homeSideColumn: some View {
        VStack(spacing: 12) {
            permissionsPanel
            recentActivityPanel
            if historyViewModel.recoveryCount > 0 {
                recoveryNote
            }
        }
    }

    private var quickActionsPanel: some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: 10) {
                miniTitle("Actions")
                HStack(spacing: 10) {
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
                                .font(ZenDesign.Typography.monoSmall)
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
        .foregroundStyle(ZenDesign.Semantic.warn)
        .padding(.horizontal, 14)
        .frame(height: 42)
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
