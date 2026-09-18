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

struct AudioScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Layout.contentGap) {
            if let device = viewModel.lastQuietDevice {
                ZenBanner(
                    kind: .warn,
                    icon: "waveform.slash",
                    text: "No audible speech from \(device). Check that "
                        + "the mic is not muted, or pick another input "
                        + "device below."
                )
            }
            inputSection
            doctorSection
        }
        .onAppear {
            viewModel.refreshMicrophones()
        }
    }

    // MARK: input devices

    private var inputSection: some View {
        ZenSection(
            title: "Input device",
            caption: viewModel.selectedMicrophoneUID == nil
                ? "Following the macOS default"
                : "Pinned to \(viewModel.selectedMicrophoneName)"
        ) {
            ZenPanel(padding: 4) {
                deviceButton(
                    id: nil,
                    icon: "macbook",
                    name: "System default",
                    detail:
                        "Follows the current macOS input.\nSwitches when macOS does.",
                    selected: viewModel.selectedMicrophoneUID == nil,
                    isDefault: false,
                    enabled: !viewModel.isAudioDoctorActive
                )

                if viewModel.microphones.isEmpty {
                    ZenPanelDivider()
                    ZenRow(
                        icon: "mic.slash",
                        iconTint: ZenDesign.Semantic.danger,
                        iconBackground: ZenDesign.Semantic.dangerMuted,
                        title: "No connected microphones found",
                        subtitle: "Connect a microphone, then reopen this screen."
                    )
                } else {
                    ForEach(viewModel.microphones) { microphone in
                        ZenPanelDivider()
                        deviceButton(
                            id: microphone.id,
                            icon: deviceIcon(microphone),
                            name: microphone.name,
                            detail: microphoneDetail(microphone),
                            selected:
                                viewModel.selectedMicrophoneUID
                                    == microphone.id,
                            isDefault: microphone.isDefault,
                            enabled: microphone.isConnected
                                && !viewModel.isAudioDoctorActive
                        )
                    }
                }
            }
        }
    }

    private func deviceButton(
        id: String?,
        icon: String,
        name: String,
        detail: String,
        selected: Bool,
        isDefault: Bool,
        enabled: Bool
    ) -> some View {
        Button {
            viewModel.selectMicrophone(id)
        } label: {
            ZenRow(
                icon: icon,
                iconTint: selected ? ZenDesign.Semantic.accent : nil,
                iconBackground:
                    selected ? ZenDesign.Semantic.accentMuted : nil,
                title: name,
                subtitle: detail
            ) {
                if isDefault {
                    ZenBadge(text: "macOS default", kind: .neutral)
                }
                if selected {
                    ZenBadge(
                        text: "In use", kind: .accent,
                        systemImage: "checkmark"
                    )
                } else if enabled {
                    Text("Pin")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func deviceIcon(_ microphone: MicrophoneDevice) -> String {
        let name = microphone.name.lowercased()
        if name.contains("airpods") || name.contains("headphones") {
            return "headphones"
        }
        return "mic"
    }

    private func microphoneDetail(
        _ microphone: MicrophoneDevice
    ) -> String {
        if !microphone.isConnected {
            return "Disconnected"
        }
        if microphone.isInUseByAnotherApplication {
            return "Connected · also in use by another app"
        }
        return microphone.isDefault
            ? "Connected · current macOS default"
            : "Connected"
    }

    // MARK: audio doctor

    private var doctorSection: some View {
        ZenSection(
            title: "Audio Doctor",
            caption: "10-second on-device check"
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    HStack(spacing: ZenDesign.Spacing.sm) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .frame(width: 36, height: 36)
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 8,
                                    style: .continuous
                                )
                                .strokeBorder(
                                    ZenDesign.Semantic.textPrimary.opacity(0.55),
                                    lineWidth: 1.4
                                )
                            }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check signal and format")
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text(viewModel.audioDoctorState.title)
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(audioDoctorTint)
                            if case .quiet = viewModel.audioDoctorState {
                                Text(
                                    "The microphone picked up almost "
                                        + "nothing. Check that it is not "
                                        + "muted, or pick another input "
                                        + "device above."
                                )
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            }
                        }
                        Spacer(minLength: ZenDesign.Spacing.sm)
                        Button(audioDoctorButtonTitle) {
                            switch viewModel.audioDoctorState {
                            case .running, .paused:
                                viewModel.toggleAudioDoctorPause()
                            case .idle, .passed, .quiet, .failed:
                                viewModel.runAudioDoctor()
                            case .analyzing:
                                break
                            }
                        }
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .disabled(
                            viewModel.audioDoctorState == .analyzing
                        )
                    }

                    GeometryReader { proxy in
                        let barWidth: CGFloat = 2.5
                        let spacing: CGFloat = 2
                        let count = max(
                            AudioSpectrumMeter.barCount,
                            Int(
                                (proxy.size.width + spacing)
                                    / (barWidth + spacing)
                            )
                        )
                        WaveformView(
                            model: viewModel.audioDoctorMeter,
                            style: .voiceprint,
                            voiceprintBarCount: count
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .center
                        )
                    }
                    .frame(height: 36)
                    .padding(.horizontal, ZenDesign.Spacing.sm)
                    .padding(.vertical, ZenDesign.Spacing.xs)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.large,
                            style: .continuous
                        )
                        .strokeBorder(
                            ZenDesign.Semantic.textPrimary.opacity(0.45),
                            lineWidth: 1.4
                        )
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Microphone waveform")
                    .accessibilityValue(audioDoctorTimingLabel)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var audioDoctorTint: Color {
        switch viewModel.audioDoctorState {
        case .passed:
            return ZenDesign.Semantic.success
        case .quiet, .failed:
            return ZenDesign.Semantic.danger
        case .idle, .running, .paused, .analyzing:
            return ZenDesign.Semantic.accent
        }
    }

    private var audioDoctorButtonTitle: String {
        switch viewModel.audioDoctorState {
        case .running:
            return "Pause"
        case .paused:
            return "Resume"
        case .analyzing:
            return "Checking…"
        case .idle, .passed, .quiet, .failed:
            return "Run Check"
        }
    }

    private var audioDoctorTimingLabel: String {
        switch viewModel.audioDoctorState {
        case .running, .paused:
            return String(
                format: "%.1f s remaining",
                viewModel.audioDoctorRemainingSeconds
            )
        case .analyzing:
            return "Capture complete · validating"
        case .idle:
            return "Ready · 10 s check"
        case .passed:
            return "Signal and format passed"
        case .quiet:
            return "Format passed · signal is quiet"
        case .failed:
            return "Check could not complete"
        }
    }
}


