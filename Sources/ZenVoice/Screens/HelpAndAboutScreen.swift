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

/// Phase 6 consolidated Help & About surface.
///
/// Help, the setup guide, and update settings are support content, not daily
/// controls. They share one screen so top-level navigation stays focused on
/// things the user changes while dictating.
struct HelpAndAboutScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var updatesViewModel: UpdatesViewModel
    @ObservedObject var onboardingViewModel: OnboardingViewModel
    let openShortcuts: () -> Void

    private enum Tab: String, CaseIterable, Identifiable {
        case help, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .help:
                return "Help"
            case .about:
                return "About"
            }
        }
    }

    @State private var selection: Tab = .help

    var body: some View {
        ZenScreen(
            icon: "questionmark.circle.fill",
            title: "Help & About",
            subtitle:
                "Short answers, and what you are running.",
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
            case .help:
                HelpScreen(
                    viewModel: viewModel,
                    onboardingViewModel: onboardingViewModel,
                    openShortcuts: openShortcuts
                )
            case .about:
                UpdatesScreen(
                    viewModel: updatesViewModel
                )
            }
        }
    }
}
