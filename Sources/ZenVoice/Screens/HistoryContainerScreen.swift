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

/// Phase 6 consolidated History surface.
///
/// Dictation transcripts, retained audio, and usage insights are tabs of the
/// same view because they are all views of the same local data.
struct HistoryContainerScreen: View {
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var audioHistoryViewModel: AudioHistoryViewModel
    @ObservedObject var insightsViewModel: InsightsViewModel
    @ObservedObject var meetingViewModel: MeetingViewModel
    @ObservedObject var meetingMCPController: MeetingMCPController

    @ObservedObject var cloudAIViewModel: CloudAIViewModel

    private enum Tab: String, CaseIterable, Identifiable {
        case dictations, meetings, audio, insights

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dictations:
                return "Dictations"
            case .meetings:
                return "Meetings"
            case .audio:
                return "Audio"
            case .insights:
                return "Insights"
            }
        }
    }

    @State private var selection: Tab = .dictations

    var body: some View {
        ZenScreen(
            icon: "clock.fill",
            title: "History",
            subtitle:
                "Dictations, meetings, recordings, and statistics — kept on this Mac.",
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
            case .dictations:
                HistoryScreen(viewModel: historyViewModel)
            case .meetings:
                MeetingsScreen(
                    viewModel: meetingViewModel,
                    cloudAIViewModel: cloudAIViewModel,
                    mcpController: meetingMCPController
                )
            case .audio:
                AudioHistoryScreen(viewModel: audioHistoryViewModel)
            case .insights:
                InsightsScreen(viewModel: insightsViewModel)
            }
        }
    }
}
