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

                PrivacyToggleRow(
                    title: "Enable Command Mode",
                    detail:
                        "Let spoken phrases run app launches, Shortcuts, and system actions. Built-in actions run without approval; scripts and URLs require explicit approval.",
                    isOn: Binding(
                        get: { viewModel.commandModeEnabled },
                        set: viewModel.setCommandModeEnabled
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

            HStack(spacing: 10) {
                Picker(
                    "Engine",
                    selection: Binding(
                        get: {
                            profile.preferredEngineID
                        },
                        set: {
                            applicationProfileViewModel
                                .setPreferredEngineID(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                ) {
                    ForEach(engineOptions, id: \.id) { option in
                        Text(option.name)
                            .tag(option.id as String?)
                    }
                }
                .frame(maxWidth: .infinity)

                Picker(
                    "Output mode",
                    selection: Binding(
                        get: {
                            profile.preferredOutputMode
                        },
                        set: {
                            applicationProfileViewModel
                                .setPreferredOutputMode(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                ) {
                    ForEach(outputModeOptions, id: \.id) { option in
                        Text(option.name)
                            .tag(option.id)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                Picker(
                    "ZenIntelligence",
                    selection: Binding(
                        get: { profile.zenIntelligenceMode },
                        set: {
                            applicationProfileViewModel
                                .setZenIntelligenceMode(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                ) {
                    ForEach(
                        zenIntelligenceModeOptions,
                        id: \.id
                    ) { option in
                        Text(option.name)
                            .tag(option.id as ZenIntelligenceMode?)
                    }
                }
                .frame(maxWidth: .infinity)

                Picker(
                    "Command set",
                    selection: Binding(
                        get: { profile.commandSetID },
                        set: {
                            applicationProfileViewModel
                                .setCommandSetID(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                ) {
                    ForEach(commandSetOptions, id: \.id) { option in
                        Text(option.name)
                            .tag(option.id as String?)
                    }
                }
                .frame(maxWidth: .infinity)

                Picker(
                    "Write mode",
                    selection: Binding(
                        get: { profile.writeModeDefault },
                        set: {
                            applicationProfileViewModel
                                .setWriteModeDefault(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                ) {
                    ForEach(writeModeOptions, id: \.id) { option in
                        Text(option.name)
                            .tag(option.id as WriteModeSubMode?)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                TextField(
                    "Custom prompt hints (comma separated)",
                    text: Binding(
                        get: {
                            profile.customPromptHints.joined(
                                separator: ", "
                            )
                        },
                        set: { value in
                            let hints = value
                                .split(separator: ",")
                                .map {
                                    $0.trimmingCharacters(
                                        in: .whitespaces
                                    )
                                }
                                .filter { !$0.isEmpty }
                            applicationProfileViewModel
                                .setCustomPromptHints(
                                    hints,
                                    for: profile
                                )
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            }
        }
    }

    private var engineOptions: [(id: String?, name: String)] {
        [
            (nil, "Use global engine preference"),
            (EngineIdentifiers.whisper, "Whisper (local)"),
            (EngineIdentifiers.appleSpeech, "Apple Speech (on-device)"),
        ]
    }

    private var outputModeOptions:
        [(id: TranscriptionOutputMode?, name: String)] {
        [(nil, "Use language default")]
            + TranscriptionOutputMode.allCases.map {
                ($0, $0.displayName)
            }
    }

    private var zenIntelligenceModeOptions:
        [(id: ZenIntelligenceMode?, name: String)] {
        [(nil, "Use global ZenIntelligence")]
            + ZenIntelligenceMode.allCases.map {
                ($0, $0.displayName)
            }
    }

    private var commandSetOptions: [(id: String?, name: String)] {
        [
            (nil, "Use global command set"),
            ("default", "Default commands")
        ]
    }

    private var writeModeOptions:
        [(id: WriteModeSubMode?, name: String)] {
        [(nil, "Use global Write Mode")]
            + WriteModeSubMode.allCases.map {
                ($0, $0.displayName)
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
