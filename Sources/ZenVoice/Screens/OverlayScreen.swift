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

struct OverlayScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            styleSection
            if viewModel.livePreviewOverlayEnabled {
                previewSection
            }
        }
    }

    private var styleSection: some View {
        ZenSection(title: "Live preview") {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    Text(
                        "Show a larger, notch-aware transcription overlay "
                            + "while dictating. ZenBar remains the default."
                    )
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Toggle(
                        "Enable live preview overlays",
                        isOn: Binding(
                            get: { viewModel.livePreviewOverlayEnabled },
                            set: { viewModel.setLivePreviewOverlayEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    if viewModel.livePreviewOverlayEnabled {
                        Picker(
                            "Overlay style",
                            selection: Binding(
                                get: { viewModel.activeOverlayKind },
                                set: { viewModel.setActiveOverlayKind($0) }
                            )
                        ) {
                            ForEach(OverlayKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Toggle(
                            "Reduce motion",
                            isOn: Binding(
                                get: { viewModel.overlayReduceMotion },
                                set: { viewModel.setOverlayReduceMotion($0) }
                            )
                        )
                        .toggleStyle(.switch)
                    }
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var previewSection: some View {
        ZenSection(
            title: "Preview",
            caption: "Approximate size and shape on screen."
        ) {
            ZenPanel {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ZenDesign.Spacing.lg) {
                        previewSurface
                        previewDescription
                            .frame(minWidth: 180, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                        previewSurface
                        previewDescription
                    }
                }
                .padding(ZenDesign.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var previewSurface: some View {
        let size = viewModel.activeOverlayKind.defaultSize
        return RoundedRectangle(
            cornerRadius: ZenDesign.Radius.bar,
            style: .continuous
        )
        .fill(ZenDesign.Semantic.surface.opacity(0.96))
        .overlay {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.bar,
                style: .continuous
            )
            .strokeBorder(ZenDesign.Semantic.borderStrong, lineWidth: 1)
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: size.width, maxHeight: size.height)
        .overlay {
            previewContent
                .padding(ZenDesign.Spacing.xs)
        }
    }

    private var previewDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.activeOverlayKind.displayName)
                .font(ZenDesign.Typography.bodyStrong)
            Text(viewModel.activeOverlayKind.detail)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if viewModel.activeOverlayKind == .zenBar {
            HStack(spacing: ZenDesign.Spacing.xs) {
                BrandLogo(size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dictation")
                        .font(.system(size: 12, weight: .medium))
                    Text("Ready")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ZenDesign.Semantic.accent)
                        .frame(width: 6, height: 6)
                    Text("listening")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    Spacer()
                }
                Text("This is how live transcription looks in the overlay.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(
                        max(1, viewModel.activeOverlayKind.lineCount - 1)
                    )
                    .truncationMode(.tail)
            }
        }
    }
}
