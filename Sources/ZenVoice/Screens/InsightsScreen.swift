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

private struct DisplayActivityDay: Identifiable {
    var id: Date { date }
    let date: Date
    let wordCount: Int
}

struct InsightsScreen: View {
    @ObservedObject var viewModel: InsightsViewModel
    @State private var showsShareCard = false

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            if let error = viewModel.errorMessage {
                ZenBanner(
                    kind: .danger,
                    icon: "exclamationmark.triangle",
                    text: error
                )
            }

            metrics
            activitySection

            HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
                appsSection
                categoriesSection
            }

            HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
                ZenBanner(
                    kind: .info,
                    icon: "lock",
                    text:
                        "Insights are calculated locally. ZenVoice stores app identity — never window titles, URLs, recipients, or surrounding text."
                )
                Button {
                    showsShareCard = true
                } label: {
                    Label(
                        "Share highlights",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(ZenSecondaryButtonStyle(height: 60))
            }
        }
        .onAppear(perform: viewModel.refresh)
        .sheet(isPresented: $showsShareCard) {
            ShareHighlightSheet(summary: shareSummary)
        }
    }

    // MARK: stat tiles

    private var metrics: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            ZenStatTile(
                value: viewModel.snapshot.totalWordCount.formatted(),
                label: "words dictated"
            )
            ZenStatTile(
                value:
                    "\(Int(viewModel.snapshot.weightedWordsPerMinute.rounded()))",
                label: "weighted WPM"
            )
            ZenStatTile(
                value:
                    "\(viewModel.snapshot.currentStreakDays) day"
                    + (viewModel.snapshot.currentStreakDays == 1 ? "" : "s"),
                label: "streak",
                detail: "best: \(viewModel.snapshot.longestStreakDays)"
            )
            ZenStatTile(
                value: viewModel.snapshot.dictationCount.formatted(),
                label: "dictations"
            )
        }
    }

    // MARK: words per day

    private var activitySection: some View {
        ZenSection(
            title: "Words per day",
            caption: busiestCaption
        ) {
            ZenPanel {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(displayedActivity) { day in
                        VStack(spacing: 6) {
                            RoundedRectangle(
                                cornerRadius: 4, style: .continuous
                            )
                            .fill(
                                day.wordCount == maxActivityWords
                                    && day.wordCount > 0
                                    ? ZenDesign.Semantic.accent
                                    : day.wordCount > 0
                                        ? ZenDesign.Semantic.accentMuted
                                        : ZenDesign.Semantic.surfaceRaised
                            )
                            .frame(
                                height: activityHeight(for: day.wordCount)
                            )
                            .frame(maxHeight: 96, alignment: .bottom)
                            .accessibilityLabel(
                                "\(day.date.formatted(.dateTime.weekday(.wide))): \(day.wordCount) words"
                            )
                            Text(
                                day.date.formatted(
                                    .dateTime.weekday(.abbreviated)
                                )
                                .lowercased()
                            )
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(ZenDesign.Spacing.md)
                .frame(height: 140, alignment: .bottom)
            }
        }
    }

    private var busiestCaption: String {
        guard
            let top = viewModel.snapshot.recentActivity
                .max(by: { $0.wordCount < $1.wordCount }),
            top.wordCount > 0
        else {
            return "\(viewModel.snapshot.dictationCount) dictations total"
        }
        return "Busiest: \(top.date.formatted(.dateTime.weekday(.wide))) · \(top.wordCount.formatted()) words"
    }

    // MARK: apps & categories

    private var appsSection: some View {
        ZenSection(title: "Where you dictate") {
            ZenPanel {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.snapshot.topApplications.isEmpty {
                        ZenRow(
                            icon: "app",
                            title: "No application context yet",
                            subtitle:
                                "ZenVoice remembers only the app name, never window titles or URLs."
                        )
                        .padding(.vertical, ZenDesign.Spacing.sm)
                    } else {
                        ForEach(
                            viewModel.snapshot.topApplications
                        ) { app in
                            ZenMeterRow(
                                label: app.displayName,
                                percent: percentOfWords(app.wordCount)
                            )
                        }
                        .padding(.horizontal, ZenDesign.Spacing.md)
                    }
                }
                .padding(.vertical, ZenDesign.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var categoriesSection: some View {
        ZenSection(title: "What kind of work") {
            ZenPanel {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.snapshot.categories.isEmpty {
                        ZenRow(
                            icon: "square.grid.2x2",
                            title: "No categories yet",
                            subtitle: "Work categories appear after saved dictations."
                        )
                    } else {
                        ForEach(viewModel.snapshot.categories) { insight in
                            ZenMeterRow(
                                label: insight.category.displayName,
                                percent: percentOfWords(insight.wordCount)
                            )
                        }
                        .padding(.horizontal, ZenDesign.Spacing.md)
                    }
                }
                .padding(.vertical, ZenDesign.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func percentOfWords(_ count: Int) -> Int {
        let total = max(1, viewModel.snapshot.totalWordCount)
        return Int(
            (Double(count) / Double(total) * 100).rounded()
        )
    }

    private var shareSummary: ShareCardSummary {
        ShareCardSummary(
            totalWordCount: viewModel.snapshot.totalWordCount,
            weightedWordsPerMinute:
                Int(viewModel.snapshot.weightedWordsPerMinute.rounded()),
            currentStreakDays: viewModel.snapshot.currentStreakDays,
            distinctApplicationCount:
                viewModel.snapshot.distinctApplicationCount
        )
    }

    private var maxActivityWords: Int {
        displayedActivity.map(\.wordCount).max() ?? 0
    }

    private var displayedActivity: [DisplayActivityDay] {
        guard viewModel.snapshot.recentActivity.isEmpty else {
            return viewModel.snapshot.recentActivity.map {
                DisplayActivityDay(date: $0.date, wordCount: $0.wordCount)
            }
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: -offset,
                to: start
            ) else {
                return nil
            }
            return DisplayActivityDay(date: date, wordCount: 0)
        }
    }

    private func activityHeight(for wordCount: Int) -> CGFloat {
        let maximum = max(1, maxActivityWords)
        guard wordCount > 0 else { return 4 }
        return 12 + 84 * CGFloat(wordCount) / CGFloat(maximum)
    }
}
