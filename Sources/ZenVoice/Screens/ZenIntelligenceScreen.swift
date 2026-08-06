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

struct ZenIntelligenceScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var previewInput = ""
    @State private var previewResult: ZenIntelligenceResult?

    var body: some View {
        ZenScreen(
            title: "ZenIntelligence",
            subtitle:
                "Local, opt-in enhancement that runs after Instant Refine."
        ) {
            modeSection
            previewSection
            privacyBanner
        }
    }

    private var modeSection: some View {
        ZenSection(title: "Enhancement mode") {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    modeCard(.off, detail: "Instant Refine only")
                    modeCard(.format, detail: "Capitalization & numbers")
                    modeCard(.contextAware, detail: "Uses context for joins")
                }

                ZenPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.zenIntelligenceMode.detail)
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                        Text(
                            "ZenIntelligence never leaves this Mac. The current implementation is deterministic; a local model can replace it later without changing settings or the meaning guard."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                    .padding(ZenDesign.Spacing.md)
                }
            }
        }
    }

    private func modeCard(
        _ mode: ZenIntelligenceMode,
        detail: String
    ) -> some View {
        ZenChoiceCard(
            title: mode.displayName,
            detail: detail,
            selected: viewModel.zenIntelligenceMode == mode
        ) {
            viewModel.setZenIntelligenceMode(mode)
            runPreview()
        }
    }

    private var previewSection: some View {
        ZenSection(
            title: "Live preview",
            caption: "Type rough text to see how ZenIntelligence formats it."
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $previewInput)
                        .font(ZenDesign.Typography.body)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
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
                        .onChange(of: previewInput) { _, _ in
                            runPreview()
                        }

                    if let previewResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(previewResult.text)
                                .font(ZenDesign.Typography.body)
                                .foregroundStyle(
                                    previewResult.wasRejected
                                        ? ZenDesign.Semantic.danger
                                        : ZenDesign.Semantic.textPrimary
                                )
                            if !previewResult.changeDescription.isEmpty {
                                Text(previewResult.changeDescription)
                                    .font(ZenDesign.Typography.caption)
                                    .foregroundStyle(
                                        ZenDesign.Semantic.textTertiary
                                    )
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var privacyBanner: some View {
        ZenBanner(
            kind: .info,
            icon: "lock.shield",
            text:
                "ZenIntelligence is local-only. The meaning guard rejects changes that would alter what you said."
        )
    }

    private func runPreview() {
        previewResult = ZenIntelligenceEngine().enhance(
            previewInput,
            mode: viewModel.zenIntelligenceMode,
            languageCode: viewModel.languageProfile.inputLanguageCode,
            context: viewModel.sanitizedNextDictationContext
        )
    }
}
