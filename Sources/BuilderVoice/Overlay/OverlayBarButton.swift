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

/// Reusable overlay button used by ZenBar and live-preview overlays.
struct OverlayBarButton: View {
    let title: String
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: emphasized ? .semibold : .medium))
                .foregroundStyle(emphasized ? ZenDesign.Semantic.accent : ZenDesign.Semantic.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
                .frame(minHeight: ZenDesign.Layout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(
            ZenPressButtonStyle(cornerRadius: ZenDesign.Radius.barControl)
        )
        .accessibilityLabel(title)
    }
}

/// Circular outline control used by the compact recording HUD.
///
/// The listening bar is a single drawing: two stroked circles and a
/// voiceprint. Labels do not fit that silhouette, so the action is the icon
/// and VoiceOver / the tooltip carry the name.
struct OverlayCircleButton: View {
    let systemImage: String
    let label: String
    var tint: Color = ZenDesign.Semantic.textPrimary
    let action: () -> Void

    @State private var hovering = false

    private static let visualSize: CGFloat = 28
    private static let lineWidth: CGFloat = 1.4

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.visualSize, height: Self.visualSize)
                .background {
                    Circle()
                        .fill(tint.opacity(hovering ? 0.10 : 0))
                }
                .overlay {
                    Circle()
                        .strokeBorder(tint, lineWidth: Self.lineWidth)
                }
                .contentShape(Circle())
        }
        .buttonStyle(
            ZenPressButtonStyle(cornerRadius: Self.visualSize / 2)
        )
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
