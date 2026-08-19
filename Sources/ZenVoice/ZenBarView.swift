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

/// The floating dictation bar.
///
/// This is the surface the user sees more than any other, and it is the one
/// that has to justify sitting permanently on top of their work. So it is small
/// and it is quiet: at rest it is a capsule about the size of a word, showing a
/// flat waveform and nothing else.
///
/// The previous version was a 580pt-wide rectangle carrying, simultaneously, a
/// logo, the mode name, the word "Ready", a three-way mode switcher, a Start
/// button and the shortcut in key caps — six clusters, permanently, for an
/// operation the user performs with a key they already know. That is a toolbar,
/// and a toolbar that never goes away is furniture.
///
/// **Controls are revealed on hover, not displayed.** Every action here has a
/// keyboard route: the shortcut starts and finishes, and the mode is a setting.
/// So the controls do not need to be on screen — they need to be *reachable*,
/// which is what pointing at the bar does. The one exception is an error, which
/// is the only state that can't be resolved by pressing the shortcut again.
///
/// The resting waveform is the same `WaveformView` used while listening, fed
/// the same level model. At rest the level is zero, so the bars sit flat; when
/// speech arrives the identical component comes alive. Nothing swaps out, which
/// is why starting dictation reads as the bar *waking up* rather than as one
/// view being replaced by another.
struct ZenBarView: View {
    /// Room left around the bar for its shadow to land in.
    ///
    /// The panel clips its hosting view, so a shadow with nowhere to go is
    /// simply not drawn. These are the margins the panel is sized against in
    /// ``OverlayKind/defaultSize``.
    static let shadowInset: CGFloat = 26

    /// A capsule the height of a menu-bar item, not of a toolbar.
    static let barHeight: CGFloat = 36

    /// The widest the bar ever gets — an error carrying a message and two
    /// actions. Every other state is far narrower.
    static let maximumBarWidth: CGFloat = 380

    @AppStorage(ZenAppearance.storageKey)
    private var appearance = ZenAppearance.system.rawValue
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @ObservedObject var state: AppState
    let toggleRecording: () -> Void
    let cancelRecording: () -> Void
    let finishRecording: () -> Void
    let dismissError: () -> Void
    let setMode: (ZenBarMode) -> Void
    let cancelAgenticGoal: () -> Void

    /// Whether the pointer is over the bar. Drives the control reveal.
    @State private var hovering = false

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
            // Identity changes on the *content* only. The container keeps its
            // own, so the bar's width and background morph between phases while
            // the contents cross-fade. Putting `.id` on the whole bar — as this
            // once did — destroyed and rebuilt it instead, which is why every
            // state change read as a hard cut.
            content
                .id(state.phase.label)
                .transition(.opacity)
        }
        .frame(width: barWidth, height: Self.barHeight)
        .background(barBackground)
        .clipShape(barShape)
        .contentShape(barShape)
        .onHover { isInside in
            hovering = isInside
        }
        .animation(ZenDesign.Motion.standard(reduceMotion), value: state.phase)
        .animation(ZenDesign.Motion.standard(reduceMotion), value: hovering)
        // The width morph gets the *momentum* spring while the contents get the
        // critically damped one. The bar changing size is the one moment this
        // interface behaves like a physical object, and a few percent of
        // overshoot on the geometry — with none on the text riding inside it —
        // is what makes the change read as elastic rather than as a window
        // being programmatically resized.
        .animation(ZenDesign.Motion.momentum(reduceMotion), value: barWidth)
        .accessibilityElement(children: .contain)
    }

    /// A true capsule, derived from the height rather than set by hand, so the
    /// two can never drift apart. At 36pt tall this is what makes the bar read
    /// as an object hovering over the desktop instead of a panel docked to it.
    private var barShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: Self.barHeight / 2,
            style: .continuous
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
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
                "transcribing",
                tint: ZenDesign.Semantic.accent
            )
        case .awaitingCloudReview:
            reviewContent
        case .inserting:
            workingContent(
                "inserting",
                tint: ZenDesign.Semantic.success
            )
        case .success:
            successContent
        case .error(let message):
            errorContent(message)
        }
    }

    /// At rest: a flat waveform. That is the whole idle interface.
    ///
    /// Hovering widens the bar and reveals the mode switcher and the shortcut,
    /// so the two things a user might want to check are one pointer-move away
    /// rather than permanently occupying the screen.
    private var idleContent: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 10) {
                BrandLogo(size: 16)

                WaveformView(model: state.audioLevel, barCount: 14)
                    // Dimmed, not hidden. A flat waveform at reading contrast
                    // looks like a broken meter; at this opacity it reads as
                    // the instrument being idle.
                    .opacity(0.4)

                if hovering {
                    hairline
                    modeSwitcher
                    ZenKbdGroup(combo: HotKeyPreferences.load().displayName)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressableStyle())
        .accessibilityLabel("Start ZenVoice \(state.mode.displayName)")
        .accessibilityHint(
            "Press \(HotKeyPreferences.load().displayName) or activate this button."
        )
    }

    /// While listening the waveform *is* the interface — it is the only thing
    /// on screen that proves the microphone is hearing anything.
    private var listeningContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ZenDesign.Semantic.accent)
                .frame(width: 7, height: 7)

            WaveformView(model: state.audioLevel, barCount: 20)

            if !state.liveTranscriptPreview.isEmpty {
                Text(state.liveTranscriptPreview)
                    .font(.system(size: 11))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if hovering {
                hairline
                // Icons, not labels. "Cancel" and "Finish" as words cost 90pt
                // of a bar this size, and both already have a keyboard route —
                // the shortcut finishes, and this is the fallback for a pointer.
                barIconButton(
                    "xmark",
                    label: "Cancel dictation",
                    action: cancelRecording
                )
                barIconButton(
                    "checkmark",
                    label: "Finish dictation",
                    tint: ZenDesign.Semantic.accent,
                    action: finishRecording
                )
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("ZenVoice is listening")
    }

    /// Decoding and inserting: a pulsing dot and one lowercase word.
    ///
    /// These used to be a status label stacked over a travelling progress
    /// hairline, which needed a 44pt bar to hold. In a capsule this size the
    /// pulse carries the same message — *still going* — in a fifth of the room.
    private func workingContent(_ label: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            ZenStatusLabel(text: label, tint: tint, pulses: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(label)
    }

    /// The review panel does not take focus, so without this the bar sat on
    /// "transcribing…" while nothing was happening and the shortcut appeared to
    /// have died. Says what it is waiting for and how to get out of it.
    private var reviewContent: some View {
        HStack(spacing: 8) {
            ZenStatusLabel(
                text: "review cloud text",
                tint: ZenDesign.Semantic.accent
            )
            Text("· shortcut keeps local")
                .font(.system(size: 11))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(
            "Waiting for your cloud review. Press your dictation shortcut to "
            + "keep the local text."
        )
    }

    private var successContent: some View {
        HStack(spacing: 8) {
            if let warning = state.lastDecodeWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.warn)
                Text("inserted — \(warning)")
                    .font(.system(size: 11))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.success)
                Text(successMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(
            state.lastDecodeWarning.map { "Inserted, but \($0)" } ?? "Inserted"
        )
    }

    /// The one state whose controls are *not* hidden behind hover.
    ///
    /// Everything else here can be resolved by pressing the shortcut again. An
    /// error cannot: the user has to be told what happened and given a way out,
    /// and hiding that behind a pointer-move would be hiding the only thing on
    /// screen that still needs a decision.
    private func errorContent(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.danger)
            Text(displayedError(message))
                .font(.system(size: 11))
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            barIconButton(
                "arrow.clockwise",
                label: "Try again",
                tint: ZenDesign.Semantic.accent,
                action: toggleRecording
            )
            barIconButton(
                "xmark",
                label: "Dismiss",
                action: dismissError
            )
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
                state.isAgenticGoalActive
                    ? ZenDesign.Semantic.accent
                    : agenticEventTint(event)
            )

            Text(event.message)
                .font(.system(size: 11))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if state.isAgenticGoalActive {
                barIconButton(
                    "stop.fill",
                    label: "Stop agentic goal",
                    action: cancelAgenticGoal
                )
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, state.isAgenticGoalActive ? 6 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(
            "\(state.agenticGoalTitle ?? "Agentic goal"). \(event.message)"
        )
    }

    // MARK: - Parts

    private var hairline: some View {
        Rectangle()
            .fill(ZenDesign.Semantic.border)
            .frame(width: 1, height: 16)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    /// A 24pt round icon button — the only kind of button the bar has room for.
    private func barIconButton(
        _ systemImage: String,
        label: String,
        tint: Color = ZenDesign.Semantic.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background {

                    Circle().fill(ZenDesign.Semantic.textPrimary.opacity(0.09))
                }
                .contentShape(Circle())
        }
        .buttonStyle(ZenPressableStyle())
        .transition(.opacity)
        .accessibilityLabel(label)
        .help(label)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(ZenBarMode.allCases, id: \.self) { mode in
                let isSelected = state.mode == mode
                Button {
                    setMode(mode)
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(

                            isSelected
                                ? ZenDesign.Semantic.accent
                                : ZenDesign.Semantic.textTertiary
                        )
                        .frame(width: 24, height: 24)
                        .background {
                            Circle()
                                .fill(
                                    isSelected
                                        ? ZenDesign.Semantic.accentMuted
                                        : Color.clear
                                )
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(ZenPressableStyle())
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .transition(.opacity)
    }

    // MARK: - Geometry

    /// Every width is the smallest that holds its own contents.
    ///
    /// The old set started at 310 and ran to 560. These start at 96 — about the
    /// width of a word — because at rest the bar has nothing to say.
    private var barWidth: CGFloat {
        switch state.phase {
        case .idle:
            if state.agenticStatusEvent != nil {
                return state.isAgenticGoalActive ? 300 : 268
            }
            // 108 holds the mark and a fourteen-bar meter and nothing else.
            // Hovering adds the hairline, the three modes and the shortcut.
            return hovering ? 300 : 108
        case .listening:
            let base: CGFloat = state.liveTranscriptPreview.isEmpty ? 132 : 288
            // The reveal adds two 24pt buttons and the rule between them.
            return hovering ? base + 88 : base
        case .transcribing, .inserting:
            return 148
        case .awaitingCloudReview:
            return 268
        case .success:
            return state.lastDecodeWarning == nil ? 190 : 320
        case .error:
            return 380
        }
    }

    // MARK: - Material

    /// The bar reads as a piece of glass hovering over whatever the user is
    /// working in, not as a panel docked to the screen.
    ///
    /// It used to be a 96%-opaque rectangle with a hard border on all four
    /// sides — which is to say, opaque. At that alpha the material was doing no
    /// work. A real material samples what is behind it, so the bar picks up the
    /// colour of the window it is floating over and stays legible on both a
    /// white document and a dark terminal.
    private var barBackground: some View {
        barShape
            .fill(.ultraThinMaterial)
            // A thin scrim over the material. The material alone is too
            // transparent to carry small text over a busy window; this settles
            // it just enough without going back to being a solid fill.
            .overlay {
                barShape.fill(ZenDesign.Semantic.surface.opacity(0.55))
            }
            .overlay {
                barShape.strokeBorder(ZenDesign.Semantic.border, lineWidth: 1)
            }
            // The lit top lip, the same treatment every raised surface in the
            // app carries — and the reason this looks like an object with a
            // thickness rather than a rounded rectangle.
            .overlay {
                barShape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.02),
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
            .shadow(color: Color.black.opacity(0.14), radius: 3, y: 1)
    }

    // MARK: - Text

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
        return "\(summary.wordCount) words · \(summary.wordsPerMinute) wpm"
    }

    private func displayedError(_ message: String) -> String {
        if message.hasPrefix("Copied—") {
            let reason = String(message.dropFirst("Copied—".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "Couldn’t insert — \(reason) Copied instead."
        }
        return message
    }
}

/// The level meter.
///
/// Observes ``AudioLevelModel`` rather than ``AppState`` so that a level
/// arriving fifteen times a second repaints these bars and nothing else.
///
/// The history is kept here rather than in the model because it is a property
/// of the drawing, not of the audio: the recorder reports a level, and what a
/// trailing window of levels should look like is this view's business.
struct WaveformView: View {
    @ObservedObject var model: AudioLevelModel
    /// How many samples the trail holds.
    ///
    /// A parameter rather than a constant because the meter now appears at two
    /// very different scales: 14 bars inside a 36pt capsule, 23 on a settings
    /// card. One count sized for the card overflowed the capsule; one sized for
    /// the capsule looked like a stub on the card.
    let barCount: Int

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private static let barWidth: CGFloat = 2
    private static let barSpacing: CGFloat = 2
    private static let maximumHeight: CGFloat = 16
    private static let minimumHeight: CGFloat = 2

    @State private var history: [Double]

    init(model: AudioLevelModel, barCount: Int = 23) {
        self.model = model
        self.barCount = barCount
        _history = State(
            initialValue: [Double](repeating: 0, count: barCount)
        )
    }

    private var width: CGFloat {
        CGFloat(barCount) * Self.barWidth
            + CGFloat(barCount - 1) * Self.barSpacing
    }

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
        // Older samples fade out at the leading edge instead of ending on a
        // hard vertical line. The trail is a *history*, and history should
        // dissolve — a sharp left edge reads as the graphic being clipped by
        // its container.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.22),
                    .init(color: .black, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        // Capsules are centre-aligned in the row, so a bar of height h extends
        // equally above and below the midline. That mirrored shape is what
        // reads as a voice rather than as a graphic equaliser.
        .frame(width: width, height: Self.maximumHeight)
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
        let age = Double(index) / Double(max(1, barCount - 1))
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
///
/// No longer used by the ZenBar, which says the same thing with a pulsing dot
/// in a fifth of the space; the live-preview overlays, which are large enough
/// to hold it, still do.
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
