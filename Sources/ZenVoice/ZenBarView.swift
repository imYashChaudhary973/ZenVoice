import SwiftUI

struct ZenBarView: View {
    @ObservedObject var state: AppState
    let toggleRecording: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            stateIndicator
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.phase.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(helperText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if case .listening = state.phase {
                WaveformView(samples: state.audioSamples)
                    .frame(width: 63, height: 26)
            } else if state.phase == .transcribing || state.phase == .inserting {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Text("⌃⌥ Space")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 250, height: 54)
        .background {
            Capsule()
                .fill(Color(red: 0.075, green: 0.082, blue: 0.10).opacity(0.96))
                .overlay {
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 7)
        }
        .contentShape(Capsule())
        .onTapGesture {
            toggleRecording()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ZenVoice \(state.phase.label)")
        .accessibilityHint("Press Control Option Space, or click, to start or stop dictation.")
    }

    @ViewBuilder
    private var stateIndicator: some View {
        ZStack {
            Circle()
                .fill(indicatorColor.opacity(0.16))
                .overlay {
                    Circle()
                        .strokeBorder(indicatorColor.opacity(0.30), lineWidth: 1)
                }

            if let logo = BrandAssets.zenLogo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            } else {
                Text("Z")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(indicatorColor)
            }
        }
        .scaleEffect(state.phase == .listening ? 1.04 : 1)
        .animation(
            .easeInOut(duration: 0.65).repeatForever(autoreverses: true),
            value: state.phase == .listening
        )
    }

    private var helperText: String {
        switch state.phase {
        case .idle:
            return "Click or use the hotkey"
        case .listening:
            return "Press again to finish"
        case .transcribing:
            return "Audio stays on this Mac"
        case .inserting:
            return "Pasting into the active app"
        case .success:
            return "Your words are ready"
        case .error:
            return "Click to try again"
        }
    }

    private var indicatorColor: Color {
        switch state.phase {
        case .idle:
            return Color(red: 0.50, green: 0.55, blue: 0.64)
        case .listening:
            return Color(red: 0.36, green: 0.85, blue: 0.78)
        case .transcribing, .inserting:
            return Color(red: 0.52, green: 0.65, blue: 1.0)
        case .success:
            return Color(red: 0.40, green: 0.88, blue: 0.55)
        case .error:
            return Color(red: 1.0, green: 0.43, blue: 0.43)
        }
    }

    private var borderColor: Color {
        indicatorColor.opacity(state.phase == .idle ? 0.20 : 0.48)
    }
}

private struct WaveformView: View {
    let samples: [Double]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                Capsule()
                    .fill(Color.white.opacity(sample > 0.04 ? 0.94 : 0.28))
                    .frame(
                        width: 3,
                        height: max(3, 3 + (23 * sample))
                    )
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.linear(duration: 0.06), value: samples)
        .accessibilityHidden(true)
    }
}
