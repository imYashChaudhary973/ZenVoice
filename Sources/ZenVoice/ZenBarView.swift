import SwiftUI

struct ZenBarView: View {
    @ObservedObject var state: AppState
    let toggleRecording: () -> Void
    let cancelRecording: () -> Void
    let finishRecording: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(messageBackground)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .accessibilityLabel(statusMessage)
            }

            controlBar
        }
        .frame(width: 210, height: 78, alignment: .bottom)
        .animation(.easeOut(duration: 0.16), value: state.phase)
        .animation(.easeOut(duration: 0.16), value: state.showsStatusMessage)
    }

    @ViewBuilder
    private var controlBar: some View {
        switch state.phase {
        case .idle:
            Button(action: toggleRecording) {
                HStack(spacing: 6) {
                    brandLogo(size: 20)
                    Text("ZenVoice")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: 88, height: 30)
                .background(barBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start ZenVoice dictation")
            .accessibilityHint("Press Control Option Space or activate this button.")

        case .listening:
            HStack(spacing: 5) {
                Button(action: cancelRecording) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.16))
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel dictation")

                WaveformView(samples: state.audioSamples)
                    .frame(width: 56, height: 18)

                Button(action: finishRecording) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.82))
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Finish dictation and insert text")
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(barBackground)

        case .transcribing, .inserting:
            HStack(spacing: 7) {
                brandLogo(size: 19)
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
                Text(state.phase == .transcribing ? "Transcribing" : "Inserting")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(barBackground)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(state.phase.label)

        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.40, green: 0.88, blue: 0.55))
                Text("Done")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(barBackground)

        case .error:
            Button(action: toggleRecording) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.43, blue: 0.43))
                    Text("Try again")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(barBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Try dictation again")
        }
    }

    private var statusMessage: String? {
        switch state.phase {
        case .idle:
            return nil
        case .listening:
            return state.showsStatusMessage ? "Dictating with ZenVoice" : nil
        case .transcribing:
            return state.showsStatusMessage ? "Transcribing locally" : nil
        case .inserting:
            return state.showsStatusMessage ? "Inserting with ZenVoice" : nil
        case .success:
            return state.showsStatusMessage ? "Inserted with ZenVoice" : nil
        case .error(let message):
            return message
        }
    }

    private var barBackground: some View {
        Capsule()
            .fill(Color(red: 0.045, green: 0.048, blue: 0.058).opacity(0.98))
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.30), radius: 8, y: 3)
    }

    private var messageBackground: some View {
        Capsule()
            .fill(Color.black.opacity(0.96))
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.24), radius: 9, y: 3)
    }

    @ViewBuilder
    private func brandLogo(size: CGFloat) -> some View {
        if let logo = BrandAssets.zenLogo {
            Image(nsImage: logo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: "z.circle.fill")
                .resizable()
                .frame(width: size, height: size)
        }
    }
}

private struct WaveformView: View {
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
                    .fill(Color.white.opacity(sample > 0.035 ? 0.98 : 0.30))
                    .frame(
                        width: 2,
                        height: max(2, 2 + (16 * sample * profile))
                    )
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.linear(duration: 0.055), value: samples)
        .accessibilityHidden(true)
    }
}
