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

struct AgenticModeScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            ZenSection(title: "Enable Agentic Mode") {
                ZenPanel {
                    VStack(spacing: 0) {
                        settingRow(
                            title: "Run approved multi-step goals",
                            detail: "After Command Mode phrases are checked, ZenVoice can turn a spoken goal into a reviewable plan for Codex or Claude.",
                            isOn: Binding(
                                get: { viewModel.agenticModeEnabled },
                                set: viewModel.setAgenticModeEnabled
                            ),
                            label: "Enable Agentic Mode"
                        )

                        Divider()
                            .overlay(ZenDesign.Semantic.border)
                            .padding(.leading, ZenDesign.Spacing.md)

                        settingRow(
                            title: "Remember exact low-risk approvals",
                            detail: "Only an unchanged low-risk step can be remembered. Medium and high-risk steps always require a fresh decision.",
                            isOn: Binding(
                                get: {
                                    viewModel.remembersAgenticLowRiskApprovals
                                },
                                set: viewModel
                                    .setRemembersAgenticLowRiskApprovals
                            ),
                            label: "Remember low-risk approvals"
                        )
                        .disabled(!viewModel.agenticModeEnabled)
                    }
                }
            }

            ZenSection(title: "Execution contract") {
                ZenPanel {
                    VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                        contractRow(
                            icon: "checklist",
                            title: "Review before execution",
                            detail: "Every new plan shows its steps, exact commands, working directory, and recomputed risk."
                        )
                        contractRow(
                            icon: "lock.shield",
                            title: "Local planner, encrypted record",
                            detail: "Planning uses deterministic rules or Apple's on-device model. Plans and output are encrypted in the local vault."
                        )
                        contractRow(
                            icon: "stop.circle",
                            title: "Cancel from ZenBar",
                            detail: "Cancellation stops the active process group. Relaunch never resumes an interrupted command."
                        )
                    }
                    .padding(ZenDesign.Spacing.md)
                }
            }

            ZenBanner(
                kind: .warn,
                icon: "exclamationmark.shield",
                text: "Agentic Mode can edit files and run tools after you approve a plan. It remains off by default and never receives provider API keys from ZenVoice."
            )
        }
    }

    private func settingRow(
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        label: String
    ) -> some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ZenDesign.Spacing.sm)
            ZenSwitch(isOn: isOn, label: label)
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .padding(.vertical, ZenDesign.Spacing.sm)
        .frame(minHeight: 58)
    }

    private func contractRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(detail)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
        }
    }
}
