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

struct CommandModeScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            enableSection
            manifestSection
            trustBanner
        }
    }

    private var enableSection: some View {
        ZenSection(title: "Enable Command Mode") {
            ZenPanel {
                HStack(spacing: ZenDesign.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interpret voice commands")
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text(
                            "When on, dictation can launch apps, run Shortcuts, and adjust system settings. Per-app overrides live in App Profiles."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ZenDesign.Spacing.sm)
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.commandModeEnabled },
                            set: viewModel.setCommandModeEnabled
                        ),
                        label: "Enable Command Mode"
                    )
                }
                .padding(.horizontal, ZenDesign.Spacing.md)
                .padding(.vertical, ZenDesign.Spacing.sm)
                .frame(minHeight: 52)
            }
        }
    }

    private var manifestSection: some View {
        ZenSection(
            title: "Command phrases",
            caption: "Phrases are matched locally in manifest order."
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    HStack {
                        Text(
                            "Default manifest"
                        )
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Spacer()
                        Button("Reset to defaults") {
                            viewModel.resetCommandModeManifest()
                        }
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .disabled(
                            viewModel.commandModeManifest
                                == CommandModeEngine.defaultManifest
                        )
                    }

                    LazyVStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                        ForEach(
                            viewModel.commandModeManifest.mappings
                        ) { mapping in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(actionLabel(for: mapping.action))
                                    .font(ZenDesign.Typography.bodyStrong)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textPrimary
                                    )
                                Text(mapping.phrases.joined(separator: " · "))
                                    .font(ZenDesign.Typography.caption)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textSecondary
                                    )
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var trustBanner: some View {
        ZenBanner(
            kind: .info,
            icon: "hand.raised",
            text:
                "Command Mode runs built-in actions only: app launches and system actions. Scripts, shell commands, and multi-step goals belong to Agentic Mode, which requires approving the exact steps first."
        )
    }

    private func actionLabel(for action: CommandAction) -> String {
        switch action {
        case .none:
            return "No action"
        case .launchApp(let bundleID):
            return "Open app · \(bundleID)"
        case .systemAction(let systemAction):
            return systemAction.displayName
        }
    }
}
