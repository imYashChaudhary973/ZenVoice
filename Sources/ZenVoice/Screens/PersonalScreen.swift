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
import ZenVoiceStorage

/// Phase 6 consolidated Personal surface.
///
/// Formatting and vocabulary share one screen because they both change how
/// spoken words become text. Per-app rules used to live here and have been
/// removed.
struct PersonalScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var cloudAIViewModel: CloudAIViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel

    private enum Tab: String, CaseIterable, Identifiable {
        case formatting, vocabulary

        var id: String { rawValue }

        var title: String {
            switch self {
            case .formatting:
                return "Formatting"
            case .vocabulary:
                return "Vocabulary"
            }
        }
    }

    @State private var selection: Tab = .formatting

    var body: some View {
        ZenScreen(
            icon: "text.badge.star",
            title: "Personalisation",
            subtitle: "Formatting and vocabulary.",
            tabs: {
                ZenTabStrip(
                    items: Tab.allCases.map { tab in
                        .init(tab: tab, title: tab.title)
                    },
                    selection: $selection
                )
            }
        ) {
            switch selection {
            case .formatting:
                FormattingScreen(
                    viewModel: viewModel,
                    cloudAIViewModel: cloudAIViewModel,
                    voiceProfileViewModel: voiceProfileViewModel
                )
            case .vocabulary:
                VoiceProfileScreen(viewModel: voiceProfileViewModel)
            }
        }
    }
}
