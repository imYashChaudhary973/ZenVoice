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
/// The window toolbar owns page identity. Screen content starts directly with
/// the controls shown in the supplied redesign instead of repeating a second
/// title block inside every scroll view.
struct ZenScreen<Content: View, Tabs: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let tabs: Tabs
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if Tabs.self != EmptyView.self {
                tabs
                    .padding(.horizontal, ZenDesign.Spacing.xl)
                    .padding(.top, ZenDesign.Spacing.lg)
                    .padding(.bottom, ZenDesign.Spacing.sm)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ZenDesign.Spacing.xl)
                .padding(
                    .top,
                    Tabs.self == EmptyView.self
                        ? ZenDesign.Spacing.xl
                        : ZenDesign.Spacing.md
                )
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .scrollIndicators(.automatic)
        }
        .background(ZenDesign.Semantic.canvas)
        .toolbarBackground(.visible, for: .windowToolbar)
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

/// Draws a visible ring while a non-button control holds keyboard focus.
///
/// `ZenPressButtonStyle` handles buttons centrally. This modifier covers plain
/// text fields and other focusable controls that do not receive a native ring.
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

/// Tactile 3D keycap face. Visual language from Opensource UI `ThreeDButton`.
///
/// Resting lift + top sheen + bottom recess. Press inverts the inset and
/// flattens the lift so the key sinks. Callers own the 1-point travel.
enum ZenKeycapKind {
    /// Filled accent — primary actions.
    case solid
    /// Raised surface — secondary, menus, icon buttons.
    case muted
    /// Filled danger — destructive actions.
    case danger
}

struct ZenKeycap: View {
    var kind: ZenKeycapKind = .muted
    var isPressed = false
    var cornerRadius: CGFloat = ZenDesign.Radius.small
    var isEnabled = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        let pressed = isPressed && isEnabled
        let dark = colorScheme == .dark

        shape
            .fill(face(pressed: pressed))
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(
                                    pressed ? sheen.pressedTop : sheen.restTop
                                ),
                                Color.clear,
                                Color.black.opacity(
                                    pressed
                                        ? sheen.pressedBottom
                                        : sheen.restBottom
                                ),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(
                    edge,
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
            }
            .shadow(
                color: Color.black.opacity(
                    pressed ? (dark ? 0.28 : 0.10) : (dark ? 0.36 : 0.14)
                ),
                radius: pressed ? 1 : 3,
                x: 0,
                y: pressed ? 1 : 2
            )
    }

    private var sheen: (
        restTop: Double,
        restBottom: Double,
        pressedTop: Double,
        pressedBottom: Double
    ) {
        switch kind {
        case .solid, .danger:
            return (0.16, 0.28, 0.04, 0.42)
        case .muted:
            return colorScheme == .dark
                ? (0.12, 0.32, 0.04, 0.40)
                : (0.45, 0.10, 0.08, 0.16)
        }
    }

    private func face(pressed: Bool) -> Color {
        switch kind {
        case .solid:
            return pressed
                ? ZenDesign.Semantic.accentStrong
                : ZenDesign.Semantic.accentFill
        case .muted:
            return pressed
                ? ZenDesign.Semantic.surfaceRaised
                : ZenDesign.Component.shortcutBackground
        case .danger:
            return ZenDesign.Semantic.danger.opacity(pressed ? 0.78 : 1)
        }
    }

    private var edge: Color {
        switch kind {
        case .solid:
            return Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18)
        case .muted:
            return ZenDesign.Semantic.borderStrong
        case .danger:
            return Color.black.opacity(0.22)
        }
    }
}

/// Immediate press feedback and keyboard focus for custom controls that cannot
/// use a native bordered button style. Feedback begins on pointer-down through
/// `configuration.isPressed`, remains interruptible, and never bounces.
///
/// Painted controls sink one point like an Opensource UI keycap. Reduce Motion
/// keeps the focus ring and drops the travel.
struct ZenPressButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = ZenDesign.Radius.small

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .offset(
                y: configuration.isPressed && isEnabled && !reduceMotion
                    ? 1
                    : 0
            )
            .opacity(isEnabled ? 1 : 0.45)
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    isFocused && isEnabled
                        ? ZenDesign.Component.focusRing
                        : Color.clear,
                    lineWidth: 2
                )
                .padding(-2)
                .allowsHitTesting(false)
            }
            .animation(
                ZenDesign.Motion.fast(reduceMotion),
                value: configuration.isPressed
            )
            .animation(
                ZenDesign.Motion.fast(reduceMotion),
                value: isFocused
            )
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
                    .font(.headline)
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
    @Environment(\.colorSchemeContrast) private var contrast

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
            .strokeBorder(
                contrast == .increased
                    ? ZenDesign.Semantic.borderStrong
                    : ZenDesign.Semantic.border.opacity(0.72),
                lineWidth: contrast == .increased ? 1.5 : 1
            )
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
                            : Color.clear,
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
        HStack(alignment: .center, spacing: ZenDesign.Spacing.sm) {
            if let icon {
                ZenIconChip(
                    systemImage: icon,
                    size: ZenDesign.Layout.hitTarget,
                    tint: iconTint ?? ZenDesign.Semantic.textSecondary
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)

            trailing
                .layoutPriority(1)
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .padding(.vertical, ZenDesign.Spacing.sm)
        .frame(minHeight: ZenDesign.Layout.hitTarget + 16)
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

    private var isWord: Bool { text.count > 1 }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, isWord ? 12 : 7)
            .frame(
                minWidth: text.count > 8 ? 96 : isWord ? 48 : 26,
                minHeight: 28
            )
            .background {
                ZenKeycap(
                    kind: .muted,
                    cornerRadius: 6
                )
            }
    }
}

/// Shortcut combo rendered as individual key chips.
struct ZenKbdGroup: View {
    let combo: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                ZenKbd(text: key)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo)
    }

    private var keys: [String] {
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

/// Opensource UI system alert: glass card, two-line body, red 3D keycap.
struct ZenSystemAlert: View {
    let title: String
    let description: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textOnDanger)
                .frame(width: 38, height: 38)
                .background {
                    ZenKeycap(kind: .danger, cornerRadius: 10)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                Text(description)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .fill(ZenDesign.Semantic.surface.opacity(0.92))
            .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .strokeBorder(ZenDesign.Semantic.borderStrong)
        }
        .accessibilityElement(children: .combine)
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

/// Sliding segmented toggle. Visual language from Opensource UI
/// `SegmentedToggleButton`: inset well, raised pill, eased travel.
struct ZenTabStrip<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let title: String
        var badge: Int = 0
    }

    let items: [Item]
    @Binding var selection: Tab

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let selected = item.tab == selection
                Button {
                    withAnimation(ZenDesign.Motion.standard(reduceMotion)) {
                        selection = item.tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(item.title)
                        if item.badge > 0 {
                            Text("\(item.badge)")
                                .font(ZenDesign.Typography.badge)
                                .padding(.horizontal, 6)
                                .frame(minHeight: 18)
                                .background {
                                    Capsule().fill(
                                        selected
                                            ? ZenDesign.Semantic.accent
                                                .opacity(0.22)
                                            : ZenDesign.Semantic.surfaceRaised
                                    )
                                }
                        }
                    }
                    .font(ZenDesign.Typography.button)
                    .foregroundStyle(
                        selected
                            ? ZenDesign.Semantic.textPrimary
                            : ZenDesign.Semantic.textSecondary
                    )
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background {
                        if selected {
                            RoundedRectangle(
                                cornerRadius: ZenDesign.Radius.small,
                                style: .continuous
                            )
                            .fill(ZenDesign.Semantic.surfaceRaised)
                            .shadow(
                                color: Color.black.opacity(0.12),
                                radius: 2,
                                y: 1
                            )
                            .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .fill(ZenDesign.Semantic.surfaceSunken)
        }
        .frame(minHeight: ZenDesign.Layout.hitTarget)
        .accessibilityElement(children: .contain)
    }
}

/// Search field. Opensource UI `SearchInput`: leading glyph, clear, no ring.
struct ZenSearchField: View {
    let placeholder: String
    @Binding var text: String
    var compact = false
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(ZenDesign.Typography.body)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .frame(
                            width: compact
                                ? ZenDesign.Layout.control
                                : ZenDesign.Layout.hitTarget,
                            height: compact
                                ? ZenDesign.Layout.control
                                : ZenDesign.Layout.hitTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(
                    ZenPressButtonStyle(
                        cornerRadius: ZenDesign.Radius.medium
                    )
                )
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, ZenDesign.Spacing.sm)
        .frame(
            height: compact
                ? ZenDesign.Layout.control
                : ZenDesign.Layout.hitTarget
        )
        .background {
            if !compact {
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
                    .strokeBorder(ZenDesign.Semantic.borderStrong)
                }
            }
        }
        .modifier(CompactSearchGlass(enabled: compact))
        .zenFocusRing()
    }
}

private struct CompactSearchGlass: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.zenGlassSurface(
                cornerRadius: ZenDesign.Radius.pill,
                interactive: true
            )
        } else {
            content
        }
    }
}

struct ZenTextInput: View {
    let placeholder: String
    @Binding var text: String
    var icon: String?
    var minWidth: CGFloat = 170

    var body: some View {
        HStack(spacing: ZenDesign.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .accessibilityHidden(true)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(ZenDesign.Typography.body)
        }
        .padding(.horizontal, ZenDesign.Spacing.sm)
        .frame(minWidth: minWidth, minHeight: ZenDesign.Layout.hitTarget)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.small,
                style: .continuous
            )
            .fill(ZenDesign.Semantic.surfaceRaised)
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .strokeBorder(ZenDesign.Semantic.borderStrong)
            }
        }
        .zenFocusRing()
    }
}

/// Labelled textarea with a count. Opensource UI `TextareaFieldInput`.
struct ZenTextArea: View {
    var label: String
    @Binding var text: String
    var hint: String?
    var maxLength: Int = 2_000
    var minHeight: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Spacer()
                Text("\(text.count)/\(maxLength)")
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(
                        text.count >= maxLength
                            ? ZenDesign.Semantic.warn
                            : ZenDesign.Semantic.textTertiary
                    )
                    .monospacedDigit()
            }
            TextEditor(text: $text)
                .font(ZenDesign.Typography.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: minHeight)
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
                        .strokeBorder(ZenDesign.Semantic.borderStrong)
                    }
                }
                .onChange(of: text) { _, next in
                    if next.count > maxLength {
                        text = String(next.prefix(maxLength))
                    }
                }
            if let hint {
                Text(hint)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Select-style picker. Chevron rotates like Opensource UI `SelectFieldInput`;
/// the menu panel uses a spring popover to match the dropdowns.
struct ZenMenuPicker<Option: Hashable>: View {
    let label: String
    let options: [Option]
    @Binding var selection: Option
    var minWidth: CGFloat = 190
    var compact = false
    let title: (Option) -> String

    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(ZenDesign.Motion.fast(reduceMotion)) {
                open.toggle()
            }
        } label: {
            HStack(spacing: ZenDesign.Spacing.sm) {
                Text(title(selection))
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: ZenDesign.Spacing.sm)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, compact ? 10 : ZenDesign.Spacing.sm)
            .frame(
                minWidth: minWidth,
                minHeight: compact
                    ? ZenDesign.Layout.control
                    : ZenDesign.Layout.hitTarget
            )
            .background {
                ZenKeycap(kind: .muted, isPressed: open)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                        open = false
                    } label: {
                        HStack {
                            Text(title(option))
                                .font(ZenDesign.Typography.body)
                            Spacer()
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .frame(minWidth: minWidth)
        }
        .frame(width: compact ? minWidth : nil)
        .fixedSize(horizontal: !compact, vertical: false)
        .accessibilityLabel(label)
        .accessibilityValue(title(selection))
        .accessibilityAddTraits(.isButton)
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
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        : hovering
                            ? ZenDesign.Semantic.surfaceRaised
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
                        : hovering
                            ? ZenDesign.Semantic.borderStrong
                            : ZenDesign.Semantic.border,
                    lineWidth: selected ? 1.5 : 1
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ZenPressButtonStyle(cornerRadius: ZenDesign.Radius.large)
        )
        .onHover { hovering = $0 }
        .animation(
            ZenDesign.Motion.fast(reduceMotion),
            value: hovering
        )
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Native switch. Motion uses the same critically damped spring as the rest
/// of ZenVoice — no glass wrapper around the control.
struct ZenSwitch: View {
    @Binding var isOn: Bool
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(ZenDesign.Semantic.accentFill)
            .animation(ZenDesign.Motion.fast(reduceMotion), value: isOn)
            .accessibilityLabel(label)
    }
}

/// Small 3D icon button (Opensource UI `ThreeDIconButton`).
struct ZenIconButton: View {
    let systemImage: String
    let label: String
    var isDanger = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(
            ZenIconKeycapStyle(isDanger: isDanger, hovering: hovering)
        )
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct ZenIconKeycapStyle: ButtonStyle {
    var isDanger: Bool
    var hovering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(iconColor(pressed: configuration.isPressed))
            .frame(
                width: ZenDesign.Layout.control,
                height: ZenDesign.Layout.control
            )
            .background {
                ZenKeycap(
                    kind: .muted,
                    isPressed: configuration.isPressed,
                    isEnabled: isEnabled
                )
            }
            .frame(
                minWidth: ZenDesign.Layout.hitTarget,
                minHeight: ZenDesign.Layout.hitTarget
            )
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .strokeBorder(
                    isFocused && isEnabled
                        ? ZenDesign.Component.focusRing
                        : Color.clear,
                    lineWidth: 2
                )
                .padding(-2)
                .allowsHitTesting(false)
            }
            .offset(
                y: configuration.isPressed && isEnabled && !reduceMotion
                    ? 1
                    : 0
            )
            .opacity(isEnabled ? 1 : 0.45)
            .animation(
                ZenDesign.Motion.fast(reduceMotion),
                value: configuration.isPressed
            )
            .animation(
                ZenDesign.Motion.fast(reduceMotion),
                value: isFocused
            )
    }

    private func iconColor(pressed: Bool) -> Color {
        if isDanger && (hovering || pressed) {
            return ZenDesign.Semantic.danger
        }
        return hovering || pressed
            ? ZenDesign.Semantic.textPrimary
            : ZenDesign.Semantic.textSecondary
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

/// Hold-to-confirm destructive control. Visual language from Opensource UI
/// `HoldToDeleteButton`: the key sinks and a danger fill wipes across.
/// Release early to cancel. VoiceOver gets an immediate Delete action.
struct ZenHoldToDeleteButton: View {
    var label = "Hold to delete"
    var doneLabel = "Deleted"
    var holdDuration: TimeInterval = 1.1
    var minWidth: CGFloat? = 168
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var done = false
    @State private var holdTask: Task<Void, Never>?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        face
            .overlay(alignment: .leading) { wipe }
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .contentShape(Rectangle())
            .overlay { focusRing }
            .offset(y: holding && isEnabled && !reduceMotion ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(ZenDesign.Motion.fast(reduceMotion), value: holding)
            .focusable()
            .gesture(holdDrag)
            .onKeyPress(
                keys: [.space, .return],
                phases: [.down, .up],
                action: handleKey
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(done ? doneLabel : label)
            .accessibilityHint("Hold to confirm")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Delete", action)
            .onChange(of: isEnabled, initial: false) { _, enabled in
                if !enabled { reset() }
            }
    }

    private var face: some View {
        caption(color: ZenDesign.Semantic.danger)
            .padding(.horizontal, 13)
            .frame(minWidth: minWidth)
            .frame(height: ZenDesign.Layout.control)
            .background {
                ZenKeycap(
                    kind: .muted,
                    isPressed: (holding || done) && isEnabled,
                    isEnabled: isEnabled
                )
            }
    }

    private var wipe: some View {
        GeometryReader { geo in
            ZenDesign.Semantic.danger
                .frame(width: geo.size.width * progress)
                .overlay(alignment: .leading) {
                    caption(color: ZenDesign.Semantic.textOnDanger)
                        .padding(.horizontal, 13)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .clipped()
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.small,
                style: .continuous
            )
        )
    }

    private var focusRing: some View {
        RoundedRectangle(
            cornerRadius: ZenDesign.Radius.small,
            style: .continuous
        )
        .strokeBorder(
            isFocused && isEnabled
                ? ZenDesign.Component.focusRing
                : Color.clear,
            lineWidth: 2
        )
        .padding(-2)
        .allowsHitTesting(false)
    }

    private var holdDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = hypot(
                    value.translation.width,
                    value.translation.height
                )
                if distance > 44 {
                    cancelHold()
                } else {
                    startHold()
                }
            }
            .onEnded { _ in cancelHold() }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard isEnabled, !done else { return .ignored }
        if press.phase == .down {
            startHold()
            return .handled
        }
        if press.phase == .up {
            cancelHold()
            return .handled
        }
        return .ignored
    }

    private func caption(color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark" : "trash")
                .font(.system(size: 12, weight: .semibold))
            Text(done ? doneLabel : label)
                .font(ZenDesign.Typography.button)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(color)
    }

    private func startHold() {
        guard isEnabled, !done, holdTask == nil else { return }
        holding = true
        if reduceMotion {
            progress = 1
        } else {
            withAnimation(.linear(duration: holdDuration)) {
                progress = 1
            }
        }
        holdTask = Task { @MainActor in
            let nanos = UInt64(holdDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            holdTask = nil
            done = true
            holding = false
            progress = 1
            action()
            try? await Task.sleep(for: .milliseconds(1_600))
            if !Task.isCancelled { reset() }
        }
    }

    private func cancelHold() {
        guard !done else { return }
        holdTask?.cancel()
        holdTask = nil
        holding = false
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.3)) {
            progress = 0
        }
    }

    private func reset() {
        holdTask?.cancel()
        holdTask = nil
        done = false
        holding = false
        progress = 0
    }
}

/// 3D copy control. Opensource UI `CopyButton`: keycap, icon swap, Copied.
struct ZenCopyButton: View {
    var label = "Copy"
    var copiedLabel = "Copied"
    var minWidth: CGFloat? = 88
    let action: () -> Void

    @State private var copied = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            action()
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1_600))
                copied = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                Text(copied ? copiedLabel : label)
                    .font(ZenDesign.Typography.button)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(
                copied
                    ? ZenDesign.Semantic.success
                    : ZenDesign.Semantic.textPrimary
            )
            .padding(.horizontal, 13)
            .frame(minWidth: minWidth)
            .frame(height: ZenDesign.Layout.control)
            .background {
                ZenKeycap(kind: .muted, isEnabled: isEnabled)
            }
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ZenPressButtonStyle(cornerRadius: ZenDesign.Radius.small)
        )
        .animation(ZenDesign.Motion.fast(reduceMotion), value: copied)
        .accessibilityLabel(copied ? copiedLabel : label)
    }
}

/// Native menu behind a 3D ellipsis trigger. Opensource UI kebab, macOS menu.
struct ZenKebabMenu<Content: View>: View {
    var label = "More actions"
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .frame(
                    width: ZenDesign.Layout.hitTarget,
                    height: ZenDesign.Layout.hitTarget
                )
                .background {
                    ZenKeycap(kind: .muted)
                }
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
    }
}
