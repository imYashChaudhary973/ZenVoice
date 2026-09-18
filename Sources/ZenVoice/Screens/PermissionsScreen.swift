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

/// macOS permissions in their own section: what each one is for, the live
/// status, and the action that resolves it.
struct PermissionsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZenScreen(
            icon: "lock.shield",
            title: "Permissions",
            subtitle: "The macOS permissions dictation depends on."
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Layout.contentGap) {
                microphoneSection
                accessibilitySection
                explainer
            }
        }
    }

    private var microphoneSection: some View {
        ZenSection(title: "MICROPHONE") {
            ZenPanel {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone access",
                    detail: "Used while dictating. Audio is processed on this Mac.",
                    status: viewModel.microphoneStatus,
                    action: viewModel.requestMicrophoneAccess
                )
            }
        }
    }

    private var accessibilitySection: some View {
        ZenSection(title: "ACCESSIBILITY") {
            ZenPanel {
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

    private var explainer: some View {
        ZenSection(title: "Why these two") {
            ZenPanel(padding: ZenDesign.Spacing.md) {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                    Text("Microphone")
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        "Dictation records your voice and transcribes it on "
                            + "this Mac. No audio leaves the device."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Accessibility")
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .padding(.top, ZenDesign.Spacing.xxs)
                    Text(
                        "ZenVoice types the finished text straight into "
                            + "whatever field you dictate into. Without the "
                            + "permission, transcripts land on the clipboard "
                            + "instead."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One permission in the reference row style: icon chip, name, detail, the
/// remedy hint, a status badge, and the action that resolves the state.
struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: SettingsViewModel.PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: ZenDesign.Spacing.md) {
            ZenIconChip(
                systemImage: icon,
                size: ZenDesign.Layout.rowIcon,
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
    }

    private var badgeKind: ZenBadge.Kind {
        switch status {
        case .allowed: return .success
        case .denied, .restricted: return .danger
        case .notRequested: return .neutral
        }
    }
}
