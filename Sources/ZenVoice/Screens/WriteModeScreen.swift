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

struct WriteModeScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            subModeSection
            defaultPromptSection
            accessibilityBanner
        }
    }

    private var subModeSection: some View {
        ZenSection(title: "Default sub-mode") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: ZenDesign.Spacing.sm),
                    GridItem(.flexible(), spacing: ZenDesign.Spacing.sm)
                ],
                spacing: ZenDesign.Spacing.sm
            ) {
                subModeCard(
                    .compose,
                    detail: "Insert transcript at the cursor"
                )
                subModeCard(
                    .rewrite,
                    detail: "Replace selected text"
                )
            }

            ZenPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.writeModeSubMode.displayName)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        "In Rewrite, ZenVoice reads the current selection using Accessibility (or the clipboard as a fallback), applies your prompt through the Smart formatting rung, and shows a preview when the change is large."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private func subModeCard(
        _ mode: WriteModeSubMode,
        detail: String
    ) -> some View {
        ZenChoiceCard(
            title: mode.displayName,
            detail: detail,
            selected: viewModel.writeModeSubMode == mode
        ) {
            viewModel.setWriteModeSubMode(mode)
        }
    }

    private var defaultPromptSection: some View {
        ZenSection(
            title: "Rewrite prompt",
            caption: "Used when no per-app custom prompt hints are set."
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(
                        text: Binding(
                            get: { viewModel.writeModeDefaultPrompt },
                            set: viewModel.setWriteModeDefaultPrompt
                        )
                    )
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(ZenDesign.Spacing.xs)
                    .frame(minHeight: 64, maxHeight: 82)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.surfaceSunken)
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: ZenDesign.Radius.small,
                                style: .continuous
                            )
                            .strokeBorder(
                                ZenDesign.Semantic.borderStrong
                            )
                        }
                    }

                    Text(
                        "\(viewModel.writeModeDefaultPrompt.count) characters"
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var accessibilityBanner: some View {
        ZenBanner(
            kind: .info,
            icon: "accessibility",
            text:
                "Write Mode Rewrite needs Accessibility access to read the current selection. If unavailable, it falls back to the clipboard."
        )
    }
}
