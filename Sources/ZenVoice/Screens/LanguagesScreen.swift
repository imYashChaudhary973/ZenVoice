import SwiftUI
import ZenVoiceCore
import ZenVoiceStorage

struct LanguagesScreen: View {
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

    private var isAutomatic: Bool {
        viewModel.languageProfile.inputLanguageCode
            == LanguageProfile.automaticCode
    }

    var body: some View {
        ZenScreen(
            title: "Languages",
            subtitle: "What you speak, and how it should be written."
        ) {
            if let error = viewModel.languageError {
                ZenBanner(
                    kind: .danger,
                    icon: "exclamationmark.triangle",
                    text: error
                )
            }

            profileSection
            outputSection
            allLanguagesSection

            if viewModel.languageProfile.requiresMultilingualModel {
                ZenBanner(
                    kind: .warn,
                    icon: "cpu",
                    text:
                        "This profile requires the Multilingual model — download it in Models. Language quality varies by model and language."
                )
            } else {
                ZenBanner(
                    kind: .info,
                    icon: "checkmark.shield",
                    text:
                        "English-only and Multilingual models are both compatible with this profile. Language quality varies by model and language."
                )
            }
        }
    }

    // MARK: quick profiles

    private var profileSection: some View {
        ZenSection(title: "English · Multilingual · Auto-Detect") {
            HStack(spacing: ZenDesign.Spacing.xs) {
                ZenChoiceCard(
                    title: "English",
                    detail: "English-safe: never outputs another language",
                    selected: viewModel.languageProfile == .english,
                    action: viewModel.useEnglishProfile
                )
                ZenChoiceCard(
                    title: "Hinglish",
                    badge: "Multilingual",
                    detail: "Hindi–English the way you actually speak it",
                    selected: viewModel.languageProfile == .hinglish,
                    action: viewModel.useHinglishProfile
                )
                ZenChoiceCard(
                    title: "Auto-Detect",
                    badge: "Multilingual model",
                    detail: "Detects the spoken language per dictation",
                    selected: isAutomatic,
                    action: viewModel.useAutomaticProfile
                )
            }
        }
    }

    // MARK: output mode

    private var outputSection: some View {
        ZenSection(
            title: "Output mode",
            caption: viewModel.languageProfile.displayName
        ) {
            HStack(spacing: ZenDesign.Spacing.xs) {
                ForEach(TranscriptionOutputMode.allCases) { mode in
                    ZenChoiceCard(
                        title: mode.displayName,
                        detail: mode.detail,
                        selected:
                            viewModel.languageProfile.outputMode == mode,
                        action: {
                            viewModel.setOutputMode(mode)
                        }
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Transcription output mode")
        }
    }

    // MARK: all languages

    private var allLanguagesSection: some View {
        ZenSection(
            title: "All languages",
            caption: "\(LanguageCatalog.languages.count) supported"
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                ZenSearchField(
                    placeholder: "Search languages…",
                    text: $searchText
                )

                ZenPanel {
                    Button {
                        viewModel.useAutomaticProfile()
                    } label: {
                        ZenRow(
                            icon: "wand.and.rays",
                            title: "Automatic detection",
                            subtitle:
                                "Useful for unknown input; less reliable for short phrases"
                        ) {
                            if isAutomatic {
                                ZenBadge(
                                    text: "Selected", kind: .accent,
                                    systemImage: "checkmark"
                                )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        isAutomatic ? .isSelected : []
                    )

                    if visibleLanguages.isEmpty {
                        ZenPanelDivider()
                        VStack(spacing: 4) {
                            Text("No language matches “\(searchText)”")
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textPrimary
                                )
                            Text("Search covers English names, native names, and codes.")
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ZenDesign.Spacing.lg)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleLanguages) { language in
                                ZenPanelDivider()
                                languageButton(language)
                            }
                        }
                    }
                }
            }
        }
    }

    private func languageButton(
        _ language: SupportedLanguage
    ) -> some View {
        let selected = viewModel.languageProfile.inputLanguageCode
            == language.code
        return Button {
            viewModel.setInputLanguage(language.code)
        } label: {
            HStack(spacing: ZenDesign.Spacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.displayName)
                        .font(
                            selected
                                ? ZenDesign.Typography.bodyStrong
                                : ZenDesign.Typography.body
                        )
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(language.nativeName)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(language.code)
                    .font(ZenDesign.Typography.monoSmall)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                ZenBadge(
                    text: language.supportLevel.displayName,
                    kind: .neutral
                )
                Image(
                    systemName: selected
                        ? "checkmark.circle.fill" : "circle"
                )
                .font(.system(size: 13))
                .foregroundStyle(
                    selected
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Semantic.borderStrong
                )
            }
            .padding(.horizontal, ZenDesign.Spacing.md)
            .frame(minHeight: 44)
            .background(
                selected
                    ? ZenDesign.Semantic.accentMuted
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
