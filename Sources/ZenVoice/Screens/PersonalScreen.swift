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
    @ObservedObject var cloudAIViewModel: CloudAIViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel
    @ObservedObject var applicationProfileViewModel: ApplicationProfileViewModel

    private enum Tab: String, CaseIterable, Identifiable {
        case formatting, vocabulary, appRules, commands

        var id: String { rawValue }

        var title: String {
            switch self {
            case .formatting:
                return "Formatting"
            case .vocabulary:
                return "Vocabulary"
            case .appRules:
                return "App Rules"
            case .commands:
                return "Commands"
            }
        }
    }

    @State private var selection: Tab = .formatting

    var body: some View {
        ZenScreen(
            icon: "text.badge.star",
            title: "Personalisation",
            subtitle:
                "Control formatting, remembered words, per-app behavior, "
                + "and voice commands.",
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
            case .appRules:
                AppProfilesScreen(
                    viewModel: viewModel,
                    applicationProfileViewModel: applicationProfileViewModel
                )
            case .commands:
                CommandsScreen(viewModel: viewModel)
            }
        }
    }
}
