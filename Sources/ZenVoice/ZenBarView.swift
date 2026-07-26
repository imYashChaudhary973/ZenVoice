import SwiftUI

struct ZenBarView: View {
    @AppStorage("zenvoice.appearance")
    private var appearance = "light"
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @ObservedObject var state: AppState
    let toggleRecording: () -> Void
    let cancelRecording: () -> Void
    let finishRecording: () -> Void
    let dismissError: () -> Void

    var body: some View {
        ZStack {
            controlBar
        }
        .frame(width: barWidth, height: 44)
        .background(barBackground)
        .clipShape(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .id(state.phase.label)
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.985))
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.20),
            value: state.phase
        )
        .preferredColorScheme(appearance == "dark" ? .dark : .light)
        .accessibilityElement(children: .contain)
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
                    Text("⌃⌥ Space")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(barSecondary)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ZenDesign.Semantic.surfaceRaised)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(barBorder)
                                }
                        }
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
                Circle()
                    .fill(barAccent)
                    .frame(width: 6, height: 6)
                    .shadow(color: barAccent.opacity(0.55), radius: 4)
                    .accessibilityHidden(true)

                WaveformView(samples: state.audioSamples)
                    .frame(width: 92, height: 20)

                Spacer()
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
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(barAccent)
                Text("Refining…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(barPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .inserting:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(barAccent)
                Text("Inserting…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(barPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .success:
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(barSuccess)
                Text(successMessage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(barPrimary)
                    .lineLimit(1)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(successMessage)

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
            return 310
        case .listening:
            return 350
        case .transcribing, .inserting:
            return 310
        case .success:
            return 420
        case .error:
            return 530
        }
    }

    private var barBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(barPanel)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(barBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 18, y: 8)
    }

    private var successMessage: String {
        guard let summary = state.lastInsertionSummary else {
            return "Inserted with ZenVoice"
        }
        return "Inserted with ZenVoice · \(summary.wordCount) words · \(summary.wordsPerMinute) WPM"
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
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
        } else {
            Image(systemName: "waveform")
                .resizable()
                .foregroundStyle(barAccent)
                .frame(width: size, height: size)
        }
    }

    private var barPanel: Color {
        ZenDesign.Semantic.surface.opacity(0.98)
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

private struct WaveformView: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    let samples: [Double]
    private let visualProfile = [
        0.52, 0.72, 0.88, 0.66, 1.00, 0.78, 0.94,
        0.70, 1.00, 0.64, 0.86, 0.70, 0.50
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                let profile = visualProfile[
                    min(index, visualProfile.count - 1)
                ]
                Capsule()
                    .fill(
                        ZenDesign.Semantic.accent
                        .opacity(sample > 0.035 ? 0.98 : 0.30)
                    )
                    .frame(
                        width: 2,
                        height: max(2, 2 + (16 * sample * profile))
                    )
            }
        }
        .frame(maxHeight: .infinity)
        .animation(
            reduceMotion ? nil : .linear(duration: 0.055),
            value: samples
        )
        .accessibilityHidden(true)
    }
}
