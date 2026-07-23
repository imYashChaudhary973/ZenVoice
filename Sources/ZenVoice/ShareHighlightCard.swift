import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZenVoiceCore

@MainActor
enum ShareHighlightCardRenderer {
    static let size = CGSize(width: 1_200, height: 630)

    static func image(for summary: ShareCardSummary) -> NSImage? {
        let renderer = ImageRenderer(
            content: ShareHighlightCard(summary: summary)
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        return renderer.nsImage
    }

    static func pngData(for summary: ShareCardSummary) -> Data? {
        guard let image = image(for: summary),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor
struct ShareHighlightSheet: View {
    let summary: ShareCardSummary
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share your highlights")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        "Preview the exact image. Transcripts and app names are excluded."
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                Spacer()
                Button("Done", action: dismiss.callAsFunction)
                    .buttonStyle(ZenSecondaryButtonStyle())
            }

            ShareHighlightCard(summary: summary)
                .frame(
                    width: ShareHighlightCardRenderer.size.width,
                    height: ShareHighlightCardRenderer.size.height
                )
                .scaleEffect(0.45, anchor: .topLeading)
                .frame(width: 540, height: 284, alignment: .topLeading)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.medium,
                        style: .continuous
                    )
                    .strokeBorder(
                        ZenDesign.Semantic.borderStrong,
                        lineWidth: 1
                    )
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.danger)
            } else if let savedMessage {
                Text(savedMessage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.success)
            }

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(ZenDesign.Semantic.success)
                    Text("Rendered locally • No automatic upload")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                Spacer()
                Button("Save PNG", action: savePNG)
                    .buttonStyle(ZenSecondaryButtonStyle())
                Button("Share…", action: share)
                    .buttonStyle(ZenPrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 588)
        .background(ZenDesign.Semantic.canvas)
    }

    private func savePNG() {
        guard let data = ShareHighlightCardRenderer.pngData(
            for: summary
        ) else {
            errorMessage = "ZenVoice could not render the highlight image."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ZenVoice-Highlights.png"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            errorMessage = nil
            savedMessage = "Saved \(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func share() {
        guard let image = ShareHighlightCardRenderer.image(
            for: summary
        ),
              let view = NSApp.keyWindow?.contentView else {
            errorMessage = "ZenVoice could not open the macOS Share menu."
            return
        }
        errorMessage = nil
        let picker = NSSharingServicePicker(items: [image])
        picker.show(
            relativeTo: view.bounds,
            of: view,
            preferredEdge: .maxY
        )
    }
}

private struct ShareHighlightCard: View {
    let summary: ShareCardSummary

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.027, blue: 0.033),
                    Color(red: 0.07, green: 0.06, blue: 0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(ZenDesign.Semantic.accent.opacity(0.12))
                .frame(width: 430, height: 430)
                .blur(radius: 12)
                .offset(x: 470, y: -240)

            VStack(alignment: .leading, spacing: 42) {
                HStack(spacing: 18) {
                    if let logo = BrandAssets.zenLogo {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 18,
                                    style: .continuous
                                )
                            )
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ZENVOICE")
                            .font(.system(size: 15, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(ZenDesign.Semantic.accent)
                        Text("My on-device dictation highlights")
                            .font(
                                .system(
                                    size: 34,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(Color.white)
                    }
                    Spacer()
                }

                HStack(spacing: 18) {
                    shareMetric(
                        value: summary.totalWordCount.formatted(),
                        label: "WORDS DICTATED"
                    )
                    shareMetric(
                        value: "\(summary.weightedWordsPerMinute)",
                        label: "AVERAGE WPM"
                    )
                    shareMetric(
                        value: "\(summary.currentStreakDays)",
                        label: "DAY STREAK"
                    )
                    shareMetric(
                        value: "\(summary.distinctApplicationCount)",
                        label: "APPS USED"
                    )
                }

                HStack {
                    Label(
                        "Private by design. Processed locally on Mac.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    Spacer()
                    Text("zenvoice")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(ZenDesign.Semantic.accent)
                }
            }
            .padding(58)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "ZenVoice highlights: \(summary.totalWordCount) words, "
                + "\(summary.weightedWordsPerMinute) words per minute, "
                + "\(summary.currentStreakDays) day streak, "
                + "\(summary.distinctApplicationCount) apps."
        )
    }

    private func shareMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value)
                .font(
                    .system(
                        size: 42,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.46))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
    }
}
