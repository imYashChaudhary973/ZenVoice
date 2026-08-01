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
