import SwiftUI
import ZenVoiceCore
import ZenVoiceStorage

struct ZenVoiceSettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case history = "History"
        case shortcuts = "Shortcuts"
        case privacy = "Privacy"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview:
                return "rectangle.grid.2x2"
            case .history:
                return "clock.arrow.circlepath"
            case .shortcuts:
                return "command"
            case .privacy:
                return "hand.raised"
            }
        }
    }

    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
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
        case .history:
            HistoryScreen(viewModel: historyViewModel)
        case .shortcuts:
            ShortcutsScreen(viewModel: viewModel)
        case .privacy:
            PrivacyScreen(
                viewModel: viewModel,
                historyViewModel: historyViewModel
            )
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

private struct HistoryScreen: View {
    @ObservedObject var viewModel: HistoryViewModel
    @State private var confirmsDeleteAll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "LOCAL VAULT",
                    title: "History",
                    subtitle: "Review and copy dictations saved only on this Mac."
                )

                if !viewModel.hasMadeHistoryChoice {
                    consentCard
                } else {
                    historyControls

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if viewModel.filteredRecords.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedRecords, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1.1)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textTertiary
                                    )

                                VStack(spacing: 0) {
                                    ForEach(
                                        Array(group.records.enumerated()),
                                        id: \.element.id
                                    ) { index, record in
                                        HistoryRecordRow(
                                            record: record,
                                            copy: { viewModel.copy(record) },
                                            retry: { viewModel.retry(record) },
                                            delete: { viewModel.delete(record) }
                                        )

                                        if index < group.records.count - 1 {
                                            Divider()
                                                .overlay(
                                                    ZenDesign.Semantic.border
                                                )
                                                .padding(.leading, 54)
                                        }
                                    }
                                }
                                .background {
                                    RoundedRectangle(
                                        cornerRadius: ZenDesign.Radius.medium,
                                        style: .continuous
                                    )
                                    .fill(ZenDesign.Component.cardBackground)
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius:
                                                ZenDesign.Radius.medium,
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
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
        .background(ZenDesign.Semantic.canvas)
        .alert(
            "Delete all history?",
            isPresented: $confirmsDeleteAll
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                viewModel.deleteAll()
            }
        } message: {
            Text(
                "This removes every saved transcript and recovery recording from this Mac."
            )
        }
    }

    private var consentCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 15) {
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.accentMuted)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(ZenDesign.Semantic.accent)
                    }
                    .frame(width: 50, height: 50)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Keep a private local history?")
                            .font(
                                .system(
                                    size: 16,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text("ZenVoice can save encrypted transcripts so an interrupted paste never loses your words.")
                            .font(.system(size: 11))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ConsentFact(
                        icon: "key.fill",
                        text: "Transcript text is encrypted with a Keychain-protected key."
                    )
                    ConsentFact(
                        icon: "internaldrive",
                        text: "History stays on this Mac and is never synced."
                    )
                    ConsentFact(
                        icon: "waveform.slash",
                        text: "Successful audio is deleted after transcription."
                    )
                }

                HStack {
                    Button("Not Now") {
                        viewModel.declineHistory()
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())

                    Spacer()

                    Button("Enable Local History") {
                        viewModel.enableHistory()
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                }
            }
        }
    }

    private var historyControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                TextField("Search transcripts or apps", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
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
                    .strokeBorder(ZenDesign.Semantic.border, lineWidth: 1)
                }
            }

            StatusPill(
                title: viewModel.historyEnabled ? "Saving" : "Paused",
                isPositive: viewModel.historyEnabled
            )

            Button("Delete All") {
                confirmsDeleteAll = true
            }
            .buttonStyle(ZenSecondaryButtonStyle())
            .disabled(viewModel.records.isEmpty)
        }
    }

    private var emptyState: some View {
        ZenCard {
            VStack(spacing: 10) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 25))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                Text(
                    viewModel.historyEnabled
                        ? "Your next dictation will appear here."
                        : "History saving is paused."
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(
                    viewModel.historyEnabled
                        ? "Nothing has been saved yet."
                        : "Existing records remain local until you delete them."
                )
                .font(.system(size: 10))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    private var groupedRecords:
        [(title: String, records: [ZenVoiceStorage.DictationRecord])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: viewModel.filteredRecords) { record in
            calendar.startOfDay(for: record.startedAt)
        }
        return groups.keys.sorted(by: >).map { date in
            let title: String
            if calendar.isDateInToday(date) {
                title = "Today"
            } else if calendar.isDateInYesterday(date) {
                title = "Yesterday"
            } else {
                title = date.formatted(
                    .dateTime.weekday(.wide).month(.abbreviated).day()
                )
            }
            return (
                title: title,
                records: groups[date, default: []].sorted {
                    $0.startedAt > $1.startedAt
                }
            )
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

                        HStack(alignment: .center, spacing: 15) {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(ZenDesign.Semantic.accent)
                            }
                            .frame(width: 46, height: 46)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Paste last dictation")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text("Recovers your latest text without recording again.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }

                            Spacer()

                            ShortcutCaptureButton(
                                displayName:
                                    viewModel.pasteLastShortcut.displayName,
                                isCapturing:
                                    viewModel.isCapturingPasteLastShortcut,
                                action: {
                                    if viewModel
                                        .isCapturingPasteLastShortcut {
                                        viewModel.cancelShortcutCapture()
                                    } else {
                                        viewModel.beginShortcutCapture(
                                            for: .pasteLast
                                        )
                                    }
                                }
                            )
                        }

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        HStack(alignment: .center, spacing: 15) {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                                Image(systemName: "eye.slash.fill")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(ZenDesign.Semantic.accent)
                            }
                            .frame(width: 46, height: 46)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Toggle Private Dictation")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text("Instantly stop saving transcripts and audio.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }

                            Spacer()

                            ShortcutCaptureButton(
                                displayName:
                                    viewModel.privateModeShortcut.displayName,
                                isCapturing:
                                    viewModel.isCapturingPrivateModeShortcut,
                                action: {
                                    if viewModel
                                        .isCapturingPrivateModeShortcut {
                                        viewModel.cancelShortcutCapture()
                                    } else {
                                        viewModel.beginShortcutCapture(
                                            for: .privateMode
                                        )
                                    }
                                }
                            )
                        }

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        HStack(alignment: .center, spacing: 15) {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(ZenDesign.Semantic.accent)
                            }
                            .frame(width: 46, height: 46)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hold to dictate")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text("Recording starts while the selected modifier key is held and finishes on release.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }

                            Spacer()

                            Picker(
                                "Hold key",
                                selection: Binding(
                                    get: { viewModel.holdKey },
                                    set: viewModel.setHoldKey
                                )
                            ) {
                                ForEach(HoldKeyChoice.allCases, id: \.self) {
                                    choice in
                                    Text(choice.displayName).tag(choice)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 138)

                            Toggle(
                                "",
                                isOn: Binding(
                                    get: {
                                        viewModel.holdToDictateEnabled
                                    },
                                    set:
                                        viewModel
                                            .setHoldToDictateEnabled
                                )
                            )
                            .labelsHidden()
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
                            Button("Reset Dictation") {
                                viewModel.resetShortcut()
                            }
                            .buttonStyle(ZenSecondaryButtonStyle())

                            Button("Reset Paste") {
                                viewModel.resetPasteLastShortcut()
                            }
                            .buttonStyle(ZenSecondaryButtonStyle())

                            Button("Reset Private") {
                                viewModel.resetPrivateModeShortcut()
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

private struct ShortcutCaptureButton: View {
    let displayName: String
    let isCapturing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isCapturing {
                    Circle()
                        .fill(ZenDesign.Semantic.accent)
                        .frame(width: 7, height: 7)
                    Text("Press shortcut…")
                } else {
                    Image(systemName: "keyboard")
                    Text(displayName)
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
                isCapturing
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
                    isCapturing
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Component.shortcutBackground
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .strokeBorder(
                        isCapturing
                            ? ZenDesign.Component.focusRing
                            : ZenDesign.Semantic.borderStrong,
                        lineWidth: 1
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PrivacyScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var historyViewModel: HistoryViewModel

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
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "externaldrive.badge.checkmark")
                                .foregroundStyle(ZenDesign.Semantic.accent)
                            Text("Local history")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Spacer()
                            StatusPill(
                                title: historyViewModel.historyEnabled
                                    ? "Saving"
                                    : "Paused",
                                isPositive: historyViewModel.historyEnabled
                            )
                        }

                        PrivacyToggleRow(
                            title: "Save encrypted transcripts",
                            detail: "Save successful and partial transcripts in your encrypted local vault.",
                            isOn: Binding(
                                get: { historyViewModel.historyEnabled },
                                set: historyViewModel.setHistoryEnabled
                            )
                        )

                        PrivacyToggleRow(
                            title: "Keep failed audio for 24 hours",
                            detail: "Only when no usable transcript was produced, so you can retry.",
                            isOn: Binding(
                                get: {
                                    historyViewModel.retainsFailedAudio
                                },
                                set:
                                    historyViewModel.setRetainsFailedAudio
                            )
                        )
                        .disabled(!historyViewModel.historyEnabled)

                        PrivacyToggleRow(
                            title: "Private Dictation mode",
                            detail: "While enabled, transcripts and audio are never saved.",
                            isOn: Binding(
                                get: {
                                    historyViewModel.privateModeEnabled
                                },
                                set:
                                    historyViewModel
                                        .setPrivateModeEnabled
                            )
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
                            text: "Successful audio is deleted after transcription"
                        )
                        PrivacyFact(
                            icon: "clock.arrow.circlepath",
                            text: historyViewModel.historyEnabled
                                ? "Transcript history is encrypted on this Mac"
                                : "New transcript saving is paused"
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

private struct HistoryRecordRow: View {
    let record: ZenVoiceStorage.DictationRecord
    let copy: () -> Void
    let retry: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(iconTint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    if let appName = record.targetAppName {
                        Text(appName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                    }
                    if record.isPartial {
                        Text("Partial")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ZenDesign.Semantic.accent)
                    }
                }

                Text(transcript)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        record.status == .failed
                            ? ZenDesign.Semantic.textSecondary
                            : ZenDesign.Semantic.textPrimary
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if record.finalTranscript != nil {
                    Text(
                        "\(record.wordCount) words · "
                            + "\(Int(record.wordsPerMinute.rounded())) WPM"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 7) {
                if record.status == .failed,
                   record.recoveryAudioURL != nil {
                    Button("Retry", action: retry)
                        .buttonStyle(ZenSecondaryButtonStyle())
                }

                if record.finalTranscript != nil {
                    Button("Copy", action: copy)
                        .buttonStyle(ZenSecondaryButtonStyle())
                }

                Menu {
                    Button("Delete", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 26, height: 26)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(ZenDesign.Spacing.md)
    }

    private var transcript: String {
        if let transcript = record.finalTranscript {
            return transcript
        }
        return record.errorMessage ?? "This dictation did not finish."
    }

    private var icon: String {
        switch record.status {
        case .failed:
            return "exclamationmark.arrow.triangle.2.circlepath"
        case .inserted:
            return "checkmark"
        case .copiedOnly:
            return "doc.on.doc"
        default:
            return "waveform"
        }
    }

    private var iconTint: Color {
        record.status == .failed
            ? ZenDesign.Semantic.danger
            : ZenDesign.Semantic.accent
    }
}

private struct ConsentFact: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.success)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }
}

private struct PrivacyToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(ZenDesign.Semantic.accent)
        }
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
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

private struct ZenPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.84))
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    configuration.isPressed
                        ? ZenDesign.Primitive.gold500
                        : ZenDesign.Semantic.accent
                )
            }
    }
}
