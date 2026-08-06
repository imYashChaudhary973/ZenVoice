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

/// Phase 6 single formatting surface.
///
/// Replaces the overlapping Instant Refine and ZenIntelligence screens with
/// one ladder: Off → Clean → Smart → Cloud. Cloud provider configuration is
/// included here rather than as a separate navigation entry.
struct FormattingScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var cloudAIViewModel: CloudAIViewModel

    @AppStorage(TranscriptFormattingPreferences.preferenceKey)
    private var modeRawValue = TranscriptFormattingMode.clean.rawValue

    private var mode: TranscriptFormattingMode {
        TranscriptFormattingMode(rawValue: modeRawValue) ?? .clean
    }

    var body: some View {
        ZenScreen(
            title: "Formatting",
            subtitle: "How ZenVoice shapes your words after it hears them."
        ) {
            ZenSection(title: "Formatting ladder") {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: ZenDesign.Spacing.sm),
                        GridItem(.flexible(), spacing: ZenDesign.Spacing.sm)
                    ],
                    spacing: ZenDesign.Spacing.sm
                ) {
                    ForEach(TranscriptFormattingMode.allCases) { mode in
                        ZenChoiceCard(
                            title: mode.displayName,
                            detail: mode.detail,
                            selected: self.mode == mode,
                            titleIcon: icon(for: mode)
                        ) {
                            modeRawValue = mode.rawValue
                        }
                    }
                }
            }

            if mode == .cloud {
                ZenSection(title: "Cloud provider") {
                    CloudAIScreen(viewModel: cloudAIViewModel)
                }
            }

            if mode != .cloud {
                ZenBanner(
                    kind: .info,
                    icon: "hand.raised",
                    text:
                        "All formatting rungs below Cloud keep your transcript "
                        + "on this Mac. No text is sent to a server."
                )
            }
        }
    }

    private func icon(for mode: TranscriptFormattingMode) -> String {
        switch mode {
        case .off:
            return "power"
        case .clean:
            return "wand.and.stars"
        case .smart:
            return "sparkles"
        case .cloud:
            return "cloud"
        }
    }
}

extension TranscriptFormattingMode: Identifiable {
    public var id: String { rawValue }
}
