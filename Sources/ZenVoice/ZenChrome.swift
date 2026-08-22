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

// MARK: - Window chrome
// The shell around every screen: functional material, native toolbar chrome,
// and the icon chip that heads each preference group.

/// AppKit material hosted inside SwiftUI.
struct ZenVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        // ZenVoice frequently loses key status while dictating into another
        // app. Keeping the material active avoids a distracting value jump.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// A functional material layer with a solid accessibility fallback.
///
/// Materials communicate hierarchy in the sidebar and floating chrome. They
/// are not used as decoration on every card. Reduce Transparency swaps the
/// effect for the same graphite fallback, preserving both legibility and the
/// requested palette.
struct ZenMaterialSurface: View {
    var material: NSVisualEffectView.Material = .sidebar
    var tint: Color = ZenDesign.Semantic.sidebar.opacity(0.88)
    var fallback: Color = ZenDesign.Semantic.sidebar

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast)
    private var contrast

    var body: some View {
        ZStack {
            if reduceTransparency || contrast == .increased {
                fallback
            } else {
                ZenVisualEffect(material: material)
                tint
            }
        }
    }
}

/// Liquid Glass for floating controls on macOS 26 and newer, with the existing
/// material and solid accessibility fallback on older systems.
private struct ZenGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast)
    private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(tint?.opacity(0.18) ?? ZenDesign.Semantic.surface)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
        } else if #available(macOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    interactive
                        ? .regular.tint(tint).interactive()
                        : .regular.tint(tint),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content.glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
            }
        } else {
            content
                .background {
                    ZenMaterialSurface(
                        material: .popover,
                        tint: tint?.opacity(0.16)
                            ?? ZenDesign.Semantic.surface.opacity(0.82),
                        fallback: ZenDesign.Semantic.surface
                    )
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
        }
    }
}

extension View {
    func zenGlassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            ZenGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive
            )
        )
    }
}

struct ZenGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

/// Rounded-square tinted icon container that heads a card or a page.
struct ZenIconChip: View {
    let systemImage: String
    var size: CGFloat = 36
    var tint: Color = ZenDesign.Semantic.accent
    var background: Color?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                ZenKeycap(
                    kind: .muted,
                    cornerRadius: max(6, size * 0.22)
                )
            }
            .accessibilityHidden(true)
    }
}

/// Card or page heading: tinted icon chip, title, one line of subtitle.
struct ZenCardHeader<Trailing: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var titleFont: Font = ZenDesign.Typography.pageTitle
    var iconSize: CGFloat = 36
    var iconTint: Color = ZenDesign.Semantic.accent
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // The chip aligns to the *title row*, not to the title-plus-subtitle
        // block. Centring it against the whole block dropped it below the
        // title whenever a subtitle wrapped, and left two cards side by side
        // with their titles on different lines — the taller header pushed its
        // own title up while the shorter one stayed centred.
        HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
            ZenIconChip(
                systemImage: systemImage,
                size: iconSize,
                tint: iconTint
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: ZenDesign.Spacing.sm) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ZenDesign.Spacing.md)
                    trailing
                }
                // Pinned to the chip's height so every card's title sits on
                // the same line regardless of what is below it.
                .frame(minHeight: iconSize)

                if let subtitle {
                    Text(subtitle)
                        .font(ZenDesign.Typography.body)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension ZenCardHeader where Trailing == EmptyView {
    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        titleFont: Font = ZenDesign.Typography.pageTitle,
        iconSize: CGFloat = 36,
        iconTint: Color = ZenDesign.Semantic.accent
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            titleFont: titleFont,
            iconSize: iconSize,
            iconTint: iconTint,
            trailing: { EmptyView() }
        )
    }
}

/// Pins a SwiftUI control to the window titlebar's trailing edge.
///
/// Unified toolbars pack items after the title, so a search field never
/// reaches the right corner. AppKit's titlebar accessory does.
struct ZenTitlebarTrailing<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var accessory: NSTitlebarAccessoryViewController?
        var hosting: NSHostingView<AnyView>?
    }

    func makeNSView(context: Context) -> NSView {
        let probe = NSView(frame: .zero)
        probe.isHidden = true
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let root = AnyView(content())
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if let hosting = context.coordinator.hosting {
                hosting.rootView = root
                return
            }
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: 216, height: 36)
            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = .right
            accessory.view = hosting
            window.addTitlebarAccessoryViewController(accessory)
            context.coordinator.hosting = hosting
            context.coordinator.accessory = accessory
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.accessory?.removeFromParent()
        coordinator.accessory = nil
        coordinator.hosting = nil
    }
}
