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

/// Phase 6 consolidated screens — temporary placeholders so the new nine-entry
/// navigation compiles while each screen is rebuilt against the new design
/// system. Each placeholder will be replaced by a proper combined view in the
/// screen-rebuild pass.

struct PersonalScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel
    @ObservedObject var applicationProfileViewModel: ApplicationProfileViewModel

    var body: some View {
        ZenScreen(
            title: "Personal",
            subtitle: "Your words and per-app rules."
        ) {
            YourWordsScreen(viewModel: voiceProfileViewModel)
            PerAppRulesScreen(
                viewModel: viewModel,
                applicationProfileViewModel: applicationProfileViewModel
            )
        }
    }
}

private struct YourWordsScreen: View {
    @ObservedObject var viewModel: VoiceProfileViewModel

    var body: some View {
        VoiceProfileScreen(viewModel: viewModel)
    }
}

private struct PerAppRulesScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var applicationProfileViewModel: ApplicationProfileViewModel

    var body: some View {
        AppProfilesScreen(
            viewModel: viewModel,
            applicationProfileViewModel: applicationProfileViewModel
        )
    }
}

struct HelpAndAboutScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var updatesViewModel: UpdatesViewModel
    @ObservedObject var onboardingViewModel: OnboardingViewModel
    let openShortcuts: () -> Void

    var body: some View {
        ZenScreen(
            title: "Help & About",
            subtitle: "Frequently asked questions, setup guide, and updates."
        ) {
            HelpScreen(
                viewModel: viewModel,
                onboardingViewModel: onboardingViewModel,
                openShortcuts: openShortcuts
            )
            UpdatesScreen(viewModel: updatesViewModel)
        }
    }
}
