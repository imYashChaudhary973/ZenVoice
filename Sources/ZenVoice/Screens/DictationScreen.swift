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

/// Phase 6 consolidated Dictation surface.
///
/// Shortcut, audio, and overlay were three separate navigation entries that all
/// configure the same act: pressing the key and speaking. They now share one
/// screen with tabs.
struct DictationScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    private enum Tab: String, CaseIterable, Identifiable {
        case shortcut, audio, overlay

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shortcut:
                return "Shortcut"
            case .audio:
                return "Audio"
            case .overlay:
                return "Overlay"
            }
        }
    }

    @State private var selection: Tab = .shortcut

    var body: some View {
        ZenScreen(
            icon: "waveform",
            title: "Dictation",
            subtitle:
                "The shortcut you press, the microphone it listens to, and "
                + "what you see while you speak.",
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
            case .shortcut:
                ShortcutsScreen(viewModel: viewModel)
            case .audio:
                AudioScreen(viewModel: viewModel)
            case .overlay:
                OverlayScreen(viewModel: viewModel)
            }
        }
    }
}
