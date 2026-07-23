import SwiftUI
import ZenVoiceCore
import ZenVoiceStorage

struct ZenVoiceSettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case audio = "Audio"
        case models = "Models"
        case languages = "Languages"
        case refine = "Instant Refine"
        case history = "History"
        case insights = "Insights"
        case voiceProfile = "Voice Profile"
        case shortcuts = "Shortcuts"
        case privacy = "Privacy"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview:
                return "rectangle.grid.2x2"
            case .audio:
                return "mic"
            case .models:
                return "cpu"
            case .languages:
                return "globe"
            case .refine:
                return "wand.and.stars"
            case .history:
                return "clock.arrow.circlepath"
            case .insights:
                return "chart.bar.xaxis"
            case .voiceProfile:
                return "quote.bubble"
            case .shortcuts:
                return "command"
            case .privacy:
                return "hand.raised"
            }
        }
    }

    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var insightsViewModel: InsightsViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    @ObservedObject var refinementModelManagerViewModel:
        RefinementModelManagerViewModel
    @ObservedObject var applicationProfileViewModel:
        ApplicationProfileViewModel
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
        case .audio:
            AudioScreen(viewModel: viewModel)
        case .models:
            ModelsScreen(viewModel: modelManagerViewModel)
        case .languages:
            LanguagesScreen(viewModel: viewModel)
        case .refine:
            InstantRefineScreen(
                viewModel: viewModel,
                modelViewModel: refinementModelManagerViewModel,
                applicationProfileViewModel:
                    applicationProfileViewModel
            )
        case .history:
            HistoryScreen(viewModel: historyViewModel)
        case .insights:
            InsightsScreen(viewModel: insightsViewModel)
        case .voiceProfile:
            VoiceProfileScreen(viewModel: voiceProfileViewModel)
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

private struct AudioScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "MICROPHONE",
                    title: "Audio",
                    subtitle:
                        "Choose a microphone and verify its signal before dictating."
                )

                ZenCard {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Input device")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(viewModel.selectedMicrophoneName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }
                            Spacer()
                            StatusPill(
                                title:
                                    viewModel.selectedMicrophoneUID == nil
                                        ? "Follows macOS"
                                        : "Pinned",
                                isPositive: true
                            )
                        }

                        Button {
                            viewModel.selectMicrophone(nil)
                        } label: {
                            microphoneRow(
                                name: "System Default",
                                detail:
                                    "Follow the current macOS input automatically.",
                                selected:
                                    viewModel.selectedMicrophoneUID == nil,
                                badge: "RECOMMENDED"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            viewModel.audioDoctorState == .running
                        )

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        if viewModel.microphones.isEmpty {
                            Text("No connected microphones were found.")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.danger
                                )
                                .padding(.vertical, 8)
                        } else {
                            ForEach(viewModel.microphones) { microphone in
                                Button {
                                    viewModel.selectMicrophone(microphone.id)
                                } label: {
                                    microphoneRow(
                                        name: microphone.name,
                                        detail: microphoneDetail(microphone),
                                        selected:
                                            viewModel.selectedMicrophoneUID
                                                == microphone.id,
                                        badge:
                                            microphone.isDefault
                                                ? "DEFAULT"
                                                : nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(
                                    !microphone.isConnected
                                        || viewModel.audioDoctorState
                                            == .running
                                )
                            }
                        }
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 13) {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: ZenDesign.Radius.small,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                                Image(systemName: "waveform.badge.magnifyingglass")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.accent
                                    )
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Audio Doctor")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(viewModel.audioDoctorState.title)
                                    .font(.system(size: 9))
                                    .foregroundStyle(
                                        audioDoctorTint
                                    )
                            }
                            Spacer()
                            Button(
                                viewModel.audioDoctorState == .running
                                    ? "Testing…"
                                    : "Run 3-second test",
                                action: viewModel.runAudioDoctor
                            )
                            .buttonStyle(ZenPrimaryButtonStyle())
                            .disabled(
                                viewModel.audioDoctorState == .running
                            )
                        }

                        ProgressView(value: viewModel.audioDoctorLevel)
                            .progressViewStyle(.linear)
                            .tint(audioDoctorTint)
                            .accessibilityLabel("Microphone signal level")
                            .accessibilityValue(
                                "\(Int((viewModel.audioDoctorLevel * 100).rounded())) percent"
                            )

                        HStack(spacing: 16) {
                            PrivacyFact(
                                icon: "speaker.slash",
                                text:
                                    "The temporary test recording is deleted immediately."
                            )
                            PrivacyFact(
                                icon: "network.slash",
                                text: "No test audio leaves this Mac."
                            )
                        }
                    }
                }

                Text(
                    "If a pinned microphone disconnects during dictation, ZenVoice stops safely, preserves recoverable audio according to your Privacy setting, and asks you to choose another input."
                )
                .font(.system(size: 9))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
        .background(ZenDesign.Semantic.canvas)
        .onAppear {
            viewModel.refreshMicrophones()
        }
    }

    private var audioDoctorTint: Color {
        switch viewModel.audioDoctorState {
        case .passed:
            return ZenDesign.Semantic.success
        case .quiet, .failed:
            return ZenDesign.Semantic.danger
        case .idle, .running:
            return ZenDesign.Semantic.accent
        }
    }

    private func microphoneDetail(_ microphone: MicrophoneDevice) -> String {
        if !microphone.isConnected {
            return "Disconnected"
        }
        if microphone.isInUseByAnotherApplication {
            return "Connected • also in use by another app"
        }
        return microphone.isDefault
            ? "Connected • current macOS default"
            : "Connected"
    }

    private func microphoneRow(
        name: String,
        detail: String,
        selected: Bool,
        badge: String?
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    selected ? "checkmark.circle.fill" : "circle"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(
                selected
                    ? ZenDesign.Semantic.success
                    : ZenDesign.Semantic.textTertiary
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.small,
                style: .continuous
            )
            .fill(
                selected
                    ? ZenDesign.Semantic.accentMuted
                    : Color.clear
            )
        }
        .contentShape(Rectangle())
    }
}

private struct LanguagesScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""

    private var visibleLanguages: [SupportedLanguage] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else {
            return LanguageCatalog.languages
        }
        return LanguageCatalog.languages.filter {
            $0.displayName.lowercased().contains(query)
                || $0.nativeName.lowercased().contains(query)
                || $0.code.lowercased().contains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "LOCAL LANGUAGE PROFILES",
                    title: "Languages",
                    subtitle:
                        "Choose what you speak and how ZenVoice writes it. English stays explicit unless you select automatic detection."
                )

                if let error = viewModel.languageError {
                    ErrorBanner(message: error)
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("QUICK PROFILES")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                        HStack(spacing: 10) {
                            profileButton(
                                title: "English",
                                detail: "English speech → English",
                                selected:
                                    viewModel.languageProfile == .english,
                                action: viewModel.useEnglishProfile
                            )
                            profileButton(
                                title: "Hinglish",
                                detail: "Hindi + English → Latin script",
                                selected:
                                    viewModel.languageProfile == .hinglish,
                                action: viewModel.useHinglishProfile
                            )
                            profileButton(
                                title: "Auto",
                                detail: "Detect one language per dictation",
                                selected:
                                    viewModel.languageProfile
                                        .inputLanguageCode
                                        == LanguageProfile.automaticCode,
                                action: viewModel.useAutomaticProfile
                            )
                        }
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Output")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(
                                    viewModel.languageProfile.outputMode.detail
                                )
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            }
                            Spacer()
                            StatusPill(
                                title:
                                    viewModel.languageProfile.displayName,
                                isPositive: true
                            )
                        }

                        Picker(
                            "Output mode",
                            selection: Binding(
                                get: {
                                    viewModel.languageProfile.outputMode
                                },
                                set: viewModel.setOutputMode
                            )
                        ) {
                            ForEach(TranscriptionOutputMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Transcription output mode")

                        if viewModel.languageProfile.requiresMultilingualModel {
                            Label(
                                "This profile requires a Multilingual model.",
                                systemImage: "cpu"
                            )
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.accent
                            )
                        } else {
                            Label(
                                "English-only and Multilingual models are compatible.",
                                systemImage: "checkmark.shield"
                            )
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.success
                            )
                        }
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Spoken language")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(
                                    "\(LanguageCatalog.languages.count) explicit local languages"
                                )
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            }
                            Spacer()
                            TextField("Search languages", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 190)
                        }

                        Button {
                            viewModel.useAutomaticProfile()
                        } label: {
                            languageRow(
                                name: "Automatic detection",
                                nativeName:
                                    "Useful for unknown input; less reliable for short phrases",
                                badge: "AUTO",
                                selected:
                                    viewModel.languageProfile
                                        .inputLanguageCode
                                        == LanguageProfile.automaticCode
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .overlay(ZenDesign.Semantic.border)

                        LazyVStack(spacing: 4) {
                            ForEach(visibleLanguages) { language in
                                Button {
                                    viewModel.setInputLanguage(language.code)
                                } label: {
                                    languageRow(
                                        name: language.displayName,
                                        nativeName: language.nativeName,
                                        badge:
                                            language.supportLevel.displayName,
                                        selected:
                                            viewModel.languageProfile
                                                .inputLanguageCode
                                                == language.code
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Text(
                    "Language quality varies by model and language. Preview languages are available now but need broader real-microphone validation before a public release."
                )
                .font(.system(size: 9))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }
            .padding(34)
        }
    }

    private func profileButton(
        title: String,
        detail: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ZenDesign.Semantic.success)
                    }
                }
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(2)
            }
            .foregroundStyle(ZenDesign.Semantic.textPrimary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    selected
                        ? ZenDesign.Semantic.accentMuted
                        : ZenDesign.Semantic.surfaceRaised
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .strokeBorder(
                        selected
                            ? ZenDesign.Semantic.accent.opacity(0.45)
                            : ZenDesign.Semantic.border,
                        lineWidth: 1
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func languageRow(
        name: String,
        nativeName: String,
        badge: String,
        selected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    selected ? "checkmark.circle.fill" : "circle"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(
                selected
                    ? ZenDesign.Semantic.success
                    : ZenDesign.Semantic.textTertiary
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(nativeName)
                    .font(.system(size: 9))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(badge.uppercased())
                .font(.system(size: 7, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.small,
                style: .continuous
            )
            .fill(
                selected
                    ? ZenDesign.Semantic.accentMuted
                    : Color.clear
            )
        }
        .contentShape(Rectangle())
    }
}

private struct ModelsScreen: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    @State private var modelPendingRemoval: VerifiedModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "VERIFIED LOCAL MODELS",
                    title: "Models",
                    subtitle:
                        "Choose an approved Whisper model. Downloads are pinned and SHA-256 verified."
                )

                ZenCard {
                    HStack(spacing: 14) {
                        Image(systemName: "laptopcomputer.and.arrow.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(ZenDesign.Semantic.accent)
                            .frame(width: 46, height: 46)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: ZenDesign.Radius.small,
                                    style: .continuous
                                )
                                .fill(ZenDesign.Semantic.accentMuted)
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recommendation for this Mac")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text(viewModel.hardwareProfile.summary)
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            Text(
                                "\(ModelRecommendationEngine.recommendedTier(for: viewModel.hardwareProfile).displayName) is the default recommendation. Language remains your choice."
                            )
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                        }
                    }
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 11) {
                        PrivacyFact(
                            icon: "checkmark.shield.fill",
                            text:
                                "Only official whisper.cpp conversions from the pinned catalogue are offered."
                        )
                        PrivacyFact(
                            icon: "network.slash",
                            text:
                                "After download, transcription runs locally with no account or API key."
                        )
                        PrivacyFact(
                            icon: "doc.text.magnifyingglass",
                            text:
                                "Publisher, revision, license, size, and checksum are recorded for every model."
                        )
                    }
                }

                if viewModel.isVerifying {
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Verifying installed models…")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                ForEach(ModelPerformanceTier.allCases, id: \.self) { tier in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tier.displayName.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )

                        ForEach(
                            viewModel.models.filter { $0.tier == tier }
                        ) { model in
                            ModelRow(
                                model: model,
                                isInstalled: viewModel.isInstalled(model),
                                isSelected: viewModel.isSelected(model),
                                isLanguageCompatible:
                                    viewModel.isLanguageCompatible(model),
                                isDownloading:
                                    viewModel.downloadingModelID == model.id,
                                downloadProgress:
                                    viewModel.downloadProgress,
                                isVerifyingDownload:
                                    viewModel.isVerifyingDownload,
                                recommendation:
                                    viewModel.recommendation(for: model),
                                benchmark:
                                    viewModel.benchmarkSummary(for: model),
                                download: { viewModel.download(model) },
                                cancel: viewModel.cancelDownload,
                                select: { viewModel.select(model) },
                                remove: {
                                    modelPendingRemoval = model
                                }
                            )
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
            "Remove downloaded model?",
            isPresented: Binding(
                get: { modelPendingRemoval != nil },
                set: { if !$0 { modelPendingRemoval = nil } }
            ),
            presenting: modelPendingRemoval
        ) { model in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                viewModel.remove(model)
                modelPendingRemoval = nil
            }
        } message: { model in
            Text(
                "\(model.displayName) (\(model.languageCapability.displayName)) will be removed from this Mac."
            )
        }
    }
}

private struct ModelRow: View {
    let model: VerifiedModel
    let isInstalled: Bool
    let isSelected: Bool
    let isLanguageCompatible: Bool
    let isDownloading: Bool
    let downloadProgress: Double?
    let isVerifyingDownload: Bool
    let recommendation: ModelRecommendation
    let benchmark: ModelBenchmarkSummary?
    let download: () -> Void
    let cancel: () -> Void
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        ZenCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .fill(ZenDesign.Semantic.accentMuted)
                    Image(
                        systemName:
                            model.languageCapability == .multilingual
                                ? "globe"
                                : "character.book.closed"
                    )
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(model.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(model.languageCapability.displayName)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(
                                Capsule().fill(
                                    ZenDesign.Semantic.surfaceRaised
                                )
                            )
                    }
                    Text(
                        "\(model.formattedFileSize) • \(model.format) • \(model.license)"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    Text("Pinned \(model.sourceRevision.prefix(8)) • SHA-256 verified")
                        .font(.system(size: 8))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    Text(recommendation.rationale)
                        .font(.system(size: 8))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let benchmark {
                        Text(
                            "\(benchmark.sampleCount) local sample\(benchmark.sampleCount == 1 ? "" : "s") • \(benchmark.averageRealtimeFactor.formatted(.number.precision(.fractionLength(2))))× realtime"
                        )
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.accent)
                    }
                }

                Spacer()

                if isSelected {
                    StatusPill(title: "In use", isPositive: true)
                } else if !isLanguageCompatible {
                    StatusPill(
                        title: "English only",
                        isPositive: false
                    )
                } else {
                    StatusPill(
                        title: recommendation.title,
                        isPositive:
                            recommendation.level == .recommended
                                || recommendation.level == .supported
                    )
                }

                if isDownloading {
                    VStack(alignment: .trailing, spacing: 5) {
                        ProgressView(value: downloadProgress ?? 0)
                            .progressViewStyle(.linear)
                            .frame(width: 88)
                        Text(
                            isVerifyingDownload
                                ? "Verifying…"
                                : "\(Int(((downloadProgress ?? 0) * 100).rounded()))%"
                        )
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                    }
                    Button("Cancel", action: cancel)
                        .buttonStyle(ZenSecondaryButtonStyle())
                } else if isInstalled {
                    if !isSelected {
                        Button("Use", action: select)
                            .buttonStyle(ZenPrimaryButtonStyle())
                            .disabled(!isLanguageCompatible)
                    }
                    Button("Remove", action: remove)
                        .buttonStyle(ZenSecondaryButtonStyle())
                } else {
                    Button("Download", action: download)
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .disabled(
                            recommendation.level == .insufficientStorage
                        )
                }
            }
        }
    }
}

private struct InstantRefineScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var modelViewModel:
        RefinementModelManagerViewModel
    @ObservedObject var applicationProfileViewModel:
        ApplicationProfileViewModel
    @State private var modelPendingRemoval:
        VerifiedRefinementModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "LOCAL TEXT REFINEMENT",
                    title: "Instant Refine",
                    subtitle:
                        "Clean the local Whisper transcript before ZenVoice pastes it."
                )

                ZenCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.accent
                                )
                                .frame(width: 46, height: 46)
                                .background {
                                    RoundedRectangle(
                                        cornerRadius:
                                            ZenDesign.Radius.small,
                                        style: .continuous
                                    )
                                    .fill(
                                        ZenDesign.Semantic.accentMuted
                                    )
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Built-in refinement engine")
                                    .font(
                                        .system(
                                            size: 13,
                                            weight: .bold
                                        )
                                    )
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(
                                    "Runs on this Mac after transcription and before paste. No account, API key, or network request."
                                )
                                .font(.system(size: 10))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                            }
                        }

                        Picker(
                            "Refinement mode",
                            selection: Binding(
                                get: { viewModel.instantRefineMode },
                                set: {
                                    viewModel.setInstantRefineMode($0)
                                }
                            )
                        ) {
                            ForEach(
                                InstantRefineMode.allCases,
                                id: \.self
                            ) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Instant Refine mode")

                        Text(viewModel.instantRefineMode.detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                    }
                }

                nextDictationContextCard
                applicationProfilesCard

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("VERIFIED LOCAL MODELS")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                        Spacer()
                        Text(modelViewModel.hardwareProfile.summary)
                            .font(.system(size: 8))
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                    }

                    if modelViewModel.isVerifying {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Verifying refinement models…")
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                        }
                    }

                    if let error = modelViewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if viewModel.instantRefineMode == .localModel,
                       !modelViewModel.hasSelectedInstalledModel {
                        ErrorBanner(
                            message:
                                "No verified refinement model is selected. ZenVoice will safely fall back to Clean."
                        )
                    }

                    ForEach(modelViewModel.models) { model in
                        RefinementModelRow(
                            model: model,
                            isInstalled:
                                modelViewModel.isInstalled(model),
                            isSelected:
                                modelViewModel.isSelected(model),
                            isDownloading:
                                modelViewModel.downloadingModelID
                                    == model.id,
                            downloadProgress:
                                modelViewModel.downloadProgress,
                            isVerifyingDownload:
                                modelViewModel.isVerifyingDownload,
                            recommendation:
                                modelViewModel.recommendation(
                                    for: model
                                ),
                            download: {
                                modelViewModel.download(model)
                            },
                            cancel:
                                modelViewModel.cancelDownload,
                            select: {
                                modelViewModel.select(model)
                            },
                            remove: {
                                modelPendingRemoval = model
                            }
                        )
                    }
                }

                HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
                    exampleCard
                    safetyCard
                }

                ZenCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Live dictation",
                            systemImage: "captions.bubble"
                        )
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textPrimary
                        )
                        PrivacyToggleRow(
                            title: "Show stable phrase preview",
                            detail:
                                "Transcribe locally after a natural pause and show the stable phrase in ZenBar.",
                            isOn: Binding(
                                get: {
                                    viewModel.livePreviewEnabled
                                },
                                set:
                                    viewModel.setLivePreviewEnabled
                            )
                        )

                        PrivacyToggleRow(
                            title: "Paste stable phrases on pause",
                            detail:
                                "Experimental. Paste only when the original target app is still active; final stop remains the recovery boundary.",
                            isOn: Binding(
                                get: {
                                    viewModel.commitOnPauseEnabled
                                },
                                set:
                                    viewModel.setCommitOnPauseEnabled
                            )
                        )
                        .disabled(!viewModel.livePreviewEnabled)
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
        .background(ZenDesign.Semantic.canvas)
        .alert(
            "Remove refinement model?",
            isPresented: Binding(
                get: { modelPendingRemoval != nil },
                set: { if !$0 { modelPendingRemoval = nil } }
            ),
            presenting: modelPendingRemoval
        ) { model in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                modelViewModel.remove(model)
                modelPendingRemoval = nil
            }
        } message: { model in
            Text(
                "\(model.displayName) will be removed from this Mac. Clean refinement remains available."
            )
        }
    }

    private var nextDictationContextCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next dictation context")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(
                            "Add names, product terms, or the topic for one recording. It stays in memory and clears when recording starts."
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(
                            ZenDesign.Semantic.textSecondary
                        )
                    }
                    Spacer()
                    Text(
                        "\(viewModel.sanitizedNextDictationContext.count)/\(NextDictationContext.maximumCharacterCount)"
                    )
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                }

                TextEditor(text: $viewModel.nextDictationContext)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        ZenDesign.Semantic.textPrimary
                    )
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 64, maxHeight: 82)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(ZenDesign.Component.shortcutBackground)
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
                    .onChange(
                        of: viewModel.nextDictationContext
                    ) { _, value in
                        let sanitized =
                            NextDictationContext.sanitized(value)
                        if sanitized.count
                            >= NextDictationContext
                                .maximumCharacterCount {
                            viewModel.nextDictationContext = sanitized
                        }
                    }
                    .accessibilityLabel(
                        "Context for the next dictation"
                    )

                HStack {
                    Label(
                        "Never written to history or settings",
                        systemImage: "memorychip"
                    )
                    .font(.system(size: 8))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                    Spacer()
                    Button(
                        "Clear",
                        action: viewModel.clearNextDictationContext
                    )
                    .buttonStyle(ZenSecondaryButtonStyle())
                    .disabled(
                        viewModel.nextDictationContext.isEmpty
                    )
                }
            }
        }
    }

    private var applicationProfilesCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Application profiles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(
                            "Automatically choose language, refinement, and local voice commands for a target app."
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(
                            ZenDesign.Semantic.textSecondary
                        )
                    }
                    Spacer()
                    Button {
                        applicationProfileViewModel.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                    .accessibilityLabel("Refresh running applications")
                }

                if let error =
                    applicationProfileViewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                PrivacyToggleRow(
                    title: "Enable local voice commands by default",
                    detail:
                        "Interpret spoken layout and punctuation commands locally. Each application profile can override this.",
                    isOn: Binding(
                        get: {
                            viewModel.voiceCommandsEnabled
                        },
                        set:
                            viewModel.setVoiceCommandsEnabled
                    )
                )

                HStack(spacing: 9) {
                    Picker(
                        "Running app",
                        selection:
                            $applicationProfileViewModel
                                .selectedApplicationID
                    ) {
                        if applicationProfileViewModel
                            .runningApplications.isEmpty {
                            Text("No running apps")
                                .tag(String?.none)
                        }
                        ForEach(
                            applicationProfileViewModel
                                .runningApplications
                        ) { application in
                            Text(application.name)
                                .tag(Optional(application.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button("Add profile") {
                        applicationProfileViewModel
                            .addSelectedApplication(
                                languageProfile:
                                    viewModel.languageProfile,
                                refinementMode:
                                    viewModel.instantRefineMode
                            )
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(
                        applicationProfileViewModel
                            .selectedApplicationID == nil
                    )
                }

                if applicationProfileViewModel.profiles.isEmpty {
                    Text(
                        "No profiles yet. Open a target app, refresh this list, then add it."
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                } else {
                    ForEach(
                        applicationProfileViewModel.profiles
                    ) { profile in
                        Divider()
                            .overlay(ZenDesign.Semantic.border)
                        applicationProfileRow(profile)
                    }
                }

                Text(
                    "Voice commands: new line, new paragraph, comma, full stop, question mark, and exclamation mark. English commands work with every profile; Hindi, Spanish, French, Mandarin, and Arabic aliases are included."
                )
                .font(.system(size: 8))
                .foregroundStyle(
                    ZenDesign.Semantic.textTertiary
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func applicationProfileRow(
        _ profile: ApplicationProfile
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.applicationName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textPrimary
                        )
                    Text(profile.bundleIdentifier)
                        .font(.system(size: 8))
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                }
                Spacer()
                Button("Remove") {
                    applicationProfileViewModel.remove(profile)
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }

            HStack(spacing: 10) {
                Picker(
                    "Language",
                    selection: Binding(
                        get: { profile.languageProfile },
                        set: {
                            applicationProfileViewModel
                                .setLanguage($0, for: profile)
                        }
                    )
                ) {
                    ForEach(
                        applicationProfileLanguageOptions,
                        id: \.id
                    ) { languageProfile in
                        Text(languageProfile.displayName)
                            .tag(languageProfile)
                    }
                }
                .frame(maxWidth: .infinity)

                Picker(
                    "Refinement",
                    selection: Binding(
                        get: { profile.refinementMode },
                        set: {
                            applicationProfileViewModel
                                .setRefinementMode(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                ) {
                    ForEach(
                        InstantRefineMode.allCases,
                        id: \.self
                    ) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .frame(maxWidth: .infinity)

                Toggle(
                    "Voice commands",
                    isOn: Binding(
                        get: {
                            profile.voiceCommandsEnabled
                        },
                        set: {
                            applicationProfileViewModel
                                .setVoiceCommandsEnabled(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var applicationProfileLanguageOptions:
        [LanguageProfile] {
        [
            .hinglish,
            LanguageProfile(
                inputLanguageCode: LanguageProfile.automaticCode,
                outputMode: .spokenLanguage
            )
        ] + LanguageCatalog.languages.map {
            LanguageProfile(
                inputLanguageCode: $0.code,
                outputMode: .spokenLanguage
            )
        }
    }

    private var exampleCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("EXAMPLE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                Text("“Um, create the the local app with Swift.”")
                    .font(.system(size: 10))
                    .foregroundStyle(
                        ZenDesign.Semantic.textSecondary
                    )
                Text("Create the local app with Swift.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        ZenDesign.Semantic.textPrimary
                    )
            }
        }
    }

    private var safetyCard: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("MEANING GUARD")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                PrivacyFact(
                    icon: "checkmark.shield.fill",
                    text:
                        "Rejects a refinement that removes too much of the original transcript."
                )
                PrivacyFact(
                    icon: "text.badge.checkmark",
                    text:
                        "Every accepted result is blocked from inventing new semantic words."
                )
            }
        }
    }
}

private struct RefinementModelRow: View {
    let model: VerifiedRefinementModel
    let isInstalled: Bool
    let isSelected: Bool
    let isDownloading: Bool
    let downloadProgress: Double?
    let isVerifyingDownload: Bool
    let recommendation: ModelRecommendation
    let download: () -> Void
    let cancel: () -> Void
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        ZenCard {
            HStack(spacing: 13) {
                Image(systemName: "text.badge.sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                    .frame(width: 42, height: 42)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.accentMuted)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(model.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(model.tier.displayName.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textTertiary
                            )
                    }
                    Text(
                        "\(model.formattedFileSize) • \(model.format) • \(model.license)"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(
                        ZenDesign.Semantic.textSecondary
                    )
                    Link(
                        "Publisher license",
                        destination: model.licenseDocumentURL
                    )
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                    Text(
                        "\(model.languageSummary) Pinned \(model.sourceRevision.prefix(8)) • SHA-256 verified."
                    )
                    .font(.system(size: 8))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    Text(recommendation.rationale)
                        .font(.system(size: 8))
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                }

                Spacer()

                StatusPill(
                    title:
                        isSelected
                            ? "In use"
                            : recommendation.title,
                    isPositive:
                        isSelected
                            || recommendation.level == .recommended
                            || recommendation.level == .supported
                )

                if isDownloading {
                    VStack(alignment: .trailing, spacing: 5) {
                        ProgressView(value: downloadProgress ?? 0)
                            .progressViewStyle(.linear)
                            .frame(width: 82)
                        Text(
                            isVerifyingDownload
                                ? "Verifying…"
                                : "\(Int(((downloadProgress ?? 0) * 100).rounded()))%"
                        )
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textTertiary
                        )
                    }
                    Button("Cancel", action: cancel)
                        .buttonStyle(ZenSecondaryButtonStyle())
                } else if isInstalled {
                    if !isSelected {
                        Button("Use", action: select)
                            .buttonStyle(ZenPrimaryButtonStyle())
                    }
                    Button("Remove", action: remove)
                        .buttonStyle(ZenSecondaryButtonStyle())
                } else {
                    Button("Download", action: download)
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .disabled(
                            recommendation.level
                                == .insufficientStorage
                        )
                }
            }
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
                        value: appState.languageProfile.displayName,
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
                                            setCategory: {
                                                viewModel.setCategory(
                                                    $0,
                                                    for: record
                                                )
                                            },
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
            Picker("History view", selection: $viewModel.scope) {
                Text("All").tag(HistoryViewModel.Scope.all)
                Text("Recovery \(viewModel.recoveryCount)")
                    .tag(HistoryViewModel.Scope.recovery)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 170)
            .accessibilityLabel("History view")

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
                    viewModel.scope == .recovery
                        ? "Recovery Inbox is clear."
                        : viewModel.historyEnabled
                            ? "Your next dictation will appear here."
                            : "History saving is paused."
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(
                    viewModel.scope == .recovery
                        ? "Failed and usable partial dictations appear here with Copy, Retry, and Delete actions."
                        : viewModel.historyEnabled
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

private struct InsightsScreen: View {
    @ObservedObject var viewModel: InsightsViewModel
    @State private var showsShareCard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                HStack(alignment: .bottom) {
                    PageHeader(
                        eyebrow: "PRIVATE ANALYTICS",
                        title: "Insights",
                        subtitle:
                            "Understand your dictation habits from encrypted history on this Mac."
                    )
                    Spacer()
                    Button {
                        showsShareCard = true
                    } label: {
                        Label("Share Highlights", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(viewModel.snapshot.dictationCount == 0)
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                if viewModel.snapshot.dictationCount == 0 {
                    emptyState
                } else {
                    metrics
                    activity
                    HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
                        categoryBreakdown
                        topApplications
                    }
                    privacyNote
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
        .background(ZenDesign.Semantic.canvas)
        .onAppear(perform: viewModel.refresh)
        .sheet(isPresented: $showsShareCard) {
            ShareHighlightSheet(summary: shareSummary)
        }
    }

    private var metrics: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            StatusCard(
                icon: "text.word.spacing",
                title: "Total words",
                value: viewModel.snapshot.totalWordCount.formatted(),
                tint: ZenDesign.Semantic.accent
            )
            StatusCard(
                icon: "speedometer",
                title: "Average speed",
                value:
                    "\(Int(viewModel.snapshot.weightedWordsPerMinute.rounded())) WPM",
                tint: Color(red: 0.48, green: 0.68, blue: 1.0)
            )
            StatusCard(
                icon: "flame.fill",
                title: "Current streak",
                value:
                    "\(viewModel.snapshot.currentStreakDays) day"
                    + (viewModel.snapshot.currentStreakDays == 1 ? "" : "s"),
                tint: Color(red: 0.95, green: 0.55, blue: 0.34)
            )
            StatusCard(
                icon: "square.stack.3d.up.fill",
                title: "Apps used",
                value: viewModel.snapshot.distinctApplicationCount.formatted(),
                tint: ZenDesign.Semantic.success
            )
        }
    }

    private var activity: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last 7 days")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text(
                            "\(viewModel.snapshot.dictationCount) dictations · "
                                + "\(viewModel.snapshot.longestStreakDays)-day best streak"
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }
                    Spacer()
                    Text("Local calendar")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(viewModel.snapshot.recentActivity) { day in
                        VStack(spacing: 7) {
                            Text(day.wordCount.formatted())
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            RoundedRectangle(
                                cornerRadius: 4,
                                style: .continuous
                            )
                            .fill(
                                day.wordCount > 0
                                    ? ZenDesign.Semantic.accent
                                    : ZenDesign.Semantic.surfaceRaised
                            )
                            .frame(
                                height: activityHeight(for: day.wordCount)
                            )
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 94, alignment: .bottom)
            }
        }
    }

    private var categoryBreakdown: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Work by category")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                ForEach(viewModel.snapshot.categories) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Image(systemName: insight.category.icon)
                                .foregroundStyle(ZenDesign.Semantic.accent)
                                .frame(width: 14)
                            Text(insight.category.displayName)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            Spacer()
                            Text("\(insight.wordCount) words")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                        }
                        ProgressView(
                            value: Double(insight.wordCount),
                            total: Double(maxCategoryWords)
                        )
                        .tint(ZenDesign.Semantic.accent)
                    }
                }
            }
        }
    }

    private var topApplications: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Most-used apps")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                if viewModel.snapshot.topApplications.isEmpty {
                    Text("No application context has been saved yet.")
                        .font(.system(size: 9))
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                } else {
                    ForEach(
                        Array(
                            viewModel.snapshot.topApplications.enumerated()
                        ),
                        id: \.element.id
                    ) { index, app in
                        HStack(spacing: 9) {
                            Text("\(index + 1)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                    .lineLimit(1)
                                Text(
                                    "\(app.dictationCount) dictations · "
                                        + "\(app.wordCount) words"
                                )
                                .font(.system(size: 8))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(ZenDesign.Semantic.success)
            Text(
                "Insights are calculated locally. ZenVoice stores app identity, not window titles, URLs, recipients, or surrounding text."
            )
            .font(.system(size: 9))
            .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }

    private var emptyState: some View {
        ZenCard {
            VStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 26))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                Text("Your local insights will appear here.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(
                    "Save a completed dictation to begin tracking words, speed, streaks, apps, and categories."
                )
                .font(.system(size: 10))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var maxCategoryWords: Int {
        max(1, viewModel.snapshot.categories.map(\.wordCount).max() ?? 1)
    }

    private var shareSummary: ShareCardSummary {
        ShareCardSummary(
            totalWordCount: viewModel.snapshot.totalWordCount,
            weightedWordsPerMinute:
                Int(viewModel.snapshot.weightedWordsPerMinute.rounded()),
            currentStreakDays: viewModel.snapshot.currentStreakDays,
            distinctApplicationCount:
                viewModel.snapshot.distinctApplicationCount
        )
    }

    private func activityHeight(for wordCount: Int) -> CGFloat {
        let maximum = max(
            1,
            viewModel.snapshot.recentActivity.map(\.wordCount).max() ?? 1
        )
        guard wordCount > 0 else {
            return 5
        }
        return 12 + 50 * CGFloat(wordCount) / CGFloat(maximum)
    }
}

private struct VoiceProfileScreen: View {
    @ObservedObject var viewModel: VoiceProfileViewModel
    @State private var heardPhrase = ""
    @State private var replacementPhrase = ""
    @State private var confirmsDeleteAllRules = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.lg) {
                PageHeader(
                    eyebrow: "LOCAL LANGUAGE PROFILE",
                    title: "Voice Profile",
                    subtitle:
                        "Teach ZenVoice your words and review language patterns from recent local history."
                )

                profileSummary

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                learningControls
                corrections
                correctionReview

                HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
                    topWords
                    catchPhrases
                }

                HStack(spacing: 9) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundStyle(ZenDesign.Semantic.success)
                    Text(
                        "This is a language-usage profile, not a biometric voiceprint. ZenVoice does not identify or authenticate people."
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
        .background(ZenDesign.Semantic.canvas)
        .onAppear(perform: viewModel.refresh)
        .alert(
            "Delete all correction rules?",
            isPresented: $confirmsDeleteAllRules
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Rules", role: .destructive) {
                viewModel.deleteAllRules()
            }
        } message: {
            Text(
                "This permanently removes every encrypted personal replacement rule. Transcript history is not deleted."
            )
        }
    }

    private var profileSummary: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            StatusCard(
                icon: "waveform",
                title: "Analyzed",
                value:
                    "\(viewModel.snapshot.analyzedDictationCount) dictations",
                tint: ZenDesign.Semantic.accent
            )
            StatusCard(
                icon: "clock",
                title: "Most active",
                value: activeHourLabel,
                tint: Color(red: 0.48, green: 0.68, blue: 1.0)
            )
            StatusCard(
                icon: "text.badge.checkmark",
                title: "Corrections",
                value:
                    "\(viewModel.snapshot.correctionRules.count) rules",
                tint: ZenDesign.Semantic.success
            )
        }
    }

    private var corrections: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal corrections")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        "Explicit whole-word replacements are encrypted and applied locally."
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }

                HStack(spacing: 10) {
                    correctionField(
                        title: "WHEN ZENVOICE HEARS",
                        placeholder: "zen pens",
                        text: $heardPhrase
                    )
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    correctionField(
                        title: "REPLACE WITH",
                        placeholder: "ZenPense",
                        text: $replacementPhrase
                    )
                    Button("Add Rule") {
                        if viewModel.addRule(
                            source: heardPhrase,
                            replacement: replacementPhrase
                        ) {
                            heardPhrase = ""
                            replacementPhrase = ""
                        }
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(
                        heardPhrase.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            || replacementPhrase.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }

                if viewModel.snapshot.correctionRules.isEmpty {
                    Text(
                        "No personal corrections yet. Add only terms you want ZenVoice to replace automatically."
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(
                                viewModel.snapshot.correctionRules.enumerated()
                            ),
                            id: \.element.id
                        ) { index, rule in
                            HStack(spacing: 10) {
                                Text(rule.source)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textTertiary
                                    )
                                Text(rule.replacement)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Spacer()
                                Text(
                                    "Used \(rule.usageCount) time"
                                        + (rule.usageCount == 1 ? "" : "s")
                                )
                                .font(.system(size: 8))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                                Button {
                                    viewModel.deleteRule(rule)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(ZenDesign.Semantic.danger)
                            }
                            .padding(.vertical, 9)
                            if index
                                < viewModel.snapshot.correctionRules.count - 1 {
                                Divider().overlay(
                                    ZenDesign.Semantic.border
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var learningControls: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local learning controls")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textPrimary
                        )
                    Text(
                        "ZenVoice never learns silently. These controls affect only saved history and rules you explicitly created."
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(
                        ZenDesign.Semantic.textSecondary
                    )
                }

                PrivacyToggleRow(
                    title: "Apply personal correction rules",
                    detail:
                        "Pause every encrypted replacement rule without deleting it.",
                    isOn: Binding(
                        get: {
                            viewModel.appliesCorrectionRules
                        },
                        set:
                            viewModel.setAppliesCorrectionRules
                    )
                )

                PrivacyToggleRow(
                    title: "Analyze saved history for patterns",
                    detail:
                        "Show frequent words, recurring phrases, and your most active hour. No new copy is stored.",
                    isOn: Binding(
                        get: { viewModel.analyzesHistory },
                        set: viewModel.setAnalyzesHistory
                    )
                )

                HStack {
                    Label(
                        "No background microphone listening or biometric voiceprint",
                        systemImage: "hand.raised.fill"
                    )
                    .font(.system(size: 8))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                    Spacer()
                    Button("Delete All Rules") {
                        confirmsDeleteAllRules = true
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                    .disabled(
                        viewModel.snapshot.correctionRules.isEmpty
                    )
                }
            }
        }
    }

    private var correctionReview: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Correction Review")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            ZenDesign.Semantic.textPrimary
                        )
                    Text(
                        "Compare what Whisper heard with the final saved text. This view reads encrypted History locally and creates no training data."
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(
                        ZenDesign.Semantic.textSecondary
                    )
                }

                if viewModel.correctionReviewRecords.isEmpty {
                    Text(
                        "No corrected dictations are available to review."
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(
                        ZenDesign.Semantic.textTertiary
                    )
                } else {
                    ForEach(
                        viewModel.correctionReviewRecords
                    ) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(
                                    record.startedAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                )
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                                if let appName =
                                    record.targetAppName {
                                    Text(appName)
                                        .font(.system(size: 8))
                                        .foregroundStyle(
                                            ZenDesign.Semantic
                                                .textTertiary
                                        )
                                }
                                Spacer()
                                StatusPill(
                                    title:
                                        "\(record.correctionCount) change"
                                        + (record.correctionCount == 1
                                            ? ""
                                            : "s"),
                                    isPositive: true
                                )
                            }

                            correctionReviewLine(
                                label: "HEARD",
                                text: record.rawTranscript,
                                copy: {
                                    viewModel.copy(
                                        record.rawTranscript
                                    )
                                }
                            )
                            correctionReviewLine(
                                label: "SAVED",
                                text: record.finalTranscript,
                                copy: {
                                    viewModel.copy(
                                        record.finalTranscript
                                    )
                                }
                            )
                        }
                        .padding(10)
                        .background {
                            RoundedRectangle(
                                cornerRadius:
                                    ZenDesign.Radius.small,
                                style: .continuous
                            )
                            .fill(
                                ZenDesign.Semantic.surfaceRaised
                            )
                        }
                    }
                }
            }
        }
    }

    private func correctionReviewLine(
        label: String,
        text: String?,
        copy: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(
                    ZenDesign.Semantic.textTertiary
                )
                .frame(width: 40, alignment: .leading)
            Text(text ?? "Unavailable")
                .font(.system(size: 9))
                .foregroundStyle(
                    ZenDesign.Semantic.textSecondary
                )
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Copy", action: copy)
                .buttonStyle(ZenSecondaryButtonStyle())
                .disabled(text == nil)
        }
    }

    private var topWords: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("Most-used words")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                if viewModel.snapshot.topWords.isEmpty {
                    emptyProfileText
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 70),
                                spacing: 8
                            )
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(viewModel.snapshot.topWords) { item in
                            HStack(spacing: 6) {
                                Text(item.text)
                                    .lineLimit(1)
                                Text("\(item.count)")
                                    .foregroundStyle(
                                        ZenDesign.Semantic.accent
                                    )
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background {
                                Capsule().fill(
                                    ZenDesign.Semantic.surfaceRaised
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var catchPhrases: some View {
        ZenCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("Recurring phrases")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                if viewModel.snapshot.catchPhrases.isEmpty {
                    emptyProfileText
                } else {
                    ForEach(viewModel.snapshot.catchPhrases) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "quote.opening")
                                .foregroundStyle(
                                    ZenDesign.Semantic.accent
                                )
                            Text(item.text)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                                .lineLimit(1)
                            Spacer()
                            Text("×\(item.count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                        }
                    }
                }
            }
        }
    }

    private var emptyProfileText: some View {
        Text(
            viewModel.analyzesHistory
                ? "More saved dictations are needed."
                : "Pattern analysis is paused."
        )
            .font(.system(size: 9))
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
    }

    private var activeHourLabel: String {
        guard let hour = viewModel.snapshot.mostActiveHour,
              let date = Calendar.current.date(
                from: DateComponents(hour: hour)
              ) else {
            return "Not enough data"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func correctionField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 34)
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
                        .strokeBorder(
                            ZenDesign.Semantic.border,
                            lineWidth: 1
                        )
                    }
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
    let setCategory: (DictationCategory) -> Void
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
                    Text(record.category.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.accent)
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
                    Menu("Category") {
                        ForEach(DictationCategory.allCases) { category in
                            Button {
                                setCategory(category)
                            } label: {
                                if record.category == category {
                                    Label(
                                        category.displayName,
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(category.displayName)
                                }
                            }
                        }
                    }
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

private extension DictationCategory {
    var icon: String {
        switch self {
        case .documents: "doc.text"
        case .email: "envelope"
        case .workMessages: "person.2"
        case .personalMessages: "message"
        case .aiPrompts: "sparkles"
        case .notes: "note.text"
        case .development: "chevron.left.forwardslash.chevron.right"
        case .other: "square.grid.2x2"
        }
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

struct ZenSecondaryButtonStyle: ButtonStyle {
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

struct ZenPrimaryButtonStyle: ButtonStyle {
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
