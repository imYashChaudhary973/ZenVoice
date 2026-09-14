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

/// The floating dictation HUD.
///
/// Listening is the shape the bar is remembered by: a stroked capsule with a
/// cancel circle, a center voiceprint, and a confirm circle. No labels. The
/// two actions already have keyboard routes (Esc / the dictation shortcut);
/// the icons are the pointer equivalent, always on screen because they *are*
/// the interface, not chrome around it.
///
/// Every other phase keeps that capsule and only changes what it holds.
struct ZenBarView: View {
    /// Room left around the bar for its shadow to land in.
    ///
    /// The panel clips its hosting view, so a shadow with nowhere to go is
    /// simply not drawn. These are the margins the panel is sized against in
    /// ``OverlayKind/defaultSize``.
    static let shadowInset: CGFloat = 26
    static let barHeight: CGFloat = 42
    static let maximumBarWidth: CGFloat = 520

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @ObservedObject var state: AppState
    let toggleRecording: () -> Void
    let cancelRecording: () -> Void
    let finishRecording: () -> Void
    let dismissError: () -> Void
    let cancelAgenticGoal: () -> Void

    @State private var hovering = false

    var body: some View {
        bar
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
            .padding(.bottom, Self.shadowInset)
            .preferredColorScheme(ZenAppearance.colorScheme)
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
        .zenGlassSurface(
            cornerRadius: Self.barHeight / 2,
            interactive: true
        )
        .clipShape(barShape)
        .overlay {
            barShape.strokeBorder(
                ZenDesign.Semantic.textPrimary.opacity(0.72),
                lineWidth: 1.4
            )
        }
        .contentShape(barShape)
        .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)
        .onHover { hovering = $0 }
        .animation(ZenDesign.Motion.standard(reduceMotion), value: state.phase)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: barWidth)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: hovering)
        .accessibilityElement(children: .contain)
    }

    /// A true capsule, derived from the height so the two cannot drift.
    private var barShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: Self.barHeight / 2,
            style: .continuous
        )
    }

    @ViewBuilder
    private var controlBar: some View {
        switch state.phase {
        case .idle:
            if let event = state.agenticStatusEvent {
                agenticContent(event)
            } else {
                idleContent
            }

        case .listening:
            listeningContent

        case .transcribing:
            workingContent(
                "transcribing…",
                tint: ZenDesign.Semantic.accent,
                showsProgress: true
            )

        case .awaitingCloudReview:
            reviewContent

        case .inserting:
            workingContent(
                "inserting…",
                tint: ZenDesign.Semantic.success,
                showsProgress: false
            )

        case .success:
            successContent

        case .error(let message):
            errorContent(message)
        }
    }

    /// At rest: brand mark and a quiet voiceprint. Click starts dictation.
    /// Hover reveals the shortcut, which is the thing a user might want to
    /// check without opening Settings.
    private var idleContent: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 8) {
                BrandLogo(size: 18)
                WaveformView(model: state.audioLevel, style: .voiceprint)
                    .opacity(0.45)
                if hovering {
                    ZenKbdGroup(combo: HotKeyPreferences.load().displayName)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ZenPressButtonStyle(cornerRadius: Self.barHeight / 2)
        )
        .accessibilityLabel("Start BuilderHelm Voice \(state.mode.displayName)")
        .accessibilityHint(
            "Press \(HotKeyPreferences.load().displayName) or activate this button."
        )
    }

    /// The recording HUD. Cancel, voiceprint, finish — that is the whole bar.
    private var listeningContent: some View {
        HStack(spacing: 0) {
            OverlayCircleButton(
                systemImage: "xmark",
                label: "Cancel dictation",
                action: cancelRecording
            )
            Spacer(minLength: 6)
            WaveformView(model: state.audioLevel, style: .voiceprint)
            Spacer(minLength: 6)
            OverlayCircleButton(
                systemImage: "checkmark",
                label: "Finish dictation",
                action: finishRecording
            )
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("BuilderHelm Voice is listening")
    }

    private func workingContent(
        _ label: String,
        tint: Color,
        showsProgress: Bool
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ZenStatusLabel(text: label, tint: tint, pulses: true)
                Spacer(minLength: 0)
            }
            if showsProgress {
                IndeterminateBar()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(label)
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZenStatusLabel(
                text: "review cloud text…",
                tint: ZenDesign.Semantic.accent,
                pulses: false
            )
            Text("Press your dictation shortcut to keep the local text.")
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 16)
        .accessibilityLabel(
            "Waiting for your cloud review. Press your dictation "
                + "shortcut to keep the local text."
        )
    }

    private var successContent: some View {
        HStack(spacing: 8) {
            if let warning = state.lastDecodeWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.danger)
                Text("inserted — \(warning)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.success)
                Text(successMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(
            state.lastDecodeWarning.map { "Inserted, but \($0)" }
                ?? "Inserted"
        )
    }

    private func errorContent(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.danger)
            Text(displayedError(message))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            OverlayCircleButton(
                systemImage: "arrow.clockwise",
                label: "Try again",
                action: toggleRecording
            )
            OverlayCircleButton(
                systemImage: "xmark",
                label: "Dismiss",
                action: dismissError
            )
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(displayedError(message))
    }

    private func agenticContent(_ event: GoalStatusEvent) -> some View {
        HStack(spacing: 8) {
            Image(
                systemName: state.isAgenticGoalActive
                    ? "gearshape.2.fill"
                    : terminalAgenticIcon(event)
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(
                state.isAgenticGoalActive
                    ? ZenDesign.Semantic.accent
                    : agenticEventTint(event)
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(state.agenticGoalTitle ?? "Agentic goal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                Text(event.message)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if state.isAgenticGoalActive {
                OverlayCircleButton(
                    systemImage: "stop.fill",
                    label: "Stop agentic goal",
                    action: cancelAgenticGoal
                )
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, state.isAgenticGoalActive ? 8 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(
            "\(state.agenticGoalTitle ?? "Agentic goal"). \(event.message)"
        )
    }

    private var barWidth: CGFloat {
        switch state.phase {
        case .idle:
            if state.agenticStatusEvent != nil {
                return state.isAgenticGoalActive ? 360 : 320
            }
            return hovering ? 248 : 164
        case .listening:
            return 188
        case .transcribing, .inserting:
            return 176
        case .awaitingCloudReview:
            return 420
        case .success:
            return state.lastDecodeWarning == nil ? 240 : 420
        case .error:
            return 480
        }
    }

    private func terminalAgenticIcon(_ event: GoalStatusEvent) -> String {
        switch event.event {
        case .succeeded:
            return "checkmark.circle.fill"
        case .cancelled:
            return "stop.circle.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }

    private func agenticEventTint(_ event: GoalStatusEvent) -> Color {
        switch event.event {
        case .succeeded:
            return ZenDesign.Semantic.success
        case .cancelled:
            return ZenDesign.Semantic.textSecondary
        default:
            return ZenDesign.Semantic.danger
        }
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
}

/// The level meter.
///
/// Observes ``AudioLevelModel`` rather than ``AppState`` so that a level
/// arriving fifteen times a second repaints these bars and nothing else.
///
/// Two drawings share this view. `.trail` is a scrolling history of overall
/// loudness for the live-preview overlays. `.voiceprint` is the live waveform
/// in the recording HUD: every bar moves while you speak.
struct WaveformView: View {
    enum Style {
        case trail
        case voiceprint
    }

    @ObservedObject var model: AudioLevelModel
    var barCount: Int = 23
    var style: Style = .trail
    var voiceprintBarWidth: CGFloat = 2.5
    var voiceprintSpacing: CGFloat = 2
    var voiceprintMaxHeight: CGFloat = 20
    var voiceprintBarCount: Int = AudioSpectrumMeter.barCount

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private static let barWidth: CGFloat = 2
    private static let barSpacing: CGFloat = 2
    private static let maximumHeight: CGFloat = 18
    private static let minimumHeight: CGFloat = 2

    static var width: CGFloat {
        CGFloat(23) * barWidth + CGFloat(22) * barSpacing
    }

    static var voiceprintWidth: CGFloat {
        let count = CGFloat(AudioSpectrumMeter.barCount)
        return count * 2.5 + (count - 1) * 2
    }

    @State private var history = [Double](repeating: 0, count: 23)
    @State private var displayBands = [Double](
        repeating: 0,
        count: AudioSpectrumMeter.barCount
    )

    var body: some View {
        Group {
            switch style {
            case .trail:
                trailMeter
            case .voiceprint:
                voiceprintMeter
            }
        }
        .animation(ZenDesign.Motion.waveform(reduceMotion), value: history)
        .animation(ZenDesign.Motion.waveform(reduceMotion), value: displayBands)
        .onAppear {
            displayBands = model.bands
            if history.count != barCount {
                history = [Double](repeating: 0, count: barCount)
            }
        }
        .onChange(of: model.level) { _, level in
            var next = history
            if next.count != barCount {
                next = [Double](repeating: 0, count: barCount)
            }
            guard !next.isEmpty else { return }
            next.removeFirst()
            next.append(level)
            history = next
        }
        .onChange(of: model.bands) { _, bands in
            displayBands = bands
        }
        .accessibilityHidden(true)
    }

    private var trailMeter: some View {
        HStack(spacing: Self.barSpacing) {
            ForEach(history.indices, id: \.self) { index in
                Capsule()
                    .fill(
                        ZenDesign.Semantic.accent
                            .opacity(trailOpacity(at: index))
                    )
                    .frame(
                        width: Self.barWidth,
                        height: trailHeight(at: index)
                    )
            }
        }
        .frame(width: trailWidth, height: Self.maximumHeight)
    }

    private var voiceprintMeter: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1.0 / 12.0 : 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: voiceprintSpacing) {
                ForEach(0..<voiceprintBarCount, id: \.self) { index in
                    Capsule()
                        .fill(ZenDesign.Semantic.textPrimary)
                        .frame(
                            width: voiceprintBarWidth,
                            height: voiceprintHeight(at: index, time: time)
                        )
                }
            }
            .frame(width: voiceprintWidth, height: voiceprintMaxHeight)
        }
    }

    private var voiceprintWidth: CGFloat {
        let count = CGFloat(max(1, voiceprintBarCount))
        return count * voiceprintBarWidth
            + (count - 1) * voiceprintSpacing
    }

    private var trailWidth: CGFloat {
        CGFloat(barCount) * Self.barWidth
            + CGFloat(max(0, barCount - 1)) * Self.barSpacing
    }

    private func trailTaper(at index: Int) -> Double {
        let age = Double(index) / Double(max(1, barCount - 1))
        return 0.4 + (0.6 * age)
    }

    private func trailHeight(at index: Int) -> CGFloat {
        guard history.indices.contains(index) else {
            return Self.minimumHeight
        }
        let amplitude = history[index] * trailTaper(at: index)
        return max(
            Self.minimumHeight,
            CGFloat(amplitude) * Self.maximumHeight
        )
    }

    private func trailOpacity(at index: Int) -> Double {
        guard history.indices.contains(index) else { return 0.25 }
        return history[index] > 0.035
            ? 0.35 + (0.63 * trailTaper(at: index))
            : 0.25
    }

    private func voiceprintEnergy(at index: Int) -> Double {
        let source = displayBands
        let count = max(1, voiceprintBarCount)
        guard !source.isEmpty, count > 0 else { return 0 }
        if source.count == 1 || count == 1 {
            return source[0]
        }
        let t = Double(index) / Double(max(1, count - 1))
            * Double(source.count - 1)
        let lower = min(source.count - 1, max(0, Int(t)))
        let upper = min(source.count - 1, lower + 1)
        let fraction = t - Double(lower)
        return source[lower] * (1 - fraction) + source[upper] * fraction
    }

    private func voiceprintHeight(at index: Int, time: TimeInterval) -> CGFloat {
        let energy = voiceprintEnergy(at: index)
        let pulse: Double
        if reduceMotion || energy < 0.05 {
            pulse = 1
        } else {
            // Out-of-phase bounce so the meter keeps moving between buffers.
            let speed = 10.0 + Double(index) * 0.7
            let phase = Double(index) * 0.85
            pulse = 0.70 + 0.30 * sin(time * speed + phase)
        }
        return max(
            Self.minimumHeight,
            CGFloat(energy * pulse) * voiceprintMaxHeight
        )
    }
}

/// A hairline that keeps moving while work of unknown length is happening.
///
/// whisper reports no progress, so there is nothing honest to fill a
/// determinate bar with. What this can truthfully say is "still going", which
/// is the thing a frozen-looking bar fails to say.
struct IndeterminateBar: View {
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
