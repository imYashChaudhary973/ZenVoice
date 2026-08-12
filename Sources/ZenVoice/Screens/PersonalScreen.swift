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
/// Your Words (vocabulary and corrections) and Per-App Rules (overrides by
/// application) are different concepts that were easy to confuse when they
/// shared the word "Profile". They now live under one clearly named screen.
struct PersonalScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel
    @ObservedObject var applicationProfileViewModel: ApplicationProfileViewModel

    private enum Tab: String, CaseIterable, Identifiable {
        case yourWords, perAppRules

        var id: String { rawValue }

        var title: String {
            switch self {
            case .yourWords:
                return "Your Words"
            case .perAppRules:
                return "Per-App Rules"
            }
        }
    }

    @State private var selection: Tab = .yourWords

    var body: some View {
        ZenScreen(
            icon: "character.book.closed.fill",
            title: "Personal",
            subtitle:
                "The words ZenVoice remembers for you, and the rules that "
                + "change per app.",
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
            case .yourWords:
                VoiceProfileScreen(viewModel: voiceProfileViewModel)
            case .perAppRules:
                AppProfilesScreen(
                    viewModel: viewModel,
                    applicationProfileViewModel: applicationProfileViewModel
                )
            }
        }
    }
}
