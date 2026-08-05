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
        ZenScreen(
            title: "Audio",
            subtitle: "Pick the microphone ZenVoice listens to."
        ) {
            inputSection
            doctorSection

            ZenBanner(
                kind: .info,
                icon: "bolt.horizontal",
                text:
                    "If a pinned microphone disconnects during dictation, ZenVoice stops safely — anything captured follows your recovery-audio privacy setting."
            )
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
            ZenPanel {
                deviceButton(
                    id: nil,
                    icon: "macbook",
                    name: "System default",
                    detail:
                        "Follow the current macOS input automatically — switches when macOS does.",
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
        .buttonStyle(.plain)
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
            caption: "3-second on-device check"
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: ZenDesign.Spacing.sm) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                            .frame(width: 28, height: 28)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: 8, style: .continuous
                                )
                                .fill(ZenDesign.Semantic.surfaceRaised)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check signal and format")
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text(viewModel.audioDoctorState.title)
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(audioDoctorTint)
                        }
                        Spacer()
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

                    VStack(alignment: .leading, spacing: 8) {
                        AudioDoctorWaveform(
                            samples: viewModel.audioDoctorSamples,
                            tint: audioDoctorTint
                        )
                        .frame(height: 44)

                        HStack {
                            Text(audioDoctorTimingLabel)
                            Spacer()
                            Text("16 kHz · mono · local")
                        }
                        .font(ZenDesign.Typography.monoSmall)
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.surfaceSunken)
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: ZenDesign.Radius.small,
                                style: .continuous
                            )
                            .strokeBorder(ZenDesign.Semantic.border)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Microphone waveform")
                    .accessibilityValue(
                        "\(Int((viewModel.audioDoctorLevel * 100).rounded())) percent"
                    )

                    Text(
                        "Records three seconds locally, measures loudness, confirms the sample format, then deletes the clip. No test audio leaves this Mac."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
            return "Run check"
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
            return "Ready · 3.0 s check"
        case .passed:
            return "Signal and format passed"
        case .quiet:
            return "Format passed · signal is quiet"
        case .failed:
            return "Check could not complete"
        }
    }
}

private struct AudioDoctorWaveform: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    let samples: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let count = max(1, samples.count)
            let barWidth = max(
                2,
                (proxy.size.width - spacing * CGFloat(count - 1))
                    / CGFloat(count)
            )
            HStack(alignment: .center, spacing: spacing) {
                ForEach(
                    Array(samples.enumerated()),
                    id: \.offset
                ) { _, sample in
                    Capsule()
                        .fill(
                            tint.opacity(sample > 0.03 ? 0.95 : 0.24)
                        )
                        .frame(
                            width: barWidth,
                            height: max(
                                3,
                                proxy.size.height
                                    * max(0.06, min(1, sample))
                            )
                        )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
        }
        .animation(
            ZenDesign.Motion.waveform(reduceMotion),
            value: samples
        )
    }
}
