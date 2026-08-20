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

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .zenGlassSurface(
                cornerRadius: ZenDesign.Radius.bar,
                interactive: true
            )
            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)
            .preferredColorScheme(ZenAppearance.colorScheme)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            idleContent
        case .listening:
            listeningContent
        case .transcribing:
            statusContent("transcribing…", pulses: true)
        case .awaitingCloudReview:
            statusContent(
                "review cloud text…",
                pulses: false,
                tint: ZenDesign.Semantic.accent
            )
        case .inserting:
            statusContent("inserting…", pulses: true, tint: ZenDesign.Semantic.success)
        case .success:
            statusContent(successMessage, pulses: false, tint: ZenDesign.Semantic.success)
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

    private var listeningContent: some View {
        VStack(spacing: ZenDesign.Spacing.xs) {
            HStack(spacing: 10) {
                ZenStatusLabel(
                    text: "listening",
                    tint: ZenDesign.Semantic.accent,
                    pulses: !motionReduced
                )
                Spacer()
                OverlayBarButton(title: "Cancel", action: cancelRecording)
                OverlayBarButton(
                    title: "Finish",
                    emphasized: true,
                    action: finishRecording
                )
            }

            HStack(spacing: ZenDesign.Spacing.xs) {
                WaveformView(model: state.audioLevel)
                    .frame(height: 24)
                if !state.liveTranscriptPreview.isEmpty {
                    Text(state.liveTranscriptPreview)
                        .font(.system(size: 12.5))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .lineLimit(kind.lineCount)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
            }
        }
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
