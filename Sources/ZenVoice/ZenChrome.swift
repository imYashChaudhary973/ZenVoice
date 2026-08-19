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
// The shell around every screen: the vibrancy materials, the surface treatment
// that gives a card its depth, the top bar's action cluster, and the heading
// block that fronts each page and card.

/// Vibrancy material.
///
/// `behindWindow` blending samples the desktop, which is what gives the sidebar
/// and the window its depth. It only works while nothing opaque is painted
/// behind it, so both columns paint *translucent* tints over this rather than
/// solid fills — a single opaque background anywhere in the stack silently
/// flattens the whole window back to a plain grey panel.
struct ZenVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        // `.active` rather than `.followsWindowActiveState`: the window keeps
        // its material when it loses key, which it does constantly — dictation
        // is aimed at whatever app is in front. A sidebar that goes flat grey
        // every time you click away is the app announcing it has been
        // abandoned.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

// MARK: - Surface

/// The surface treatment every card, panel and floating object shares.
///
/// Three layers, and the order matters:
///
/// 1. a shadow, sized to the surface — bigger objects read as thicker;
/// 2. the fill;
/// 3. a **top-edge highlight**, one hairline along the upper lip only.
///
/// That third layer is the whole trick. Real surfaces catch light on the edge
/// that faces it, so a bright line on top and nothing on the bottom reads as a
/// raised object, while the same hairline drawn on all four sides reads as a
/// border — which is what the previous revision drew, on every card, inside
/// every other card. A stack of bordered rectangles has no depth at any nesting
/// level; a stack of lit surfaces has depth at all of them.
struct ZenSurface: ViewModifier {
    var cornerRadius: CGFloat = ZenDesign.Radius.large
    var fill: Color = ZenDesign.Semantic.surface
    var shadow: Color = ZenDesign.Component.cardShadow
    var shadowRadius: CGFloat = 14
    var shadowOffset: CGFloat = 4
    var showsBorder = true

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(fill)
                    .shadow(
                        color: shadow,
                        radius: shadowRadius,
                        y: shadowOffset
                    )
            }
            .clipShape(shape)
            .overlay {
                shape
                    .strokeBorder(
                        showsBorder
                            ? ZenDesign.Semantic.border
                            : Color.clear,
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .top) {
                // The lit lip. Masked to a gradient that fades out toward the
                // shoulders of the corner radius, because a highlight that runs
                // hard into a rounded corner terminates in a visible nub.
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                ZenDesign.Semantic.edgeHighlight,
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// A card-weight surface: the default for panels in the content column.
    func zenSurface(
        cornerRadius: CGFloat = ZenDesign.Radius.large,
        fill: Color = ZenDesign.Semantic.surface
    ) -> some View {
        modifier(ZenSurface(cornerRadius: cornerRadius, fill: fill))
    }

    /// A floating-weight surface: the ZenBar, the command palette, a popover.
    /// Deeper shadow and a wider spread, because it is further off the page.
    func zenFloatingSurface(
        cornerRadius: CGFloat = ZenDesign.Radius.large,
        fill: Color = ZenDesign.Semantic.surface
    ) -> some View {
        modifier(
            ZenSurface(
                cornerRadius: cornerRadius,
                fill: fill,
                shadow: ZenDesign.Component.floatingShadow,
                shadowRadius: 28,
                shadowOffset: 12
            )
        )
    }

    /// A control-weight surface: a key cap, a segment, a small chip. Almost no
    /// shadow — an object this small sitting a visible distance off the page
    /// looks like a mistake.
    func zenControlSurface(
        cornerRadius: CGFloat = ZenDesign.Radius.small,
        fill: Color = ZenDesign.Semantic.surfaceRaised
    ) -> some View {
        modifier(
            ZenSurface(
                cornerRadius: cornerRadius,
                fill: fill,
                shadow: Color.black.opacity(0.10),
                shadowRadius: 3,
                shadowOffset: 1
            )
        )
    }
}

/// Fades content out where it slides under floating chrome.
///
/// Replaces the 1px rule that used to sit under the top bar. A hard divider
/// asserts a boundary that is not there — content is *continuous* under the
/// bar, it is simply obscured — and a scrolling list that terminates on a line
/// reads as clipped rather than as continuing. The gradient says the same thing
/// honestly, and only where the two actually overlap.
struct ZenScrollEdge: View {
    var height: CGFloat = 22
    var edge: UnitPoint = .top

    var body: some View {
        LinearGradient(
            colors: [
                ZenDesign.Semantic.canvas,
                ZenDesign.Semantic.canvas.opacity(0),
            ],
            startPoint: edge,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

// MARK: - Glyphs

/// A glyph that heads a card, a row, or a page.
///
/// This used to draw a filled, accent-tinted rounded square behind every
/// symbol. Fifteen of those on one screen is what made the old window look like
/// a link farm: the chips were the loudest marks on the page and every one of
/// them was decoration — the title beside each already said what the card was.
///
/// It is now the symbol alone, monochrome by default. A caller that genuinely
/// encodes state in colour (a permission that is denied, a model that failed)
/// passes a `tint`, and because nothing around it is coloured any more, that
/// one tinted glyph actually reads as a signal.
struct ZenIconChip: View {
    let systemImage: String
    var size: CGFloat = 36
    var tint: Color = ZenDesign.Semantic.textSecondary
    /// Opt back in to a filled container. Reserved for the few places a glyph
    /// has to survive on top of an image or a busy material.
    var background: Color?

    var body: some View {
        Image(systemName: systemImage)
            // Optical size, not the frame: the glyph is drawn at a size that
            // matches the text beside it, and the frame only reserves a
            // consistent column so labels stay on one baseline whatever symbol
            // sits in front of them.
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                if let background {
                    RoundedRectangle(
                        cornerRadius: size * 0.28,
                        style: .continuous
                    )
                    .fill(background)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Toolbar

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
        // painting a capsule 14pt taller than the Dictate button beside it.
        // The hit targets are unaffected; only the paint is constrained.
        .background(alignment: .center) {
            Capsule(style: .continuous)
                .fill(ZenDesign.Semantic.surfaceRaised.opacity(0.7))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            ZenDesign.Semantic.border,
                            lineWidth: 1
                        )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                if let title {
                    Text(title)
                        .zenType(
                            ZenDesign.Typography.captionStrong,
                            tracking: ZenDesign.Tracking.caption
                        )
                }
            }
            .foregroundStyle(
                tint
                    ?? (hovering
                        ? ZenDesign.Semantic.textPrimary
                        : ZenDesign.Semantic.textSecondary)
            )
            .padding(.horizontal, title == nil ? 10 : 12)
            .frame(height: ZenDesign.Layout.control)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        hovering
                            ? ZenDesign.Semantic.textPrimary.opacity(0.07)
                            : Color.clear
                    )
                    .padding(2)
            }
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressableStyle())
        .onHover { hovering = $0 }
        .animation(ZenDesign.Motion.fast(reduceMotion), value: hovering)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Hairline between two `ZenToolbarCluster` segments.
struct ZenToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(ZenDesign.Semantic.border)
            .frame(width: 1, height: 16)
            .accessibilityHidden(true)
    }
}

// MARK: - Press feedback

/// Scales a control down the instant it is pressed, and back on release.
///
/// Feedback belongs on pointer-*down*. A control that only reacts once the
/// click completes feels dead in the hand — the delay is short enough to be
/// invisible as a delay and long enough to read as unresponsiveness. Nothing in
/// the previous revision responded to being held at all.
///
/// The spring is what makes it survive a fast double-press: the scale animates
/// from wherever it currently is, so a second press part-way through the
/// release does not snap back to 1 first.
struct ZenPressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed && !reduceMotion
                    ? ZenDesign.Motion.pressScale
                    : 1
            )
            .animation(
                ZenDesign.Motion.fast(reduceMotion),
                value: configuration.isPressed
            )
    }
}

// MARK: - Headings

/// Card or page heading: title, one line of subtitle, optional trailing slot.
///
/// The tinted icon chip that used to lead this block is gone. On a page it was
/// pure redundancy — the sidebar row you clicked to get here already carries
/// that same symbol, in that same colour, six inches to the left. On a card it
/// competed with the card's own title for the entry point. What remains is a
/// title at a size that actually leads, and a subtitle that explains rather
/// than decorates.
struct ZenCardHeader<Trailing: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var titleFont: Font = ZenDesign.Typography.sectionTitle
    var titleTracking: CGFloat = ZenDesign.Tracking.sectionTitle
    /// Retained so existing call sites keep compiling; the glyph is no longer
    /// drawn at page scale, so this only affects the inline symbol.
    var iconSize: CGFloat = 36
    var iconTint: Color = ZenDesign.Semantic.textTertiary
    /// Whether to draw the small leading glyph at all. Off for page headings,
    /// where the sidebar already names the section.
    var showsIcon = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if showsIcon {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(iconTint)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .zenType(titleFont, tracking: titleTracking)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ZenDesign.Spacing.md)
                trailing
            }

            if let subtitle {
                Text(subtitle)
                    .zenType(
                        ZenDesign.Typography.body,
                        tracking: ZenDesign.Tracking.body
                    )
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        maxWidth: ZenDesign.Layout.proseColumn,
                        alignment: .leading
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

extension ZenCardHeader where Trailing == EmptyView {
    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        titleFont: Font = ZenDesign.Typography.sectionTitle,
        titleTracking: CGFloat = ZenDesign.Tracking.sectionTitle,
        iconSize: CGFloat = 36,
        iconTint: Color = ZenDesign.Semantic.textTertiary,
        showsIcon: Bool = true
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            titleFont: titleFont,
            titleTracking: titleTracking,
            iconSize: iconSize,
            iconTint: iconTint,
            showsIcon: showsIcon,
            trailing: { EmptyView() }
        )
    }
}
