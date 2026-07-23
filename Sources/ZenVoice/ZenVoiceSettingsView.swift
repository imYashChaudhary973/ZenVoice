import SwiftUI

struct ZenVoiceSettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case shortcuts = "Shortcuts"
        case privacy = "Privacy"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview:
                return "rectangle.grid.2x2"
            case .shortcuts:
                return "command"
            case .privacy:
                return "hand.raised"
            }
        }
    }

    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var appState: AppState
    @State private var selection: Section = .overview

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(ZenDesign.Semantic.border)
                .frame(width: 1)
            content
        }
        .background(ZenDesign.Semantic.canvas)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.refreshSystemStatus()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                brandLogo(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZenVoice")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text("Local voice, refined")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }
            .padding(.horizontal, ZenDesign.Spacing.lg)
            .padding(.top, 34)
            .padding(.bottom, 30)

            Text("ZENVOICE")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .padding(.horizontal, ZenDesign.Spacing.lg)
                .padding(.bottom, 8)

            VStack(spacing: 5) {
                ForEach(Section.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: section.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                            Text(section.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(
                            selection == section
                                ? ZenDesign.Semantic.textPrimary
                                : ZenDesign.Semantic.textSecondary
                        )
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background {
                            RoundedRectangle(
                                cornerRadius: ZenDesign.Radius.small,
                                style: .continuous
                            )
                            .fill(
                                selection == section
                                    ? ZenDesign.Component.selectedNavigation
                                    : Color.clear
                            )
                            .overlay {
                                if selection == section {
                                    RoundedRectangle(
                                        cornerRadius: ZenDesign.Radius.small,
                                        style: .continuous
                                    )
                                    .strokeBorder(
                                        ZenDesign.Semantic.accent.opacity(0.16),
                                        lineWidth: 1
                                    )
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(ZenDesign.Semantic.success)
                    .frame(width: 7, height: 7)
                    .shadow(
                        color: ZenDesign.Semantic.success.opacity(0.55),
                        radius: 4
                    )
                Text("Processing stays local")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
            .padding(.horizontal, ZenDesign.Spacing.lg)
            .padding(.bottom, ZenDesign.Spacing.lg)
        }
        .frame(width: 206)
        .background(ZenDesign.Semantic.sidebar)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .overview:
            OverviewScreen(
                viewModel: viewModel,
                appState: appState,
                openShortcuts: { selection = .shortcuts }
            )
        case .shortcuts:
            ShortcutsScreen(viewModel: viewModel)
        case .privacy:
            PrivacyScreen(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func brandLogo(size: CGFloat) -> some View {
        if let logo = BrandAssets.zenLogo {
            Image(nsImage: logo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: size * 0.25,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: size * 0.25,
                        style: .continuous
                    )
                    .strokeBorder(
                        ZenDesign.Semantic.accent.opacity(0.28),
                        lineWidth: 1
                    )
                }
        } else {
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: size, height: size)
        }
    }
}

private struct OverviewScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var appState: AppState
    let openShortcuts: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "GOOD EVENING",
                    title: "Your voice. Your Mac.",
                    subtitle: "Fast local dictation without sending your audio away."
                )

                hero

                HStack(spacing: ZenDesign.Spacing.md) {
                    StatusCard(
                        icon: "waveform",
                        title: "Dictation",
                        value: appState.phase == .listening ? "Listening" : "Ready",
                        tint: ZenDesign.Semantic.success
                    )
                    StatusCard(
                        icon: "character.book.closed",
                        title: "Language",
                        value: "English",
                        tint: ZenDesign.Semantic.accent
                    )
                    StatusCard(
                        icon: "lock.shield",
                        title: "Processing",
                        value: "On-device",
                        tint: Color(red: 0.48, green: 0.68, blue: 1.0)
                    )
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 17) {
                        Text("Start dictating")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)

                        QuickStep(
                            number: "1",
                            title: "Place your cursor",
                            detail: "Click any text field in any macOS app."
                        )
                        QuickStep(
                            number: "2",
                            title: "Use your shortcut",
                            detail: viewModel.currentShortcut.displayName
                        )
                        QuickStep(
                            number: "3",
                            title: "Speak, then finish",
                            detail: "Press the shortcut again or select the checkmark."
                        )
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
        .background(ZenDesign.Semantic.canvas)
    }

    private var hero: some View {
        ZenCard {
            HStack(spacing: ZenDesign.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(ZenDesign.Semantic.accentMuted)
                        .frame(width: 74, height: 74)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(ZenDesign.Semantic.accent)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Dictate anywhere")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text("ZenVoice listens only when you ask and pastes the local transcript into the active app.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                Button(action: openShortcuts) {
                    VStack(spacing: 4) {
                        Text(viewModel.currentShortcut.displayName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("CUSTOMIZE")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.9)
                            .opacity(0.58)
                    }
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.medium,
                            style: .continuous
                        )
                        .fill(ZenDesign.Component.shortcutBackground)
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: ZenDesign.Radius.medium,
                                style: .continuous
                            )
                            .strokeBorder(
                                ZenDesign.Semantic.borderStrong,
                                lineWidth: 1
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ShortcutsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "CONTROLS",
                    title: "Shortcuts",
                    subtitle: "Choose a combination that feels natural on your keyboard."
                )

                ZenCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .center, spacing: 15) {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                                Image(systemName: "waveform.badge.mic")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(ZenDesign.Semantic.accent)
                            }
                            .frame(width: 46, height: 46)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start or stop dictation")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text("Works globally while ZenVoice is running.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }

                            Spacer()

                            Button {
                                if viewModel.isCapturingShortcut {
                                    viewModel.cancelShortcutCapture()
                                } else {
                                    viewModel.beginShortcutCapture()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if viewModel.isCapturingShortcut {
                                        Circle()
                                            .fill(ZenDesign.Semantic.accent)
                                            .frame(width: 7, height: 7)
                                        Text("Press shortcut…")
                                    } else {
                                        Image(systemName: "keyboard")
                                        Text(
                                            viewModel.currentShortcut.displayName
                                        )
                                    }
                                }
                                .font(
                                    .system(
                                        size: 12,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(
                                    viewModel.isCapturingShortcut
                                        ? Color.black.opacity(0.82)
                                        : ZenDesign.Semantic.textPrimary
                                )
                                .padding(.horizontal, 15)
                                .frame(minWidth: 128, minHeight: 38)
                                .background {
                                    RoundedRectangle(
                                        cornerRadius: ZenDesign.Radius.small,
                                        style: .continuous
                                    )
                                    .fill(
                                        viewModel.isCapturingShortcut
                                            ? ZenDesign.Semantic.accent
                                            : ZenDesign.Component.shortcutBackground
                                    )
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius: ZenDesign.Radius.small,
                                            style: .continuous
                                        )
                                        .strokeBorder(
                                            viewModel.isCapturingShortcut
                                                ? ZenDesign.Component.focusRing
                                                : ZenDesign.Semantic.borderStrong,
                                            lineWidth: 1
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("How to record")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text("Select the shortcut, then press one key with Command, Control, Option, or Shift. Press Escape to cancel.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 18)
                            Button("Reset Default") {
                                viewModel.resetShortcut()
                            }
                            .buttonStyle(ZenSecondaryButtonStyle())
                        }
                    }
                }

                if let error = viewModel.shortcutError {
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.danger)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.danger.opacity(0.10))
                    }
                }

                ZenCard {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "lightbulb.max.fill")
                            .foregroundStyle(ZenDesign.Semantic.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Choose something memorable")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text("A two-modifier shortcut is less likely to conflict with shortcuts in other apps. ZenVoice keeps your choice on this Mac.")
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
        .background(ZenDesign.Semantic.canvas)
    }
}

private struct PrivacyScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "TRUST",
                    title: "Privacy & permissions",
                    subtitle: "See exactly what ZenVoice can access on your Mac."
                )

                ZenCard {
                    VStack(spacing: 0) {
                        PermissionRow(
                            icon: "mic.fill",
                            title: "Microphone",
                            detail: "Used only while a dictation is active.",
                            status: viewModel.microphoneStatus,
                            action: viewModel.requestMicrophoneAccess
                        )

                        Divider()
                            .overlay(ZenDesign.Semantic.border)
                            .padding(.leading, 54)

                        PermissionRow(
                            icon: "accessibility",
                            title: "Accessibility",
                            detail: "Used to paste text into the active app.",
                            status: viewModel.accessibilityStatus,
                            action: viewModel.requestAccessibilityAccess
                        )
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundStyle(ZenDesign.Semantic.accent)
                            Text("Local processing")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Spacer()
                            StatusPill(
                                title: viewModel.isLocalModelReady
                                    ? "Model ready"
                                    : "Model missing",
                                isPositive: viewModel.isLocalModelReady
                            )
                        }

                        PrivacyFact(
                            icon: "network.slash",
                            text: "No cloud transcription or account"
                        )
                        PrivacyFact(
                            icon: "waveform.path",
                            text: "Temporary audio is deleted after transcription"
                        )
                        PrivacyFact(
                            icon: "clock.arrow.circlepath",
                            text: "No transcript history database"
                        )
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
        .background(ZenDesign.Semantic.canvas)
    }
}

private struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.35)
                .foregroundStyle(ZenDesign.Semantic.accent)
            Text(title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }
}

private struct ZenCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(ZenDesign.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .fill(ZenDesign.Component.cardBackground)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                    .strokeBorder(
                        ZenDesign.Component.cardBorder,
                        lineWidth: 1
                    )
                }
            }
    }
}

private struct StatusCard: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    Text(value)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                }
            }
        }
    }
}

private struct QuickStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.78))
                .frame(width: 22, height: 22)
                .background(Circle().fill(ZenDesign.Semantic.accent))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: SettingsViewModel.PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .fill(ZenDesign.Semantic.accentMuted)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }

            Spacer()

            StatusPill(
                title: status.title,
                isPositive: status == .allowed
            )

            if status != .allowed {
                Button("Open") {
                    action()
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }
        }
        .padding(.vertical, 13)
    }
}

private struct StatusPill: View {
    let title: String
    let isPositive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(
                    isPositive
                        ? ZenDesign.Semantic.success
                        : ZenDesign.Semantic.danger
                )
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(
            isPositive
                ? ZenDesign.Semantic.success
                : ZenDesign.Semantic.textSecondary
        )
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background {
            Capsule()
                .fill(
                    isPositive
                        ? ZenDesign.Semantic.success.opacity(0.10)
                        : ZenDesign.Semantic.surfaceRaised
                )
        }
    }
}

private struct PrivacyFact: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }
}

private struct ZenSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    configuration.isPressed
                        ? ZenDesign.Semantic.surfaceRaised
                        : ZenDesign.Component.shortcutBackground
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .strokeBorder(
                        ZenDesign.Semantic.borderStrong,
                        lineWidth: 1
                    )
                }
            }
    }
}
