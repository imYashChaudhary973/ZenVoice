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

struct AppProfilesScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var applicationProfileViewModel:
        ApplicationProfileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            ZenBanner(
                kind: .info,
                icon: "info.circle",
                text: "Default behavior: new apps use your global language and formatting until you add a rule."
            )
            globalDefaults
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

    private var globalDefaults: some View {
        ZenPanel {
            ZenRow(
                icon: "text.bubble",
                title: "Local voice commands",
                subtitle: "Interpret spoken layout and punctuation commands by default"
            ) {
                ZenSwitch(
                    isOn: Binding(
                        get: { viewModel.voiceCommandsEnabled },
                        set: viewModel.setVoiceCommandsEnabled
                    ),
                    label: "Local voice commands"
                )
            }
            ZenPanelDivider()
            ZenRow(
                icon: "command",
                title: "Command Mode",
                subtitle: "Allow built-in app launches, Shortcuts, and system actions"
            ) {
                ZenSwitch(
                    isOn: Binding(
                        get: { viewModel.commandModeEnabled },
                        set: viewModel.setCommandModeEnabled
                    ),
                    label: "Command Mode"
                )
            }
        }
    }

    private var applicationProfilesCard: some View {
        ZenPanel(padding: ZenDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Application Rules")
                            .font(ZenDesign.Typography.sectionTitle)
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(
                            "Automatically choose language, formatting, and local voice commands for a target app."
                        )
                        .font(ZenDesign.Typography.body)
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
                                formattingMode:
                                    TranscriptFormattingPreferences.load()
                            )
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(
                        applicationProfileViewModel
                            .selectedApplicationID == nil
                    )
                }

                if applicationProfileViewModel.profiles.isEmpty {
                    ZenRow(
                        icon: "app.badge.checkmark",
                        title: "No profiles yet",
                        subtitle:
                            "Open a target app, refresh this list, then add it."
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
                .font(ZenDesign.Typography.caption)
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
                ZenIconChip(
                    systemImage: "macwindow",
                    size: 34,
                    tint: ZenDesign.Semantic.textSecondary
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.applicationName)
                        .font(ZenDesign.Typography.bodyStrong)
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
                ZenIconButton(
                    systemImage: "trash",
                    label: "Remove \(profile.applicationName)",
                    isDanger: true
                ) {
                    applicationProfileViewModel.remove(profile)
                }
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
                    "Formatting",
                    selection: Binding(
                        get: { profile.formattingMode },
                        set: {
                            applicationProfileViewModel
                                .setFormattingMode(
                                    $0,
                                    for: profile
                                )
                        }
                    )
                ) {
                    ForEach(
                        TranscriptFormattingMode.allCases,
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

            DisclosureGroup("More settings") {
                VStack(spacing: ZenDesign.Spacing.sm) {
                    HStack(spacing: 10) {
                        Picker(
                            "Engine",
                            selection: Binding(
                                get: { profile.preferredEngineID },
                                set: {
                                    applicationProfileViewModel
                                        .setPreferredEngineID($0, for: profile)
                                }
                            )
                        ) {
                            ForEach(engineOptions, id: \.id) { option in
                                Text(option.name).tag(option.id as String?)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Picker(
                            "Output mode",
                            selection: Binding(
                                get: { profile.preferredOutputMode },
                                set: {
                                    applicationProfileViewModel
                                        .setPreferredOutputMode($0, for: profile)
                                }
                            )
                        ) {
                            ForEach(outputModeOptions, id: \.id) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 10) {
                        Picker(
                            "Command set",
                            selection: Binding(
                                get: { profile.commandSetID },
                                set: {
                                    applicationProfileViewModel
                                        .setCommandSetID($0, for: profile)
                                }
                            )
                        ) {
                            ForEach(commandSetOptions, id: \.id) { option in
                                Text(option.name).tag(option.id as String?)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Picker(
                            "Write mode",
                            selection: Binding(
                                get: { profile.writeModeDefault },
                                set: {
                                    applicationProfileViewModel
                                        .setWriteModeDefault($0, for: profile)
                                }
                            )
                        ) {
                            ForEach(writeModeOptions, id: \.id) { option in
                                Text(option.name).tag(option.id as WriteModeSubMode?)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    TextField(
                        "Custom prompt hints (comma separated)",
                        text: Binding(
                            get: { profile.customPromptHints.joined(separator: ", ") },
                            set: { value in
                                let hints = value.split(separator: ",").map {
                                    $0.trimmingCharacters(in: .whitespaces)
                                }.filter { !$0.isEmpty }
                                applicationProfileViewModel
                                    .setCustomPromptHints(hints, for: profile)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(ZenDesign.Typography.body)
                }
                .padding(.top, ZenDesign.Spacing.xs)
            }
            .font(ZenDesign.Typography.captionStrong)
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
