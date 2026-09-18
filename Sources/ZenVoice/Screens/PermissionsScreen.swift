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

/// macOS permissions in the reference card style: two large preview cards —
/// HUD gradient thumbnail, glyph art, status badge, description, and the
/// action that resolves the state — plus a Refresh Status pill.
struct PermissionsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZenScreen(
            icon: "lock.shield",
            title: "Permissions",
            subtitle: "The macOS permissions dictation depends on."
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Layout.contentGap) {
                ZenSection(title: "Required access") {
                    ZenPanel(padding: ZenDesign.Spacing.md) {
                        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                            Text(
                                "Two macOS permissions power dictation. "
                                    + "Everything they enable runs on this Mac."
                            )
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: ZenDesign.Layout.contentGap) {
                                PermissionCard(
                                    kind: .microphone,
                                    status: viewModel.microphoneStatus,
                                    action: viewModel.requestMicrophoneAccess
                                )
                                PermissionCard(
                                    kind: .accessibility,
                                    status: viewModel.accessibilityStatus,
                                    action: viewModel.requestAccessibilityAccess
                                )
                            }
                            .padding(.top, ZenDesign.Spacing.xs)
                        }
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    Button {
                        viewModel.refreshSystemStatus()
                    } label: {
                        Text("Refresh Status")
                            .font(ZenDesign.Typography.captionStrong)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .padding(.horizontal, ZenDesign.Spacing.md)
                            .frame(minHeight: 32)
                            .background {
                                Capsule()
                                    .fill(ZenDesign.Component.shortcutBackground)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh Status")
                }
            }
        }
    }
}

/// The two permission cards' flavor: which glyph art the thumbnail draws and
/// which copy the caption carries.
enum PermissionKind {
    case microphone
    case accessibility

    var name: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        }
    }

    var detail: String {
        switch self {
        case .microphone:
            return "Hears your voice while you dictate. Audio never leaves this Mac."
        case .accessibility:
            return "Powers the activation key and lands text at your cursor."
        }
    }
}

/// One permission card: HUD-gradient thumbnail with pink glyph art, caption
/// with name + Granted badge, description, and an Open Settings chip.
private struct PermissionCard: View {
    let kind: PermissionKind
    let status: SettingsViewModel.PermissionStatus
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kind.detail.isEmpty ? kind.name : kind.name)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Spacer(minLength: ZenDesign.Spacing.xs)
                    statusBadge
                }
                Text(kind.detail)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Settings") {
                    action()
                }
                .buttonStyle(ZenSecondaryButtonStyle(minWidth: 110))
                .padding(.top, ZenDesign.Spacing.sm)
            }
            .padding(ZenDesign.Spacing.md)
        }
        .background(ZenDesign.Semantic.surface)
        .clipShape(
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.large,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.large,
                style: .continuous
            )
            .strokeBorder(ZenDesign.Semantic.border.opacity(0.72), lineWidth: 1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The HUD-style art: gradient backdrop, pink glyph art centered.
    private var thumbnail: some View {
        ZStack {
            ZenDesign.Gradient.hudPreview
            switch kind {
            case .microphone:
                VStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ZenDesign.Semantic.accent)
                        .padding(10)
                        .background {
                            Circle()
                                .fill(ZenDesign.Glass.hudTint)
                        }
                        .overlay {
                            Circle().strokeBorder(
                                ZenDesign.Semantic.accent.opacity(0.4),
                                lineWidth: 1
                            )
                        }
                    waveformBars
                }
            case .accessibility:
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ZenDesign.Glass.hudTint)
                    .frame(width: 132, height: 62)
                    .overlay {
                        VStack(alignment: .leading, spacing: 8) {
                            PlaceholderLine(width: 96)
                            HStack(spacing: 6) {
                                Rectangle()
                                    .fill(ZenDesign.Semantic.accent)
                                    .frame(width: 2, height: 14)
                                PlaceholderLine(width: 64)
                            }
                        }
                    }
            }
        }
    }

    /// Five pink bars, the waveform the bar already speaks.
    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach([10, 16, 7, 14, 9], id: \.self) { height in
                Capsule()
                    .fill(ZenDesign.Semantic.accent)
                    .frame(width: 2.5, height: CGFloat(height))
            }
        }
    }

    private var statusBadge: some View {
        let text: String
        let kind: ZenBadge.Kind
        let icon: String?
        switch status {
        case .allowed:
            text = "Granted"
            kind = .success
            icon = "checkmark.circle"
        case .notRequested:
            text = "Not asked yet"
            kind = .neutral
            icon = nil
        case .denied, .restricted:
            text = "Denied"
            kind = .danger
            icon = "xmark.circle"
        }
        return ZenBadge(
            text: text,
            kind: kind,
            systemImage: icon,
            showsDot: icon == nil
        )
    }
}

/// A gray placeholder line for the accessibility thumbnail's text field.
private struct PlaceholderLine: View {
    let width: CGFloat

    var body: some View {
        Capsule()
            .fill(ZenDesign.Semantic.textTertiary.opacity(0.6))
            .frame(width: width, height: 5)
    }
}
