import SwiftUI
import ZenVoiceCore
import ZenVoiceStorage

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
                    .font(.system(size: 12))
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

struct AppProfilesScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var applicationProfileViewModel:
        ApplicationProfileViewModel

    var body: some View {
        ZenScreen(
            title: "App Profiles",
            subtitle:
                "Different apps, different behavior. Overrides apply only where you set them."
        ) {
            applicationProfilesCard

            ZenBanner(
                kind: .info,
                icon: "info.circle",
                text:
                    "Profiles switch automatically the moment you start dictating — ZenVoice checks which app is frontmost, locally."
            )
        }
        .onAppear {
            applicationProfileViewModel.refresh()
        }
    }

    private var applicationProfilesCard: some View {
        ZenPanel(padding: ZenDesign.Spacing.lg) {
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
                        .font(.system(size: 12))
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
                    .font(.system(size: 12))
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
                .font(.system(size: 11))
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
                        .font(ZenDesign.Typography.monoSmall)
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
                .tint(ZenDesign.Semantic.accent)
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
}
