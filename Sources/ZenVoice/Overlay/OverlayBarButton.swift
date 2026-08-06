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
}
