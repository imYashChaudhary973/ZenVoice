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

import AppKit
import SwiftUI
import ZenVoiceCore

/// Top-center live transcription preview for Phase 4 overlays.
///
/// Shows the current phase, a waveform when listening, and the live transcript
/// preview when available. Adapts its layout to the requested overlay kind.
struct LivePreviewOverlayView: View {
    let kind: OverlayKind
    @ObservedObject var state: AppState
    /// ZenVoice's own overlay Reduce Motion preference, which defaults to the
    /// system setting and can override it.
    let reduceMotion: Bool
    let cancelRecording: () -> Void
    let finishRecording: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// Motion is reduced when either the system or ZenVoice asks for it.
    private var motionReduced: Bool { reduceMotion || systemReduceMotion }

    private var isNotchHUD: Bool {
        OverlayPreferences.loadHUDStyle() == .notch
    }

    var body: some View {
        Group {
            if isNotchHUD {
                content
                    .padding(.horizontal, 8)
                    .padding(.top, cameraInset > 0 ? cameraInset : 6)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 18,
                            bottomTrailingRadius: 18,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                        .fill(Color.black)
                    }
            } else {
                content
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .zenGlassSurface(
                        cornerRadius: ZenDesign.Radius.pill,
                        interactive: true
                    )
            }
        }
        .preferredColorScheme(OverlayPreferences.colorScheme())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Camera housing height on a notched Mac. Zero on plain displays.
    private var cameraInset: CGFloat {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }?
            .safeAreaInsets.top ?? 0
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            if isNotchHUD {
                listeningContent
            } else {
                idleContent
            }
        case .listening:
            listeningContent
        case .transcribing:
            statusContent("transcribing…", pulses: true)
        case .inserting:
            statusContent(
                "inserting…",
                pulses: true,
                tint: ZenDesign.Semantic.success
            )
        case .success:
            statusContent(
                successMessage,
                pulses: false,
                tint: ZenDesign.Semantic.success
            )
        case .error(let message):
            errorContent(message)
        }
    }

    private var idleContent: some View {
        HStack(spacing: 10) {
            BrandLogo(size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.mode.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text("Ready")
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
            Spacer()
            ZenKbdGroup(combo: HotKeyPreferences.load().displayName)
        }
    }

    /// Compact voice bars on the left, live words growing to the right.
    private var listeningContent: some View {
        HStack(spacing: 6) {
            OverlayCircleButton(
                systemImage: "xmark",
                label: "Cancel dictation",
                action: cancelRecording
            )
            if state.livePreviewEnabled {
                WaveformView(
                    model: state.audioLevel,
                    style: .voiceprint,
                    voiceprintBarWidth: 2.5,
                    voiceprintSpacing: 2,
                    voiceprintMaxHeight: 16,
                    voiceprintBarCount: 4
                )
                .frame(width: 16, height: 16)
                Text(
                    state.liveTranscriptPreview.isEmpty
                        ? "Listening…"
                        : state.liveTranscriptPreview
                )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        state.liveTranscriptPreview.isEmpty
                            ? ZenDesign.Semantic.textSecondary
                            : ZenDesign.Semantic.textPrimary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .animation(
                        listeningMotion,
                        value: state.liveTranscriptPreview
                    )
            } else {
                Spacer(minLength: 6)
                WaveformView(model: state.audioLevel, style: .voiceprint)
                    .frame(height: 16)
                Spacer(minLength: 6)
            }
            OverlayCircleButton(
                systemImage: "checkmark",
                label: "Finish dictation",
                action: finishRecording
            )
        }
        .animation(listeningMotion, value: state.livePreviewEnabled)
    }

    private var listeningMotion: Animation {
        motionReduced
            ? .easeOut(duration: 0.2)
            : .spring(response: 0.35, dampingFraction: 1.0)
    }

    private func statusContent(
        _ text: String,
        pulses: Bool,
        tint: Color = ZenDesign.Semantic.accent
    ) -> some View {
        HStack(spacing: 10) {
            ZenStatusLabel(
                text: text,
                tint: tint,
                pulses: pulses && !motionReduced
            )
            if state.phase == .transcribing {
                Spacer()
                // IndeterminateBar already stills itself for the system
                // setting; this covers ZenVoice's own preference too.
                if motionReduced {
                    Capsule()
                        .fill(ZenDesign.Semantic.accent.opacity(0.45))
                        .frame(maxWidth: 180, maxHeight: 3)
                } else {
                    IndeterminateBar()
                        .frame(maxWidth: 180)
                }
            } else {
                Spacer()
            }
        }
    }

    private func errorContent(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.danger)
            Text(message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .lineLimit(kind.lineCount)
                .truncationMode(.tail)
            Spacer(minLength: 6)
        }
    }

    private var successMessage: String {
        guard let summary = state.lastInsertionSummary else {
            return "inserted"
        }
        return "inserted · \(summary.wordCount) words · \(summary.wordsPerMinute) wpm"
    }
}
