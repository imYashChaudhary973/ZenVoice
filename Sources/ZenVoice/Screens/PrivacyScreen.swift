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

struct PrivacyScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var voiceProfileViewModel:
        VoiceProfileViewModel
    @ObservedObject var modelManagerViewModel:
        ModelManagerViewModel
    let openModels: () -> Void
    var embedded = false


    var body: some View {
        Group {
            if embedded {
                privacyContent
            } else {
                ZenScreen(
                    icon: "lock.shield.fill",
                    title: "Privacy & Data",
                    subtitle: "What ZenVoice keeps, and where."
                ) {
                    privacyContent
                }
            }
        }
        .onAppear {
            historyViewModel.refresh()
            voiceProfileViewModel.refresh()
        }

    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xxl) {
            dictationPrivacy
            inventory
            permissions
            ZenBanner(
                kind: .success,
                icon: "network.slash",
                text:
                    "Model downloads use pinned revisions and SHA-256 verification. "
                    + "Audio, text, rules, and insights stay on this Mac."
            )
        }
    }

    // MARK: dictation privacy

    private var dictationPrivacy: some View {
        ZenSection(title: "Dictation privacy") {
            ZenPanel {
                ZenRow(
                    icon: "clock.arrow.circlepath",
                    title: "Save history",
                    subtitle:
                        "Encrypted locally. Pausing keeps existing records but stops new ones."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { historyViewModel.historyEnabled },
                            set: historyViewModel.setHistoryEnabled
                        ),
                        label: "Save history"
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "waveform",
                    title: "Keep failed audio for 24 hours",
                    subtitle:
                        "Only when no usable transcript was produced, so you can retry."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: {
                                historyViewModel.retainsFailedAudio
                            },
                            set:
                                historyViewModel.setRetainsFailedAudio
                        ),
                        label: "Keep failed audio"
                    )
                    .disabled(!historyViewModel.historyEnabled)
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "eye.slash",
                    title: "Private Dictation mode",
                    subtitle:
                        "While enabled, nothing is saved — no history, no insights, no recovery. Toggle anytime with \(viewModel.privateModeShortcut.displayName)."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: {
                                historyViewModel.privateModeEnabled
                            },
                            set:
                                historyViewModel.setPrivateModeEnabled
                        ),
                        label: "Private Dictation"
                    )
                }
            }
        }
    }

    // MARK: live inventory

    private var inventory: some View {
        ZenSection(
            title: "What's on this Mac right now",
            caption: "Live inventory · ZenVoice \(appVersion)"
        ) {
            ZenPanel {
                ZenRow(
                    icon: "lock",
                    title: "Encrypted transcripts",
                    subtitle:
                        "\(historyViewModel.savedTranscriptCount) records · AES-GCM, key in the macOS Keychain"
                ) {
                    ZenHoldToDeleteButton(
                        label: "Delete",
                        minWidth: 108
                    ) {
                        historyViewModel.deleteAll()
                    }
                    .disabled(historyViewModel.savedTranscriptCount == 0)
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "tray",
                    title: "Recovery audio",
                    subtitle:
                        "\(historyViewModel.recoveryAudioCount) clips · kept at most 24 hours, only if you allowed it"
                ) {
                    ZenHoldToDeleteButton(
                        label: "Delete",
                        minWidth: 108
                    ) {
                        historyViewModel.deleteAllRecoveryAudio()
                    }
                    .disabled(historyViewModel.recoveryAudioCount == 0)
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "pencil",
                    title: "Correction rules",
                    subtitle:
                        "\(voiceProfileViewModel.snapshot.correctionRules.count) rules · encrypted with the same key"
                ) {
                    ZenHoldToDeleteButton(
                        label: "Delete",
                        minWidth: 108
                    ) {
                        voiceProfileViewModel.deleteAllRules()
                    }
                    .disabled(
                        voiceProfileViewModel.snapshot
                            .correctionRules.isEmpty
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "cpu",
                    title: "Local models",
                    subtitle:
                        "\(modelManagerViewModel.installedModelIDs.count) speech — verified weights"
                ) {
                    Button("Manage", action: openModels)
                        .buttonStyle(
                            ZenPrimaryButtonStyle(minWidth: 108)
                        )
                }
            }
        }
    }

    // MARK: permissions

    private var permissions: some View {
        ZenSection(title: "macOS permissions") {
            ZenPanel {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "Used only while a dictation is active.",
                    status: viewModel.microphoneStatus,
                    action: viewModel.requestMicrophoneAccess
                )
                ZenPanelDivider()
                PermissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    detail:
                        "Types the finished text into the active app. Without it, transcripts are copied to the clipboard instead.",
                    status: viewModel.accessibilityStatus,
                    action: viewModel.requestAccessibilityAccess
                )
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: SettingsViewModel.PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: ZenDesign.Spacing.md) {
            ZenIconChip(
                systemImage: icon,
                size: ZenDesign.Layout.hitTarget,
                tint: ZenDesign.Semantic.textSecondary
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let remedy = status.remedy {
                    Text(remedy)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: ZenDesign.Spacing.sm)

            ZenBadge(
                text: status.title,
                kind: badgeKind,
                showsDot: true
            )

            if let actionTitle = status.actionTitle {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }
        }
        .padding(.vertical, ZenDesign.Spacing.sm)
        .padding(.horizontal, ZenDesign.Spacing.md)
        .frame(minHeight: 64)
    }

    /// "Not asked yet" is a neutral starting state, not a failure — only an
    /// actual denial or a policy restriction is worth colouring red.
    private var badgeKind: ZenBadge.Kind {
        switch status {
        case .allowed:
            return .success
        case .notRequested:
            return .neutral
        case .denied, .restricted:
            return .danger
        }
    }
}
