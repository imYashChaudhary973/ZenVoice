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
import ZenVoiceRuntime

struct ModelMismatchAlert: Equatable {
    var title: String
    var description: String
    var token = UUID()
}

struct ModelsScreen: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @Binding var mismatchAlert: ModelMismatchAlert?

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            spokenLanguage
            let downloadedEngines = downloaded.filter {
                $0.id != ZenPolishLanguageModel.modelID
            }
            let downloadedEnhancement = downloaded.filter {
                $0.id == ZenPolishLanguageModel.modelID
            }
            if !downloadedEnhancement.isEmpty {
                cardSection(
                    title: "Downloaded dictation enhancement",
                    specs: downloadedEnhancement
                )
            }
            let availableEnhancement = available.filter {
                $0.id == ZenPolishLanguageModel.modelID
            }
            if !availableEnhancement.isEmpty {
                cardSection(
                    title: "Available dictation enhancement",
                    specs: availableEnhancement
                )
            }
            if !downloadedEngines.isEmpty {
                cardSection(title: "Downloaded speech-to-text", specs: downloadedEngines)
            }
            Text(
                "All models run entirely on this Mac. NVIDIA Parakeet stays loaded for instant dictation."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(ZenDesign.Semantic.textSecondary)
            if !available.isEmpty {
                cardSection(
                    title: "Available speech-to-text",
                    specs: available.filter {
                        $0.id != ZenPolishLanguageModel.modelID
                    }
                )
            }
            if let error = viewModel.errorMessage,
               !error.contains("Automatic detection requires") {
                ZenBanner(
                    kind: .danger,
                    icon: "exclamationmark.triangle",
                    text: error
                )
            }
        }
    }

    private var spokenLanguage: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            Text("Language")
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            ZenPanel {
                ZenRow(
                    title: "Spoken language",
                    subtitle:
                        "ZenVoice uses this language for dictation. Engines that cannot handle it stay unavailable."
                ) {
                    ZenMenuPicker(
                        label: "Spoken language",
                        options: LanguageCatalog.languages.map(\.code),
                        selection: Binding(
                            get: {
                                let code = settingsViewModel
                                    .languageProfile.inputLanguageCode
                                if code == LanguageProfile.automaticCode {
                                    return "en"
                                }
                                return code
                            },
                            set: settingsViewModel.setSpokenLanguage
                        ),
                        minWidth: 160,
                        title: { code in
                            LanguageCatalog.language(code: code)?.displayName
                                ?? code
                        }
                    )
                }

                ZenPanelDivider()

                ZenRow(
                    title: "Translate to English",
                    subtitle:
                        "Whisper translates while decoding. Other engines use Apple Intelligence on this Mac."
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: {
                                settingsViewModel.languageProfile
                                    .shouldTranslateToEnglish
                            },
                            set: { enabled in
                                settingsViewModel.setOutputMode(
                                    enabled
                                        ? .englishTranslation
                                        : .spokenLanguage
                                )
                            }
                        ),
                        label: "Translate to English"
                    )
                }
            }
        }
    }

    private func cardSection(
        title: String,
        specs: [EngineCardSpec]
    ) -> some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            Text(title.uppercased())
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            VStack(spacing: ZenDesign.Spacing.sm) {
                ForEach(specs) { spec in
                    engineRow(spec)
                }
            }
        }
    }

    private var downloaded: [EngineCardSpec] {
        EngineCardSpec.picker.filter { isDownloaded($0) }
    }

    private var available: [EngineCardSpec] {
        EngineCardSpec.picker.filter { !isDownloaded($0) }
    }

    private func isDownloaded(_ spec: EngineCardSpec) -> Bool {
        if spec.builtIn { return true }
        if spec.comingSoon { return false }
        if spec.id == ZenPolishLanguageModel.modelID {
            return viewModel.isZenPolishInstalled()
        }
        return viewModel.installedEngineIDs.contains(spec.id)
            || viewModel.installedModelIDs.contains(spec.id)
    }

    private func engineRow(_ spec: EngineCardSpec) -> some View {
        let selected = viewModel.isSelectedEngine(spec.id)
        let isZenPolish = spec.id == ZenPolishLanguageModel.modelID
        let downloading = isZenPolish
            ? viewModel.isDownloadingZenPolish
            : viewModel.isDownloadingEngine(id: spec.id)
        return Button {
            guard !spec.comingSoon else { return }
            if isZenPolish {
                if !viewModel.isZenPolishInstalled() {
                    viewModel.downloadZenPolish()
                }
                return
            }
            viewModel.selectEngine(spec.id)
        } label: {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
                    engineGlyph(spec.glyph)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(spec.title)
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            if selected {
                                ZenBadge(
                                    text: "Active",
                                    kind: .accent,
                                    systemImage: "checkmark"
                                )
                            } else if let badge = spec.badge {
                                ZenBadge(text: badge, kind: .accent)
                            }
                        }
                        Text(spec.summary)
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 6) {
                        MeterBar(
                            label: "Accuracy",
                            value: spec.accuracy,
                            tint: ZenDesign.Semantic.accent
                        )
                        MeterBar(
                            label: "Speed",
                            value: spec.speed,
                            tint: ZenDesign.Semantic.warn
                        )
                    }
                }
                Rectangle()
                    .fill(ZenDesign.Semantic.border)
                    .frame(height: 1)
                    .opacity(0.5)
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    Text(spec.languages)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    if spec.realtime {
                        ZenBadge(text: "Real-time", kind: .accent)
                    }
                    Spacer()
                    cardAction(
                        spec: spec,
                        selected: selected,
                        downloading: downloading
                    )
                }
                if downloading {
                    ZenProgressBar(
                        value: isZenPolish
                            ? viewModel.downloadProgress ?? 0
                            : viewModel.engineDownloadProgress(
                                for: spec.id
                            ) ?? 0
                    )
                    .frame(height: 3)
                }
            }
            .padding(ZenDesign.Spacing.md)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.large,
                    style: .continuous
                )
                .fill(
                    selected
                        ? ZenDesign.Semantic.accentMuted
                        : ZenDesign.Component.cardBackground
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.large,
                        style: .continuous
                    )
                    .strokeBorder(
                        selected
                            ? ZenDesign.Semantic.accent
                            : ZenDesign.Semantic.border,
                        lineWidth: selected ? 1.5 : 1
                    )
                }
            }
        }
        .buttonStyle(ZenPressButtonStyle())
        .disabled(spec.comingSoon)
        .accessibilityLabel(spec.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func cardAction(
        spec: EngineCardSpec,
        selected: Bool,
        downloading: Bool
    ) -> some View {
        if spec.builtIn {
            Label("Built in", systemImage: "checkmark.circle.fill")
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(ZenDesign.Semantic.success)
        } else if spec.comingSoon {
            Text("Coming soon")
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
        } else if downloading {
            if spec.id == ZenPolishLanguageModel.modelID {
                // Cancellation lands with the v3 download refactor.
                Button("Cancel") {}
                    .buttonStyle(ZenSecondaryButtonStyle())
                    .disabled(true)
            } else {
                Button("Cancel") { viewModel.cancelDownload() }
                    .buttonStyle(ZenSecondaryButtonStyle())
            }
        } else if isDownloaded(spec) {
            if spec.id == ZenPolishLanguageModel.modelID {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.success)
            } else if selected {
                EmptyView()
            } else {
                Text("Use")
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.accent)
            }
        } else {
            Label("Download", systemImage: "arrow.down.circle")
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(ZenDesign.Semantic.accent)
        }
    }

    private func engineGlyph(_ glyph: EngineCardSpec.Glyph) -> some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .fill(glyph.fill)
            .frame(width: 36, height: 36)
            Image(systemName: glyph.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Display scores for the Models cards. Not measured WER.
///
/// ponytail: replace with benchmark medians when we have them.
private struct EngineCardSpec: Identifiable {
    enum Glyph {
        case apple, nvidia, whisper, cohere, qwen, zenpolish

        var symbol: String {
            switch self {
            case .apple: return "apple.logo"
            case .nvidia: return "eye.fill"
            case .whisper: return "sparkles"
            case .cohere: return "waveform"
            case .qwen: return "globe.asia.australia.fill"
            case .zenpolish: return "brain"
            }
        }

        var fill: Color {
            switch self {
            case .apple: return Color(white: 0.22)
            case .nvidia: return Color(red: 0.29, green: 0.73, blue: 0.31)
            case .whisper: return Color(red: 0.48, green: 0.42, blue: 0.92)
            case .cohere: return Color(red: 0.22, green: 0.45, blue: 0.92)
            case .qwen: return Color(red: 0.86, green: 0.35, blue: 0.18)
            case .zenpolish: return Color(red: 0.38, green: 0.28, blue: 0.86)
            }
        }
    }

    let id: String
    let title: String
    let summary: String
    let glyph: Glyph
    let badge: String?
    let languages: String
    let realtime: Bool
    let accuracy: Double
    let speed: Double
    let builtIn: Bool
    let comingSoon: Bool

    static let picker: [EngineCardSpec] = [
        EngineCardSpec(
            id: ZenPolishLanguageModel.modelID,
            title: "ZenPolish 1.7B",
            summary:
                "ZenVoice's own fine-tuned formatting model. Punctuation, "
                + "capitalization, fillers, and numbers for the Smart level. "
                + "934 MB. Runs on this Mac.",
            glyph: .zenpolish,
            badge: "Smart",
            languages: "English",
            realtime: false,
            accuracy: 0.85,
            speed: 0.70,
            builtIn: false,
            comingSoon: false
        ),
        EngineCardSpec(
            id: EngineIdentifiers.appleSpeech,
            title: "Apple Speech Analyzer",
            summary:
                "Next-generation on-device speech recognition. Requires macOS 26+.",
            glyph: .apple,
            badge: nil,
            languages: "System languages",
            realtime: true,
            accuracy: 0.82,
            speed: 0.96,
            builtIn: true,
            comingSoon: false
        ),
        EngineCardSpec(
            id: EngineIdentifiers.qwen3ASR,
            title: "Qwen3-ASR 0.6B",
            summary:
                "On-device multilingual ASR. 6-bit MLX, ~822 MB. 30 languages.",
            glyph: .qwen,
            badge: "New",
            languages: "30 languages",
            realtime: false,
            accuracy: 0.90,
            speed: 0.74,
            builtIn: false,
            comingSoon: false
        ),
        EngineCardSpec(
            id: EngineIdentifiers.nemotronSpeech,
            title: "NVIDIA Nemotron 3.5 Multilingual 0.6B",
            summary:
                "True streaming transcription: words land while you speak, in 8 languages.",
            glyph: .nvidia,
            badge: "Streaming",
            languages: "8 languages",
            realtime: true,
            accuracy: 0.78,
            speed: 0.86,
            builtIn: false,
            comingSoon: false
        ),
        EngineCardSpec(
            id: EngineIdentifiers.parakeetTDTv3,
            title: "NVIDIA Parakeet TDT 0.6B V3",
            summary:
                "Ultra-fast NVIDIA FastConformer model for conversational speech and voice commands.",
            glyph: .nvidia,
            badge: "Fastest",
            languages: "25 languages",
            realtime: false,
            accuracy: 0.80,
            speed: 0.92,
            builtIn: false,
            comingSoon: false
        ),
        EngineCardSpec(
            id: EngineIdentifiers.parakeetTDTv2,
            title: "NVIDIA Parakeet TDT 0.6B V2",
            summary:
                "Ultra-fast English-only transcription on NVIDIA FastConformer V2.",
            glyph: .nvidia,
            badge: nil,
            languages: "English only",
            realtime: false,
            accuracy: 0.78,
            speed: 0.88,
            builtIn: false,
            comingSoon: false
        ),
        EngineCardSpec(
            id: EngineIdentifiers.cohereTranscribe,
            title: "Cohere Transcribe",
            summary:
                "2B on-device Conformer. 14 languages. ~3 GB ONNX download.",
            glyph: .cohere,
            badge: nil,
            languages: "14 languages",
            realtime: false,
            accuracy: 0.86,
            speed: 0.62,
            builtIn: false,
            comingSoon: false
        ),
        EngineCardSpec(
            id: EngineIdentifiers.whisperLargeV3Turbo,
            title: "Whisper Large v3 Turbo",
            summary:
                "Higher accuracy for longer offline dictations and complex speech.",
            glyph: .whisper,
            badge: nil,
            languages: "99 languages",
            realtime: false,
            accuracy: 0.88,
            speed: 0.70,
            builtIn: false,
            comingSoon: false
        ),
        EngineCardSpec(
            id: "whisper-small-multilingual",
            title: "Whisper Small",
            summary:
                "Balanced on-device dictation model for everyday use.",
            glyph: .whisper,
            badge: nil,
            languages: "99 languages",
            realtime: false,
            accuracy: 0.62,
            speed: 0.78,
            builtIn: false,
            comingSoon: false
        ),
        EngineCardSpec(
            id: "whisper-tiny-en",
            title: "Whisper Tiny (English)",
            summary:
                "Tiniest English-only model for instant voice notes. Limited accuracy.",
            glyph: .whisper,
            badge: nil,
            languages: "English only",
            realtime: false,
            accuracy: 0.34,
            speed: 0.96,
            builtIn: false,
            comingSoon: false
        ),
        EngineCardSpec(
            id: "whisper-tiny-multilingual",
            title: "Whisper Tiny",
            summary:
                "Tiniest multilingual model for instant voice notes. Accuracy limited on complex speech.",
            glyph: .whisper,
            badge: nil,
            languages: "99 languages",
            realtime: false,
            accuracy: 0.30,
            speed: 0.96,
            builtIn: false,
            comingSoon: false
        )
    ]
}

private struct MeterBar: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .frame(width: 58, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ZenDesign.Semantic.border.opacity(0.45))
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: max(6, geo.size.width * min(1, max(0, value)))
                        )
                }
            }
            .frame(width: 92, height: 6)
        }
    }
}

struct ModelMismatchToastOverlay: View {
    @Binding var alert: ModelMismatchAlert?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack {
            Spacer()
            if visible, let alert {
                ZenSystemAlert(
                    title: alert.title,
                    description: alert.description
                ) {
                    dismiss()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .transition(
                    .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .allowsHitTesting(visible)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: visible)
        .onChange(of: alert) { _, new in
            guard new != nil else {
                visible = false
                return
            }
            present()
        }
    }

    private func present() {
        hideTask?.cancel()
        visible = true
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        visible = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            alert = nil
        }
    }
}
