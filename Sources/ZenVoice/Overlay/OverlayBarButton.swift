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

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(
                    emphasized
                        ? ZenDesign.Semantic.textOnAccent
                        : ZenDesign.Semantic.textSecondary
                )
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background {
                    // The emphasised button is *filled*, not tinted. On the
                    // bar's translucent material a 13%-alpha wash behind accent
                    // text is barely a shape at all, so the one action the user
                    // is meant to take looked identical to the one that cancels
                    // it. A solid fill is also the only version that survives
                    // the bar sitting over an arbitrary window.
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.barControl,
                        style: .continuous
                    )
                    .fill(
                        emphasized
                            ? ZenDesign.Semantic.accentFill
                            : ZenDesign.Semantic.textPrimary
                                .opacity(hovering ? 0.10 : 0)
                    )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressableStyle())
        .onHover { hovering = $0 }
        .animation(ZenDesign.Motion.fast(reduceMotion), value: hovering)
        .accessibilityLabel(title)
    }
}
