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

// MARK: - ZenVoice component vocabulary
//
// Every screen is composed from these, so the rules live here once rather than
// in twenty-six places. Two of them account for most of the visual change from
// the previous revision:
//
//   * `ZenInsetRow` no longer draws a border. A bordered row inside a bordered
//     card inside a bordered panel is three rectangles deep and reads as none
//     of them; grouping is now carried by a soft fill and by proximity, which
//     is what actually communicates "these belong together".
//
//   * Nothing draws an accent-tinted glyph unless the colour means something.
//     The accent is spent on selection, the primary action, and live state.

struct ZenBrandMark: View {
    let size: CGFloat

    var body: some View {
        if let logo = BrandAssets.zenLogo {
            Image(nsImage: logo)
                .resizable()
                .scaledToFit()
                .padding(max(2, size * 0.08))
                .frame(width: size, height: size)
                .background(Color.black)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: min(6, size * 0.22),
                        style: .continuous
                    )
                )
        } else {
            Image(systemName: "waveform")
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(
                        cornerRadius: min(6, size * 0.22),
                        style: .continuous
                    )
                    .fill(ZenDesign.Semantic.accentMuted)
                }
        }
    }
}

/// The one page scaffold: title, subtitle, optional tab strip, content.
///
/// The heading is now the largest type in the window and carries no icon. It
/// used to be a `ZenCardHeader` with a 40pt tinted chip, drawn at the same
/// 21pt as a card title — so the page's own name had no more presence than the
/// third card down, and the chip duplicated the sidebar glyph that was already
/// on screen. A page should announce itself once, clearly, and then get out of
/// the way.
struct ZenScreen<Content: View, Tabs: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let tabs: Tabs
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .zenType(
                            ZenDesign.Typography.display,
                            tracking: ZenDesign.Tracking.display
                        )
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)

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
                .frame(maxWidth: .infinity, alignment: .leading)

                if Tabs.self != EmptyView.self {
                    // The tab strip sits *below* the page title: the title
                    // names the section, the tabs are views within it.
                    tabs
                        .padding(.top, ZenDesign.Spacing.lg)
                }

                VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                    content
                }
                .padding(.top, ZenDesign.Spacing.xl)
            }
            // Cards fill the window. Long *prose* still needs a measure, so the
            // heading caps its own subtitle rather than the page capping
            // everything — otherwise full screen leaves the content floating in
            // a centred column matching neither the sidebar nor the top bar.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ZenDesign.Spacing.xl)
            .padding(.top, ZenDesign.Spacing.sm)
            .padding(.bottom, ZenDesign.Spacing.xxl)
        }
        .scrollIndicators(.automatic)
        // Content is continuous under the top bar; it is obscured, not clipped.
        // A gradient says that, a 1px rule lies about it.
        .overlay(alignment: .top) { ZenScrollEdge() }
    }
}

extension ZenScreen where Tabs == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            icon: icon,
            title: title,
            subtitle: subtitle,
            tabs: { EmptyView() },
            content: content
        )
    }
}

/// Draws a visible ring while the control it wraps holds keyboard focus.
///
/// Custom `.buttonStyle(.plain)` controls and plain text fields lose the system
/// focus ring, which left keyboard navigation through this window with no
/// visible indication of where you were.
struct ZenFocusRing: ViewModifier {
    var cornerRadius: CGFloat = ZenDesign.Radius.small
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    isFocused
                        ? ZenDesign.Component.focusRing
                        : Color.clear,
                    lineWidth: 2.5
                )
                .padding(-2)
                .allowsHitTesting(false)
            }
            .animation(ZenDesign.Motion.fast(reduceMotion), value: isFocused)
    }
}

extension View {
    func zenFocusRing(
        cornerRadius: CGFloat = ZenDesign.Radius.small
    ) -> some View {
        modifier(ZenFocusRing(cornerRadius: cornerRadius))
    }
}

/// Section label above a group of cards.
struct ZenSection<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: ZenDesign.Spacing.sm) {
                Text(title)
                    .zenType(
                        ZenDesign.Typography.bodyStrong,
                        tracking: ZenDesign.Tracking.body
                    )
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Spacer(minLength: 0)
                if let caption {
                    Text(caption)
                        .zenType(
                            ZenDesign.Typography.caption,
                            tracking: ZenDesign.Tracking.caption
                        )
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The card. One lit surface — the single container every screen is built from.
struct ZenPanel<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zenSurface()
    }
}

/// A card that heads itself: title, optional subtitle, then content.
struct ZenCard<Content: View, Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        ZenPanel(padding: ZenDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                ZenCardHeader(
                    systemImage: icon,
                    title: title,
                    subtitle: subtitle,
                    titleFont: ZenDesign.Typography.sectionTitle,
                    titleTracking: ZenDesign.Tracking.sectionTitle,
                    trailing: { trailing }
                )
                content
            }
        }
    }
}

extension ZenCard where Trailing == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            icon: icon,
            title: title,
            subtitle: subtitle,
            trailing: { EmptyView() },
            content: content
        )
    }
}

/// A row nested inside a card.
///
/// **No border.** This is the change that unwinds the box-in-a-box-in-a-box
/// look: the row is grouped by a soft fill and by sitting next to its siblings,
/// not by being outlined. The previous version drew a 1px stroke around every
/// one of these, inside a card that also had a stroke, inside a panel that had
/// one too — three concentric rectangles competing to be the thing that
/// contains you.
struct ZenInsetRow<Content: View>: View {
    var tinted = false

    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, ZenDesign.Spacing.sm)
            .padding(.vertical, ZenDesign.Spacing.xs + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .fill(
                    tinted
                        ? ZenDesign.Semantic.accentMuted
                        : ZenDesign.Semantic.textPrimary.opacity(0.04)
                )
            }
    }
}

struct ZenPanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(ZenDesign.Semantic.border)
            .frame(height: 1)
    }
}

/// List row: glyph · title/sub · trailing control.
struct ZenRow<Trailing: View>: View {
    var icon: String?
    var iconTint: Color?
    /// Retained for source compatibility. A filled container behind a row glyph
    /// is the decoration this revision removed; passing one no longer draws it.
    var iconBackground: Color?
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: ZenDesign.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        iconTint ?? ZenDesign.Semantic.textTertiary
                    )
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .zenType(
                        ZenDesign.Typography.bodyStrong,
                        tracking: ZenDesign.Tracking.body
                    )
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .zenType(
                            ZenDesign.Typography.caption,
                            tracking: ZenDesign.Tracking.caption
                        )
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 0) {
                trailing
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .padding(.vertical, ZenDesign.Spacing.sm)
        .frame(minHeight: 48)
    }
}

extension ZenRow where Trailing == EmptyView {
    init(
        icon: String? = nil,
        iconTint: Color? = nil,
        iconBackground: Color? = nil,
        title: String,
        subtitle: String? = nil
    ) {
        self.init(
            icon: icon,
            iconTint: iconTint,
            iconBackground: iconBackground,
            title: title,
            subtitle: subtitle,
            trailing: { EmptyView() }
        )
    }
}

/// Keyboard-key chip.
///
/// Drawn as an actual key: a raised cap with a lit top edge and a hint of
/// shadow under it. A shortcut is the one thing in this window the user has to
/// reproduce on hardware, so it should look like the hardware.
struct ZenKbd: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(ZenDesign.Semantic.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 23, minHeight: 22)
            .zenControlSurface(cornerRadius: 6)
    }
}

/// Shortcut combo rendered as individual key chips.
struct ZenKbdGroup: View {
    let combo: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                ZenKbd(text: key)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo)
    }

    private var keys: [String] {
        // "⌃⌥Space" → ["⌃", "⌥", "Space"]; tolerate arbitrary display names.
        var result: [String] = []
        var current = ""
        for char in combo {
            if "⌃⌥⇧⌘".contains(char) {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(String(char))
            } else if char == " " || char == "+" {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.isEmpty ? [combo] : result
    }
}

/// Quiet capsule with optional dot/icon.
struct ZenBadge: View {
    enum Kind {
        case neutral, success, accent, danger, warn
    }

    let text: String
    var kind: Kind = .neutral
    var systemImage: String?
    var showsDot = false

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle().fill(foreground).frame(width: 5, height: 5)
            }
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            // Sentence case, not uppercase. These pills carry model names and
            // capability labels — "Apple Silicon", "AI enhanced" — and
            // uppercasing turned proper nouns into shouting.
            Text(text)
                .lineLimit(1)
        }
        .font(ZenDesign.Typography.badge)
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background {
            Capsule(style: .continuous).fill(background)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var foreground: Color {
        switch kind {
        case .neutral: return ZenDesign.Semantic.textTertiary
        case .success: return ZenDesign.Semantic.success
        case .accent: return ZenDesign.Semantic.accent
        case .danger: return ZenDesign.Semantic.danger
        case .warn: return ZenDesign.Semantic.warn
        }
    }

    private var background: Color {
        switch kind {
        case .neutral: return ZenDesign.Semantic.textPrimary.opacity(0.06)
        case .success: return ZenDesign.Semantic.successMuted
        case .accent: return ZenDesign.Semantic.accentMuted
        case .danger: return ZenDesign.Semantic.dangerMuted
        case .warn: return ZenDesign.Semantic.warnMuted
        }
    }
}

/// Inline banner.
struct ZenBanner: View {
    enum Kind {
        case info, warn, danger, success
    }

    let kind: Kind
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.top, 1)
            Text(text)
                .zenType(
                    ZenDesign.Typography.body,
                    tracking: ZenDesign.Tracking.body
                )
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenDesign.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .fill(background)
        }
        // A leading accent bar rather than a full outline. It marks the banner
        // as a distinct kind of object without drawing a fourth rectangle
        // around content that already sits in two.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(foreground)
                .frame(width: 3)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
        )
    }

    /// The icon carries the kind's colour; the text stays at reading contrast.
    /// A whole paragraph in amber or red is harder to read than the same
    /// paragraph in body text with a coloured glyph beside it.
    private var foreground: Color {
        switch kind {
        case .info: return ZenDesign.Semantic.accent
        case .warn: return ZenDesign.Semantic.warn
        case .danger: return ZenDesign.Semantic.danger
        case .success: return ZenDesign.Semantic.success
        }
    }

    private var background: Color {
        switch kind {
        case .info: return ZenDesign.Semantic.accentMuted
        case .warn: return ZenDesign.Semantic.warnMuted
        case .danger: return ZenDesign.Semantic.dangerMuted
        case .success: return ZenDesign.Semantic.successMuted
        }
    }
}

/// Stat tile: label, then the number at display size, then one line of context.
///
/// The label sits *above* the value, which is the order the eye wants — you
/// read what the number is before you read the number. The uppercase tracked
/// eyebrow and the accent glyph beside it are both gone: a number is already
/// the most salient thing you can put on a page, and dressing it up in a second
/// colour and a third type treatment made a page of four of them read as an
/// analytics dashboard rather than as a quiet fact about your day.
struct ZenStatTile: View {
    let value: String
    let label: String
    var detail: String?
    var icon: String?
    var valueTint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .zenType(
                    ZenDesign.Typography.caption,
                    tracking: ZenDesign.Tracking.caption
                )
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .lineLimit(1)

            Text(value)
                .zenType(
                    ZenDesign.Typography.metric,
                    tracking: ZenDesign.Tracking.metric
                )
                .foregroundStyle(valueTint ?? ZenDesign.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let detail {
                Text(detail)
                    .zenType(
                        ZenDesign.Typography.caption,
                        tracking: ZenDesign.Tracking.caption
                    )
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .padding(ZenDesign.Spacing.lg)
        .frame(
            maxWidth: .infinity,
            minHeight: 128,
            alignment: .topLeading
        )
        .zenSurface()
        .accessibilityElement(children: .combine)
    }
}

/// Label · percent · thin bar.
struct ZenMeterRow: View {
    let label: String
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .zenType(
                        ZenDesign.Typography.body,
                        tracking: ZenDesign.Tracking.body
                    )
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Spacer()
                Text("\(percent)%")
                    .font(ZenDesign.Typography.metricCaption.monospacedDigit())
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ZenDesign.Semantic.surfaceSunken)
                    Capsule()
                        .fill(ZenDesign.Semantic.accent)
                        .frame(
                            width: proxy.size.width
                                * CGFloat(max(0, min(percent, 100))) / 100
                        )
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, ZenDesign.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(percent) percent")
    }
}

/// Underline tab strip.
///
/// The selected underline slides between tabs on a shared `matchedGeometry`
/// namespace instead of appearing and disappearing. The eye tracks a moving
/// object without effort and has to re-find a teleporting one — and because the
/// motion is a spring, clicking a third tab mid-slide redirects the underline
/// from wherever it currently is rather than restarting it.
struct ZenTabStrip<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let title: String
        var badge: Int = 0
    }

    let items: [Item]
    @Binding var selection: Tab

    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ZenDesign.Spacing.xl) {
                ForEach(items, id: \.tab) { item in
                    Button {
                        selection = item.tab
                    } label: {
                        VStack(spacing: ZenDesign.Spacing.xs) {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .zenType(
                                        ZenDesign.Typography.bodyStrong,
                                        tracking: ZenDesign.Tracking.body
                                    )
                                if item.badge > 0 {
                                    Text("\(item.badge)")
                                        .font(ZenDesign.Typography.badge)
                                        .foregroundStyle(
                                            ZenDesign.Semantic.warn
                                        )
                                        .padding(.horizontal, 6)
                                        .frame(height: 16)
                                        .background {
                                            Capsule().fill(
                                                ZenDesign.Semantic.warnMuted
                                            )
                                        }
                                }
                            }
                            .foregroundStyle(
                                selection == item.tab
                                    ? ZenDesign.Semantic.textPrimary
                                    : ZenDesign.Semantic.textTertiary
                            )

                            Group {
                                if selection == item.tab {
                                    Capsule()
                                        .fill(ZenDesign.Semantic.accent)
                                        .matchedGeometryEffect(
                                            id: "underline",
                                            in: underline
                                        )
                                } else {
                                    Capsule().fill(Color.clear)
                                }
                            }
                            .frame(height: 2)
                        }
                        // Hugs its label. Without this the underline claims an
                        // equal share of the strip's width, so three tabs each
                        // grew a rule a third of the window wide and the
                        // selected one was impossible to pick out.
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minHeight: ZenDesign.Layout.hitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ZenPressableStyle())
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(
                        selection == item.tab ? .isSelected : []
                    )
                }
                Spacer()
            }
            .animation(ZenDesign.Motion.standard(reduceMotion), value: selection)

            Rectangle()
                .fill(ZenDesign.Semantic.border)
                .frame(height: 1)
        }
    }
}

/// Search field.
struct ZenSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .zenType(
                    ZenDesign.Typography.body,
                    tracking: ZenDesign.Tracking.body
                )
                .zenFocusRing()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                .buttonStyle(ZenPressableStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, ZenDesign.Spacing.sm)
        .frame(height: ZenDesign.Layout.control + 6)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .fill(ZenDesign.Semantic.textPrimary.opacity(0.05))
        }
    }
}

/// Selectable card for mode/priority pickers.
struct ZenChoiceCard: View {
    let title: String
    var badge: String?
    let detail: String
    let selected: Bool
    var titleIcon: String?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let titleIcon {
                        Image(systemName: titleIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                selected
                                    ? ZenDesign.Semantic.accent
                                    : ZenDesign.Semantic.textTertiary
                            )
                    }
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                    if let badge {
                        ZenBadge(text: badge, kind: .neutral)
                    }
                    Spacer(minLength: 0)
                    // A filled check, not a bare tick: the selected card is one
                    // of the three places the accent is allowed to be, and at
                    // this size a hairline glyph does not survive being the
                    // only mark carrying the state.
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ZenDesign.Semantic.accent)
                        .opacity(selected ? 1 : 0)
                        .scaleEffect(selected ? 1 : 0.6)
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            .padding(ZenDesign.Spacing.md)
            .frame(
                maxWidth: .infinity,
                minHeight: 92,
                alignment: .topLeading
            )
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.large,
                    style: .continuous
                )
                .fill(
                    selected
                        ? ZenDesign.Semantic.accentMuted
                        : ZenDesign.Semantic.textPrimary
                            .opacity(hovering ? 0.07 : 0.04)
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.large,
                    style: .continuous
                )
                .strokeBorder(
                    selected
                        ? ZenDesign.Semantic.accent.opacity(0.85)
                        : Color.clear,
                    lineWidth: 1.5
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressableStyle())
        .onHover { hovering = $0 }
        .animation(ZenDesign.Motion.fast(reduceMotion), value: hovering)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: selected)
        .zenFocusRing(cornerRadius: ZenDesign.Radius.large)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Accent-tinted switch with standard macOS behavior.
struct ZenSwitch: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(ZenDesign.Semantic.accent)
            .accessibilityLabel(label)
    }
}

/// Small ghost icon button.
struct ZenIconButton: View {
    let systemImage: String
    let label: String
    var isDanger = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    hovering
                        ? (isDanger
                            ? ZenDesign.Semantic.danger
                            : ZenDesign.Semantic.textPrimary)
                        : ZenDesign.Semantic.textTertiary
                )
                .frame(
                    width: ZenDesign.Layout.control,
                    height: ZenDesign.Layout.control
                )
                .background {
                    // A resting fill, not a hover-only one. These buttons carry
                    // reset and delete actions; with no visible affordance they
                    // were invisible to anyone who had not already swept the
                    // pointer across them.
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .fill(
                        hovering
                            ? (isDanger
                                ? ZenDesign.Semantic.dangerMuted
                                : ZenDesign.Semantic.textPrimary.opacity(0.10))
                            : ZenDesign.Semantic.textPrimary.opacity(0.05)
                    )
                }
                .frame(
                    minWidth: ZenDesign.Layout.hitTarget,
                    minHeight: ZenDesign.Layout.hitTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressableStyle())
        .onHover { hovering = $0 }
        .animation(ZenDesign.Motion.fast(reduceMotion), value: hovering)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Live status: dot + lowercase label, no container.
///
/// The dot breathes on a scale *and* an opacity curve rather than opacity
/// alone. A dot that only dims reads as a rendering artefact at small sizes;
/// one that also swells slightly reads as a pulse, which is the thing being
/// communicated — something is happening right now.
struct ZenStatusLabel: View {
    let text: String
    var tint: Color = ZenDesign.Semantic.textSecondary
    var pulses = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                // A soft halo, so the pulse is legible against both a card and
                // the ZenBar's material without the dot itself having to grow
                // large enough to become a blob.
                Circle()
                    .fill(tint.opacity(0.28))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulsing ? 1.15 : 0.6)
                    .opacity(pulsing ? 0 : 0.9)
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 14, height: 14)

            Text(text.lowercased())
                .zenType(
                    ZenDesign.Typography.captionStrong,
                    tracking: ZenDesign.Tracking.caption
                )
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .lineLimit(1)
        }
        .onAppear {
            guard pulses, !reduceMotion else { return }
            withAnimation(
                .easeOut(duration: 1.4).repeatForever(autoreverses: false)
            ) {
                pulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Hairline progress bar for downloads and long-running work.
struct ZenProgressBar: View {
    /// 0…1
    let value: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ZenDesign.Semantic.surfaceSunken)
                Capsule()
                    .fill(ZenDesign.Semantic.accent)
                    .frame(
                        width: proxy.size.width
                            * CGFloat(max(0, min(value, 1)))
                    )
            }
        }
        .frame(height: 3)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// Mono metadata line for model rows (size · revision · checksum).
struct ZenModelMeta: View {
    let parts: [String]

    var body: some View {
        Text(parts.joined(separator: "  ·  "))
            .font(ZenDesign.Typography.monoSmall)
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
