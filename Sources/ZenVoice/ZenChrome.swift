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

import AppKit
import SwiftUI

// MARK: - Window chrome
// The shell around every screen: the translucent sidebar material, the top
// bar's action cluster, and the icon chip that heads each card.

/// Vibrancy material, for the sidebar.
///
/// `behindWindow` blending samples the desktop, which is what gives the
/// sidebar its depth. It only works while nothing opaque is painted behind it,
/// so the root view paints its canvas on the *content column* rather than on
/// the whole window — a full-window background silently flattens this back to
/// a plain grey panel.
struct ZenVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        // `.active` rather than `.followsWindowActiveState`: the sidebar keeps
        // its material when the window loses key, which it does constantly —
        // dictation is aimed at whatever app is in front.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Rounded-square tinted icon container that heads a card or a page.
struct ZenIconChip: View {
    let systemImage: String
    var size: CGFloat = 36
    var tint: Color = ZenDesign.Semantic.accent
    var background: Color?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(
                    cornerRadius: size * 0.28,
                    style: .continuous
                )
                .fill(background ?? tint.opacity(0.14))
            }
            .accessibilityHidden(true)
    }
}

/// The capsule cluster in the top-right of the window.
///
/// Segments are separated by hairlines rather than gaps, so the group reads as
/// one control instead of three floating buttons.
struct ZenToolbarCluster<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        // The capsule is pinned to `control` height rather than left to size
        // itself to the stack. Each segment carries a 44pt hit frame, so the
        // stack is 44pt tall — and an unpinned background inherited that,
        // painting a capsule 12pt taller than the Dictate button beside it.
        // The hit targets are unaffected; only the paint is constrained.
        .background(alignment: .center) {
            Capsule(style: .continuous)
                .fill(ZenDesign.Semantic.surfaceRaised)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(ZenDesign.Semantic.border, lineWidth: 1)
                }
                .frame(height: ZenDesign.Layout.control)
        }
    }
}

/// One segment of a `ZenToolbarCluster`.
struct ZenToolbarButton: View {
    let systemImage: String
    var title: String?
    let label: String
    var tint: Color?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                if let title {
                    Text(title)
                        .font(ZenDesign.Typography.captionStrong)
                }
            }
            .foregroundStyle(
                tint
                    ?? (hovering
                        ? ZenDesign.Semantic.textPrimary
                        : ZenDesign.Semantic.textSecondary)
            )
            .padding(.horizontal, title == nil ? 10 : 13)
            .frame(height: ZenDesign.Layout.control)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        hovering
                            ? ZenDesign.Semantic.surfaceSunken.opacity(0.6)
                            : Color.clear
                    )
                    .padding(2)
            }
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Hairline between two `ZenToolbarCluster` segments.
struct ZenToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(ZenDesign.Semantic.border)
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }
}

/// Card or page heading: tinted icon chip, title, one line of subtitle.
struct ZenCardHeader<Trailing: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var titleFont: Font = ZenDesign.Typography.pageTitle
    var iconSize: CGFloat = 36
    var iconTint: Color = ZenDesign.Semantic.accent
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // The chip aligns to the *title row*, not to the title-plus-subtitle
        // block. Centring it against the whole block dropped it below the
        // title whenever a subtitle wrapped, and left two cards side by side
        // with their titles on different lines — the taller header pushed its
        // own title up while the shorter one stayed centred.
        HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
            ZenIconChip(
                systemImage: systemImage,
                size: iconSize,
                tint: iconTint
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: ZenDesign.Spacing.sm) {
                    Text(title)
                        .font(titleFont)
                        .tracking(-0.2)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ZenDesign.Spacing.md)
                    trailing
                }
                // Pinned to the chip's height so every card's title sits on
                // the same line regardless of what is below it.
                .frame(minHeight: iconSize)

                if let subtitle {
                    Text(subtitle)
                        .font(ZenDesign.Typography.body)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension ZenCardHeader where Trailing == EmptyView {
    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        titleFont: Font = ZenDesign.Typography.pageTitle,
        iconSize: CGFloat = 36,
        iconTint: Color = ZenDesign.Semantic.accent
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            titleFont: titleFont,
            iconSize: iconSize,
            iconTint: iconTint,
            trailing: { EmptyView() }
        )
    }
}
