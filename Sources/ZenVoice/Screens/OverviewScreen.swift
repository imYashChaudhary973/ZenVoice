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
    let navigate: (OverviewDestination) -> Void

    var body: some View {
        ZenScreen(
            icon: "slider.horizontal.3",
            title: "General",
            subtitle: "Launch, microphone, and the recording HUD."
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                launchAndInput
                recordingHUD
                appearance
            }
            .onAppear {
                viewModel.refreshMicrophones()
            }
        }
    }

    private var launchAndInput: some View {
        ZenPanel {
            ZenRow(
                icon: "power",
                title: "Launch at login",
                subtitle: "Start ZenVoice when you sign in."
            ) {
                ZenSwitch(
                    isOn: Binding(
                        get: { viewModel.launchAtLoginEnabled },
                        set: viewModel.setLaunchAtLogin
                    ),
                    label: "Launch at login"
                )
            }

            if let error = viewModel.launchAtLoginError {
                ZenBanner(
                    kind: .danger,
                    icon: "exclamationmark.triangle",
                    text: error
                )
                .padding(.horizontal, ZenDesign.Spacing.md)
            }

            ZenPanelDivider()

            ZenRow(
                icon: "mic",
                title: "Input device",
                subtitle: "The microphone ZenVoice records from."
            ) {
                ZenMenuPicker(
                    label: "Input device",
                    options: microphoneOptions,
                    selection: Binding(
                        get: { viewModel.selectedMicrophoneUID ?? "" },
                        set: { uid in
                            viewModel.selectMicrophone(
                                uid.isEmpty ? nil : uid
                            )
                        }
                    ),
                    minWidth: 180,
                    title: microphoneTitle
                )
            }
        }
    }

    private var recordingHUD: some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording HUD")
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text("Choose where the live transcript appears while you speak.")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                .padding(.horizontal, ZenDesign.Spacing.md)
                .padding(.top, ZenDesign.Spacing.md)

                HStack(spacing: ZenDesign.Spacing.sm) {
                    hudCard(style: .notch) {
                        notchPreview
                    }
                    hudCard(style: .floatingPanel) {
                        floatingPreview
                    }
                }
                .padding(.horizontal, ZenDesign.Spacing.md)

                if viewModel.recordingHUDStyle == .floatingPanel {
                    ZenPanelDivider()

                    ZenRow(
                        title: "Position",
                        subtitle: "Where the live transcript appears."
                    ) {
                        ZenMenuPicker(
                            label: "Position",
                            options: RecordingHUDPosition.allCases,
                            selection: Binding(
                                get: { viewModel.recordingHUDPosition },
                                set: viewModel.setRecordingHUDPosition
                            ),
                            minWidth: 140,
                            title: \.displayName
                        )
                    }
                }
            }
            .padding(.bottom, ZenDesign.Spacing.sm)
        }
    }

    private var appearance: some View {
        ZenPanel {
            ZenRow(
                title: "Appearance",
                subtitle: "Dark glass by default, or follow the system look."
            ) {
                ZenMenuPicker(
                    label: "Appearance",
                    options: RecordingHUDAppearance.allCases,
                    selection: Binding(
                        get: { viewModel.recordingHUDAppearance },
                        set: viewModel.setRecordingHUDAppearance
                    ),
                    minWidth: 120,
                    title: \.displayName
                )
            }
        }
    }

    private func hudCard<Preview: View>(
        style: RecordingHUDStyle,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        let selected = viewModel.recordingHUDStyle == style
        return Button {
            viewModel.setRecordingHUDStyle(style)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                preview()
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.displayName)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(style.detail)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(
                            selected
                                ? ZenDesign.Semantic.accent
                                : ZenDesign.Semantic.textSecondary
                        )
                }
                .padding(ZenDesign.Spacing.sm)
            }
            .background(ZenDesign.Semantic.surfaceRaised)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .strokeBorder(
                    selected
                        ? ZenDesign.Semantic.accentFill
                        : ZenDesign.Semantic.border,
                    lineWidth: selected ? 2 : 1
                )
            }
        }
        .buttonStyle(ZenPressButtonStyle())
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var notchPreview: some View {
        ZStack(alignment: .top) {
            hudGradient
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 12,
                topTrailingRadius: 0
            )
            .fill(Color.black)
            .frame(width: 88, height: 28)
            .overlay {
                waveformBars
            }
        }
    }

    private var floatingPreview: some View {
        ZStack {
            hudGradient
            Capsule()
                .fill(Color.black.opacity(0.72))
                .frame(width: 108, height: 32)
                .overlay {
                    waveformBars
                }
        }
    }

    private var hudGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.28, blue: 0.28),
                Color(red: 0.18, green: 0.10, blue: 0.32),
                Color(red: 0.42, green: 0.12, blue: 0.38)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(Array([7, 12, 18, 10, 16, 8, 14].enumerated()), id: \.offset) {
                _,
                height in
                Capsule()
                    .fill(ZenDesign.Semantic.accent)
                    .frame(width: 3, height: CGFloat(height))
            }
        }
    }

    private var microphoneOptions: [String] {
        [""] + viewModel.microphones.map(\.id)
    }

    private func microphoneTitle(_ uid: String) -> String {
        if uid.isEmpty { return "System default" }
        return viewModel.microphones.first { $0.id == uid }?.name
            ?? "Microphone"
    }
}
