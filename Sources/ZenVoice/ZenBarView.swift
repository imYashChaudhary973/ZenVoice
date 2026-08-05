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

struct ZenBarView: View {
    /// Room left around the bar for its shadow to land in.
    ///
    /// The panel clips its hosting view, so a shadow with nowhere to go is
    /// simply not drawn. These are the margins the panel is sized against in
    /// ``ZenBarPanelController``.
    static let shadowInset: CGFloat = 26
    static let barHeight: CGFloat = 44
    static let maximumBarWidth: CGFloat = 580

    @AppStorage(ZenAppearance.storageKey)
    private var appearance = ZenAppearance.system.rawValue
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @ObservedObject var state: AppState
    let toggleRecording: () -> Void
    let cancelRecording: () -> Void
    let finishRecording: () -> Void
    let dismissError: () -> Void

    var body: some View {
        bar
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
            .padding(.bottom, Self.shadowInset)
            .preferredColorScheme(
                ZenAppearance.resolved(appearance).colorScheme
            )
    }

    private var bar: some View {
        ZStack {
            // Identity changes on the *content* only. The container keeps
            // its own, so the bar's width and background morph between phases
            // while the contents cross-fade. Putting `.id` on the whole bar —
            // as this once did — destroyed and rebuilt it instead, which is
            // why every state change read as a hard cut.
            controlBar
                .id(state.phase.label)
                .transition(.opacity)
        }
        .frame(width: barWidth, height: Self.barHeight)
        .background(barBackground)
        .clipShape(barShape)
        .contentShape(barShape)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: state.phase)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: barWidth)
        .accessibilityElement(children: .contain)
    }

    private var barShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ZenDesign.Radius.bar,
            style: .continuous
        )
    }

    @ViewBuilder
    private var controlBar: some View {
        switch state.phase {
        case .idle:
            Button(action: toggleRecording) {
                HStack(spacing: 9) {
                    brandLogo(size: 22)
                    Text("Ready")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(barSecondary)
                    Spacer()
                    ZenKbdGroup(combo: "⌃⌥ Space")
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start ZenVoice dictation")
            .accessibilityHint("Press Control Option Space or activate this button.")

        case .listening:
            HStack(spacing: 10) {
                ZenStatusLabel(
                    text: "listening",
                    tint: barAccent,
                    pulses: true
                )

                WaveformView(model: state.audioLevel)

                // Only present when stable-phrase detection is switched on.
                // The text was computed and thrown away before this: nothing
                // read `liveTranscriptPreview` at all.
                if !state.liveTranscriptPreview.isEmpty {
                    Text(state.liveTranscriptPreview)
                        .font(.system(size: 11.5))
                        .foregroundStyle(barSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Spacer()
                }

                barButton("Cancel", action: cancelRecording)
                barButton(
                    "Finish",
                    emphasized: true,
                    action: finishRecording
                )
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("ZenVoice is listening")

        case .transcribing:
            // Transcribing and inserting were pixel-identical before, during
            // the slowest part of the interaction. Decoding is the part with
            // no upper bound the user can feel, so it is the one that gets a
            // progress hairline.
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    ZenStatusLabel(text: "transcribing…", pulses: true)
                    Spacer()
                }
                IndeterminateBar()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Transcribing locally")

        case .inserting:
            HStack(spacing: 10) {
                ZenStatusLabel(
                    text: "inserting…",
                    tint: barSuccess,
                    pulses: true
                )
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Inserting text")

        case .success:
            HStack(spacing: 9) {
                if let warning = state.lastDecodeWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(barDanger)
                    Text("inserted — \(warning)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(barPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    ZenStatusLabel(
                        text: successMessage,
                        tint: barSuccess
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(
                state.lastDecodeWarning.map { "Inserted, but \($0)" }
                    ?? "Inserted"
            )

        case .error(let message):
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(barDanger)
                Text(displayedError(message))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(barPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                barButton(
                    "Try again",
                    emphasized: true,
                    action: toggleRecording
                )
                barButton("Dismiss", action: dismissError)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(displayedError(message))
        }
    }

    private var barWidth: CGFloat {
        switch state.phase {
        case .idle:
            return 320
        case .listening:
            return state.liveTranscriptPreview.isEmpty ? 400 : 560
        case .transcribing, .inserting:
            return 310
        case .success:
            return state.lastDecodeWarning == nil ? 420 : 530
        case .error:
            return 530
        }
    }

    private var barBackground: some View {
        barShape
            .fill(barPanel)
            .overlay {
                barShape
                    .strokeBorder(barBorder, lineWidth: 1)
                    .overlay {
                        barShape
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    }
            }
            .shadow(color: Color.black.opacity(0.28), radius: 20, y: 9)
    }

    private var successMessage: String {
        guard let summary = state.lastInsertionSummary else {
            return "inserted"
        }
        return "inserted · \(summary.wordCount) words · \(summary.wordsPerMinute) wpm"
    }

    private func displayedError(_ message: String) -> String {
        if message.hasPrefix("Copied—") {
            let reason = String(message.dropFirst("Copied—".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "Couldn’t insert — \(reason) Text copied to clipboard."
        }
        return message
    }

    private func barButton(
        _ title: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: emphasized ? .semibold : .medium))
                .foregroundStyle(emphasized ? barAccent : barSecondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.barControl,
                        style: .continuous
                    )
                    .fill(
                        emphasized
                            ? ZenDesign.Semantic.accentMuted
                            : Color.clear
                    )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func brandLogo(size: CGFloat) -> some View {
        if let logo = BrandAssets.zenLogo {
            Image(nsImage: logo)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                )
        } else {
            Image(systemName: "waveform")
                .resizable()
                .foregroundStyle(barAccent)
                .frame(width: size, height: size)
        }
    }

    private var barPanel: Color {
        ZenDesign.Semantic.surface.opacity(0.96)
    }

    private var barBorder: Color {
        ZenDesign.Semantic.borderStrong
    }

    private var barPrimary: Color {
        ZenDesign.Semantic.textPrimary
    }

    private var barSecondary: Color {
        ZenDesign.Semantic.textSecondary
    }

    private var barAccent: Color {
        ZenDesign.Semantic.accent
    }

    private var barSuccess: Color {
        ZenDesign.Semantic.success
    }

    private var barDanger: Color {
        ZenDesign.Semantic.danger
    }
}

/// The one living element in the interface.
///
/// Observes ``AudioLevelModel`` rather than ``AppState`` so that a level
/// arriving fifteen times a second repaints these bars and nothing else.
///
/// The history is kept here rather than in the model because it is a property
/// of the drawing, not of the audio: the recorder reports a level, and what a
/// trailing window of levels should look like is this view's business.
private struct WaveformView: View {
    @ObservedObject var model: AudioLevelModel
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private static let barCount = 23
    private static let barWidth: CGFloat = 2
    private static let barSpacing: CGFloat = 2
    private static let maximumHeight: CGFloat = 18
    private static let minimumHeight: CGFloat = 2

    static var width: CGFloat {
        CGFloat(barCount) * barWidth
            + CGFloat(barCount - 1) * barSpacing
    }

    @State private var history = [Double](
        repeating: 0,
        count: barCount
    )

    var body: some View {
        HStack(spacing: Self.barSpacing) {
            ForEach(history.indices, id: \.self) { index in
                Capsule()
                    .fill(
                        ZenDesign.Semantic.accent
                            .opacity(opacity(at: index))
                    )
                    .frame(
                        width: Self.barWidth,
                        height: height(at: index)
                    )
            }
        }
        // Capsules are centre-aligned in the row, so a bar of height h extends
        // equally above and below the midline. That mirrored shape is what
        // reads as a voice rather than as a graphic equaliser.
        .frame(width: Self.width, height: Self.maximumHeight)
        .animation(ZenDesign.Motion.waveform(reduceMotion), value: history)
        .onChange(of: model.level) { _, level in
            var next = history
            next.removeFirst()
            next.append(level)
            history = next
        }
        .accessibilityHidden(true)
    }

    /// Newest sample sits at the trailing edge; older ones are damped so the
    /// trail falls away instead of ending on a cliff.
    private func taper(at index: Int) -> Double {
        let age = Double(index) / Double(max(1, Self.barCount - 1))
        return 0.4 + (0.6 * age)
    }

    private func height(at index: Int) -> CGFloat {
        let amplitude = history[index] * taper(at: index)
        return max(
            Self.minimumHeight,
            CGFloat(amplitude) * Self.maximumHeight
        )
    }

    private func opacity(at index: Int) -> Double {
        history[index] > 0.035 ? 0.35 + (0.63 * taper(at: index)) : 0.25
    }
}

/// A hairline that keeps moving while work of unknown length is happening.
///
/// whisper reports no progress, so there is nothing honest to fill a
/// determinate bar with. What this can truthfully say is "still going", which
/// is the thing a frozen-looking bar fails to say.
private struct IndeterminateBar: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private static let period: Double = 1.1
    private static let segmentFraction: CGFloat = 0.32

    var body: some View {
        GeometryReader { proxy in
            let segment = proxy.size.width * Self.segmentFraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ZenDesign.Semantic.surfaceSunken)
                if reduceMotion {
                    // No travelling segment; a static accent hairline still
                    // distinguishes this phase from the ones without one.
                    Capsule()
                        .fill(ZenDesign.Semantic.accent.opacity(0.45))
                } else {
                    TimelineView(.animation) { context in
                        let elapsed = context.date
                            .timeIntervalSinceReferenceDate
                        let phase = (elapsed.truncatingRemainder(
                            dividingBy: Self.period
                        )) / Self.period
                        Capsule()
                            .fill(ZenDesign.Semantic.accent)
                            .frame(width: segment)
                            .offset(
                                x: CGFloat(phase)
                                    * (proxy.size.width + segment)
                                    - segment
                            )
                    }
                }
            }
        }
        .frame(height: 2)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
