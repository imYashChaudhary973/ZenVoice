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

/// Ledger screen scaffold: editorial header rule and a responsive content
/// column that stays compact in a normal window and uses a full-screen canvas.
struct ZenScreen<Content: View>: View {
    /// Prose stops at a readable measure even when the column does not.
    ///
    /// Panels, grids and tables genuinely use the width; a sentence does not.
    /// At 13pt across the full 1200pt column a line of body text ran to roughly
    /// 180 characters, about twice a comfortable measure.
    private static var proseWidth: CGFloat { 640 }

    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            let available = max(
                0, proxy.size.width - 80
            )
            let column = min(1_200, available)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(ZenDesign.Typography.pageTitle)
                            .tracking(-0.1)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text(subtitle)
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(
                                maxWidth: Self.proseWidth,
                                alignment: .leading
                            )
                    }

                    Rectangle()
                        .fill(ZenDesign.Semantic.textPrimary)
                        .frame(height: 2)
                        .padding(.top, 14)

                    VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
                        content
                    }
                    .padding(.top, 26)
                }
                .frame(maxWidth: column, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 30)
                .padding(.bottom, ZenDesign.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(ZenDesign.Semantic.canvas)
    }
}

/// Ledger section label: compact uppercase tracking above the content.
struct ZenSection<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(ZenDesign.Typography.sectionTitle)
                    .tracking(1.7)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                Spacer()
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

/// Tonal panel. Rows inside are separated with `ZenPanelDivider`; pass
/// `padding` for free-form content that doesn't use `ZenRow`.
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
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .strokeBorder(ZenDesign.Semantic.borderStrong, lineWidth: 1)
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
        HStack(spacing: ZenDesign.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        iconTint ?? ZenDesign.Semantic.textSecondary
                    )
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
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

            Spacer(minLength: ZenDesign.Spacing.sm)

            trailing
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .padding(.vertical, ZenDesign.Spacing.sm)
        .frame(minHeight: 52)
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
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
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
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text.uppercased())
                .lineLimit(1)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .tracking(0.7)
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(background)
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
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 1)
            Text(text)
                .font(ZenDesign.Typography.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(foreground)
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
            if kind == .info {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .strokeBorder(ZenDesign.Semantic.border)
            }
        }
    }

    private var foreground: Color {
        switch kind {
        case .info: return ZenDesign.Semantic.textSecondary
        case .warn: return ZenDesign.Semantic.warn
        case .danger: return ZenDesign.Semantic.danger
        case .success: return ZenDesign.Semantic.success
        }
    }

    private var background: Color {
        switch kind {
        case .info: return ZenDesign.Semantic.surfaceRaised
        case .warn: return ZenDesign.Semantic.warnMuted
        case .danger: return ZenDesign.Semantic.dangerMuted
        case .success: return ZenDesign.Semantic.successMuted
        }
    }
}

/// Stat tile (prototype `.stat`).
struct ZenStatTile: View {
    let value: String
    let label: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(ZenDesign.Typography.metric)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Text(label)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            if let detail {
                Text(detail)
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.success)
            }
        }
        .padding(ZenDesign.Spacing.md)
        .frame(
            maxWidth: .infinity,
            minHeight: 92,
            maxHeight: 92,
            alignment: .topLeading
        )
        .background(ZenDesign.Semantic.surface)
        .clipShape(
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .strokeBorder(ZenDesign.Semantic.border)
        }
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
                    .font(ZenDesign.Typography.mono)
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
            HStack(spacing: ZenDesign.Spacing.md) {
                ForEach(items, id: \.tab) { item in
                    Button {
                        selection = item.tab
                    } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .font(ZenDesign.Typography.bodyStrong)
                                if item.badge > 0 {
                                    Text("\(item.badge)")
                                        .font(
                                            .system(
                                                size: 10, weight: .semibold
                                            )
                                        )
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
                            Rectangle()
                                .fill(
                                    selection == item.tab
                                        ? ZenDesign.Semantic.accent
                                        : Color.clear
                                )
                                .frame(height: 2)
                        }
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
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.small,
                style: .continuous
            )
            .fill(ZenDesign.Semantic.surface)
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .strokeBorder(ZenDesign.Semantic.borderStrong)
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
                                size: 14.5,
                                weight: .semibold,
                                design: .serif
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
                            .font(.system(size: 10, weight: .bold))
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
            .padding(ZenDesign.Spacing.sm + 2)
            .frame(
                maxWidth: .infinity,
                minHeight: 92,
                alignment: .topLeading
            )
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
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
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .strokeBorder(
                    selected
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Semantic.border
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        : ZenDesign.Semantic.textTertiary
                )
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .fill(
                        hovering
                            ? (isDanger
                                ? ZenDesign.Semantic.dangerMuted
                                : ZenDesign.Semantic.surfaceRaised)
                            : Color.clear
                    )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
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
                .font(ZenDesign.Typography.mono)
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
