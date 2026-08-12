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

// MARK: - ZenVoice v2 component vocabulary
// Every redesigned screen is composed from these shared native components so
// the interface vocabulary stays consistent across the app.

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
                        cornerRadius: min(4, size * 0.16),
                        style: .continuous
                    )
                )
        } else {
            Image(systemName: "waveform")
                .font(.system(size: size * 0.65, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(
                        cornerRadius: min(4, size * 0.16),
                        style: .continuous
                    )
                    .fill(ZenDesign.Semantic.accentMuted)
                }
        }
    }
}

/// The one page scaffold: icon chip, title, subtitle, optional tab strip,
/// content.
///
/// Every section of the settings window renders exactly one of these. Screens
/// that are shown as tabs of a larger section supply only their content — the
/// container owns the scaffold — so a page never grows a second title, a
/// second rule, or a nested scroll view.
///
/// The heading is a `ZenCardHeader`, the same block that heads every card, so
/// a page reads as the outermost card in its own stack rather than as a
/// different kind of object. The horizontal rule that used to sit under the
/// title is gone: cards already carry their own edges, and the rule drew a
/// second, competing boundary a few points above the first one.
struct ZenScreen<Content: View, Tabs: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let tabs: Tabs
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZenCardHeader(
                    systemImage: icon,
                    title: title,
                    subtitle: subtitle,
                    iconSize: 40
                )
                .frame(
                    maxWidth: ZenDesign.Layout.proseColumn,
                    alignment: .leading
                )

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
            // Cards fill the window. They used to be capped at a fixed column
            // width and centred, which is invisible in a small window and
            // obvious in full screen: the content floated in the middle of the
            // pane with a margin on each side that matched neither the sidebar
            // nor the top bar. Long *prose* still needs a measure, so the
            // heading caps its own subtitle rather than the page capping
            // everything.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ZenDesign.Spacing.xl)
            .padding(.top, ZenDesign.Spacing.xs)
            .padding(.bottom, ZenDesign.Spacing.xxl)
        }
        .scrollIndicators(.automatic)
        .background(ZenDesign.Semantic.canvas)
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
/// Custom `.buttonStyle(.plain)` controls and plain text fields lose the
/// system focus ring, which left keyboard navigation through this window with
/// no visible indication of where you were. `ZenDesign.Component.focusRing`
/// existed for this and was used in exactly one place.
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
                    lineWidth: 2
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
///
/// Sentence case at body weight, not tracked-out uppercase. Uppercase tracking
/// belongs on the eyebrow *inside* a stat tile, where it labels a number; used
/// as a section heading it reads as a system message rather than as a title,
/// and every heading in the window looked like a warning.
struct ZenSection<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: ZenDesign.Spacing.sm) {
                Text(title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Spacer(minLength: 0)
                if let caption {
                    Text(caption)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The card. One surface, one hairline, one large radius — the single
/// container every screen is built from.
struct ZenPanel<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .strokeBorder(ZenDesign.Semantic.border, lineWidth: 1)
        }
    }
}

/// A card that heads itself: icon chip, title, optional subtitle, then
/// content. `ZenPanel` remains available for cards that supply their own
/// heading, or none.
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
                    titleFont: .system(size: 16, weight: .semibold),
                    iconSize: 32,
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

/// A row nested inside a card: its own inset surface rather than a band
/// between two dividers. Use for list items that carry their own controls.
struct ZenInsetRow<Content: View>: View {
    var tinted = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, ZenDesign.Spacing.sm)
            .padding(.vertical, ZenDesign.Spacing.sm - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .fill(
                    tinted
                        ? ZenDesign.Semantic.accentMuted
                        : ZenDesign.Semantic.surfaceRaised
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                    .strokeBorder(
                        tinted
                            ? ZenDesign.Semantic.accent.opacity(0.35)
                            : ZenDesign.Semantic.border,
                        lineWidth: 1
                    )
                }
            }
    }
}

struct ZenPanelDivider: View {
    var body: some View {
        Divider().overlay(ZenDesign.Semantic.border)
    }
}

/// List row: icon chip · title/sub · trailing control (prototype `.row`).
struct ZenRow<Trailing: View>: View {
    var icon: String?
    var iconTint: Color?
    var iconBackground: Color?
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ZenDesign.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        iconTint ?? ZenDesign.Semantic.textSecondary
                    )
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                iconBackground
                                    ?? ZenDesign.Semantic.surfaceRaised
                            )
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(ZenDesign.Typography.caption)
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

/// Keyboard-key chip (prototype `.kbd`).
struct ZenKbd: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(ZenDesign.Semantic.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 24)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(ZenDesign.Semantic.surfaceRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(ZenDesign.Semantic.borderStrong)
                    }
            }
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

/// Badge (prototype `.badge`): quiet capsule with optional dot/icon.
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
                Circle().fill(foreground).frame(width: 6, height: 6)
            }
            if let systemImage {
                Image(systemName: systemImage)
                    .font(ZenDesign.Typography.badge)
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
        case .neutral: return ZenDesign.Semantic.textSecondary
        case .success: return ZenDesign.Semantic.success
        case .accent: return ZenDesign.Semantic.accent
        case .danger: return ZenDesign.Semantic.danger
        case .warn: return ZenDesign.Semantic.warn
        }
    }

    private var background: Color {
        switch kind {
        case .neutral: return ZenDesign.Semantic.surfaceRaised
        case .success: return ZenDesign.Semantic.successMuted
        case .accent: return ZenDesign.Semantic.accentMuted
        case .danger: return ZenDesign.Semantic.dangerMuted
        case .warn: return ZenDesign.Semantic.warnMuted
        }
    }
}

/// Inline banner (prototype `.banner`).
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
                .font(ZenDesign.Typography.body)
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
        .overlay {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .strokeBorder(border)
        }
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

    private var border: Color {
        foreground.opacity(0.3)
    }
}

/// Stat tile: uppercase eyebrow with an icon, then the number at display
/// size, then one line of context.
///
/// The label sits *above* the value, which is the order the eye wants — you
/// read what the number is before you read the number.
struct ZenStatTile: View {
    let value: String
    let label: String
    var detail: String?
    var icon: String?
    var valueTint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(label.uppercased())
                    .font(ZenDesign.Typography.eyebrow)
                    .tracking(1.0)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .lineLimit(1)
            }
            Text(value)
                .font(ZenDesign.Typography.metric)
                .foregroundStyle(
                    valueTint ?? ZenDesign.Semantic.textPrimary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(ZenDesign.Spacing.lg)
        .frame(
            maxWidth: .infinity,
            minHeight: 132,
            alignment: .topLeading
        )
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
            .strokeBorder(ZenDesign.Semantic.border)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Label · percent · thin bar (prototype `.meter-row`).
struct ZenMeterRow: View {
    let label: String
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Spacer()
                Text("\(percent)%")
                    .font(ZenDesign.Typography.metricCaption)
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
            .frame(height: 4)
        }
        .padding(.vertical, ZenDesign.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(percent) percent")
    }
}

/// Underline tab strip (prototype `.tabs`).
struct ZenTabStrip<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let title: String
        var badge: Int = 0
    }

    let items: [Item]
    @Binding var selection: Tab

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
                                    .font(ZenDesign.Typography.bodyStrong)
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
                            RoundedRectangle(
                                cornerRadius: 1.5,
                                style: .continuous
                            )
                            .fill(
                                selection == item.tab
                                    ? ZenDesign.Semantic.accent
                                    : Color.clear
                            )
                            .frame(height: 2.5)
                        }
                        // Hugs its label. Without this the underline claims an
                        // equal share of the strip's width, so three tabs each
                        // grew a rule a third of the window wide and the
                        // selected one was impossible to pick out.
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minHeight: ZenDesign.Layout.hitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(
                        selection == item.tab ? .isSelected : []
                    )
                }
                Spacer()
            }
            Divider().overlay(ZenDesign.Semantic.border)
        }
    }
}

/// Search field (prototype `.search-wrap`).
struct ZenSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(ZenDesign.Typography.body)
                .zenFocusRing()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                .buttonStyle(.plain)
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
            .fill(ZenDesign.Semantic.surfaceRaised)
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .strokeBorder(ZenDesign.Semantic.border)
            }
        }
    }
}

/// Selectable card for mode/priority pickers (prototype `.reco button`,
/// `.lang-chip`).
struct ZenChoiceCard: View {
    let title: String
    var badge: String?
    let detail: String
    let selected: Bool
    var titleIcon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let titleIcon {
                        Image(systemName: titleIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                selected
                                    ? ZenDesign.Semantic.accent
                                    : ZenDesign.Semantic.textSecondary
                            )
                    }
                    Text(title)
                        .font(
                            .system(
                                size: 14,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                    if let badge {
                        ZenBadge(text: badge, kind: .neutral)
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(ZenDesign.Typography.badge)
                            .foregroundStyle(ZenDesign.Semantic.accent)
                    }
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            .padding(ZenDesign.Spacing.md)
            .frame(
                maxWidth: .infinity,
                minHeight: 96,
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
                        : ZenDesign.Semantic.surface
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.large,
                    style: .continuous
                )
                .strokeBorder(
                    selected
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Semantic.border,
                    lineWidth: selected ? 1.5 : 1
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// Small ghost icon button (prototype `.icon-btn`).
struct ZenIconButton: View {
    let systemImage: String
    let label: String
    var isDanger = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    hovering
                        ? (isDanger
                            ? ZenDesign.Semantic.danger
                            : ZenDesign.Semantic.textPrimary)
                        : ZenDesign.Semantic.textSecondary
                )
                .frame(
                    width: ZenDesign.Layout.control,
                    height: ZenDesign.Layout.control
                )
                .background {
                    // A resting fill and border, not a hover-only one. These
                    // buttons carry reset and delete actions; with no visible
                    // affordance they were invisible to anyone who had not
                    // already swept the pointer across them.
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .fill(
                        hovering
                            ? (isDanger
                                ? ZenDesign.Semantic.dangerMuted
                                : ZenDesign.Semantic.surfaceRaised)
                            : ZenDesign.Semantic.surfaceRaised.opacity(0.6)
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .strokeBorder(
                            hovering && isDanger
                                ? ZenDesign.Semantic.danger.opacity(0.5)
                                : ZenDesign.Semantic.border,
                            lineWidth: 1
                        )
                    }
                }
                .frame(
                    minWidth: ZenDesign.Layout.hitTarget,
                    minHeight: ZenDesign.Layout.hitTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Terminal-style live status: dot + lowercase mono label, no container.
/// For transient runtime states ("● listening", "● downloading 42%") —
/// use `ZenBadge` for persistent states that describe an item.
struct ZenStatusLabel: View {
    let text: String
    var tint: Color = ZenDesign.Semantic.textSecondary
    var pulses = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .opacity(dimmed ? 0.35 : 1)
            Text(text.lowercased())
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .lineLimit(1)
        }
        .onAppear {
            guard pulses, !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
            ) {
                dimmed = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Hairline 2pt progress bar for downloads and long-running work.
struct ZenProgressBar: View {
    /// 0…1
    let value: Double

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
        .frame(height: 2)
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
