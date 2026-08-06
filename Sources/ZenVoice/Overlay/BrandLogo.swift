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

/// Reusable ZenVoice brand logo used by overlay views.
struct BrandLogo: View {
    let size: CGFloat

    var body: some View {
        if let logo = BrandAssets.zenLogo {
            Image(nsImage: logo)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                )
        } else {
            Image(systemName: "waveform")
                .resizable()
                .foregroundStyle(ZenDesign.Semantic.accent)
                .frame(width: size, height: size)
        }
    }
}
