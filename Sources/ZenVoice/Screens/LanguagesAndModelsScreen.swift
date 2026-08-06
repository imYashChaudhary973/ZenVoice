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

/// Phase 6 consolidated Languages & Models surface.
///
/// Languages you speak and the engines that understand them are configured
/// together, because engine choice depends on the active language profile.
struct LanguagesAndModelsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel

    private enum Tab: String, CaseIterable, Identifiable {
        case languages, models

        var id: String { rawValue }

        var title: String {
            switch self {
            case .languages:
                return "Languages"
            case .models:
                return "Models"
            }
        }
    }

    @State private var selection: Tab = .languages

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZenTabStrip(
                items: Tab.allCases.map { tab in
                    .init(tab: tab, title: tab.title)
                },
                selection: $selection
            )
            .padding(.horizontal, 32)
            .padding(.top, 24)

            switch selection {
            case .languages:
                LanguagesScreen(viewModel: viewModel)
            case .models:
                ModelsScreen(viewModel: modelManagerViewModel)
            }
        }
        .background(ZenDesign.Semantic.canvas)
    }
}
