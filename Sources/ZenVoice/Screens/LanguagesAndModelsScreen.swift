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

/// Language and model choices live in one scrollable setup page.
struct LanguagesAndModelsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var modelManagerViewModel: ModelManagerViewModel

    var body: some View {
        ZenScreen(
            icon: "globe",
            title: "Languages & Models",
            subtitle:
                "What you speak, and the on-device engines that understand it."
        ) {
            LanguagesScreen(viewModel: viewModel)
            ModelsScreen(viewModel: modelManagerViewModel)
        }
    }
}
