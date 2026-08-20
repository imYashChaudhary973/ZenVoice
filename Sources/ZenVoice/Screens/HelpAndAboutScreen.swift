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

/// Help and product information share one continuous support page.
struct HelpAndAboutScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var updatesViewModel: UpdatesViewModel
    @ObservedObject var onboardingViewModel: OnboardingViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var voiceProfileViewModel: VoiceProfileViewModel
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel
    let openModels: () -> Void
    let openShortcuts: () -> Void

    var body: some View {
        ZenScreen(
            icon: "gearshape",
            title: "Settings",
            subtitle: "Privacy, permissions, updates, and support."
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.xxl) {
                PrivacyScreen(
                    viewModel: viewModel,
                    historyViewModel: historyViewModel,
                    voiceProfileViewModel: voiceProfileViewModel,
                    modelManagerViewModel: modelManagerViewModel,
                    openModels: openModels,
                    embedded: true
                )
                HelpScreen(
                    viewModel: viewModel,
                    onboardingViewModel: onboardingViewModel,
                    openShortcuts: openShortcuts
                )
                UpdatesScreen(viewModel: updatesViewModel)
            }
        }
    }
}
