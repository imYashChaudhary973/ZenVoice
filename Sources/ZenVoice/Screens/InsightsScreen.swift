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

            topMetricsGrid

            HStack(alignment: .top, spacing: ZenDesign.Spacing.xl) {
                desktopUsageCard
                streakCard
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
        .padding(ZenDesign.Spacing.xl)
        .frame(width: 920, alignment: .topLeading)
        .onAppear(perform: viewModel.refresh)
        .sheet(isPresented: $showsShareCard) {
            ShareHighlightSheet(summary: shareSummary)
        }
    }

    // MARK: top metrics

    private var topMetricsGrid: some View {
        HStack(alignment: .top, spacing: ZenDesign.Spacing.xl) {
            wpmCard
            fixesCard
            totalWordsCard
            topAppCard
        }
    }

    private var wpmCard: some View {
        metricCard(
            icon: "waveform",
            label: "Words per minute",
            value: "\(Int(viewModel.snapshot.weightedWordsPerMinute.rounded()))"
        ) {
            ZenGauge(progress: wpmGaugeProgress)
                .frame(height: 64)
        }
    }

    private var wpmGaugeProgress: Double {
        let wpm = viewModel.snapshot.weightedWordsPerMinute
        guard wpm > 0 else { return 0 }
        return min(1.0, wpm / 200)
    }

    private var fixesCard: some View {
        metricCard(
            icon: "wand.and.stars",
            label: "Fixes made by ZenVoice",
            value: viewModel.snapshot.correctionCount.formatted()
        ) {
            Text("Corrections applied across all dictations.")
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
        }
    }

    private var totalWordsCard: some View {
        metricCard(
            icon: "text.quote",
            label: "Total words dictated",
            value: viewModel.snapshot.totalWordCount.formatted()
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                Text(totalWordsFlavor)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)

                if let topApp = viewModel.snapshot.topApplications.first {
                    HStack(spacing: ZenDesign.Spacing.xs) {
                        Image(systemName: "macwindow")
                            .foregroundStyle(ZenDesign.Semantic.textOnAccent)
                            .padding(ZenDesign.Spacing.xs)
                            .background(ZenDesign.Semantic.accentFill)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        barFill(percent: percentOfWords(topApp.wordCount))
                            .frame(height: 12)

                        Text(topApp.displayName)
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var totalWordsFlavor: String {
        let words = viewModel.snapshot.totalWordCount
        guard words >= 1000 else { return "Keep going — every word counts." }
        let chapters = max(1, words / 2500)
        return "You've written about \(chapters) book chapter\(chapters == 1 ? "" : "s")!"
    }

    private var topAppCard: some View {
        metricCard(
            icon: "macwindow",
            label: "Most used app",
            value: viewModel.snapshot.topApplications.first?.displayName ?? "—"
        ) {
            if let topApp = viewModel.snapshot.topApplications.first {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(topApp.wordCount.formatted())
                            .font(ZenDesign.Typography.metricCaption)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text("words")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    }
                    ZenMeterRow(
                        label: "of total",
                        percent: percentOfWords(topApp.wordCount)
                    )
                }
            } else {
                Text("No app data yet")
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }
        }
    }

    private func metricCard(
        icon: String,
        label: String,
        value: String,
        @ViewBuilder detail: () -> some View
    ) -> some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                metricEyebrow(label, icon: icon)
                Text(value)
                    .font(ZenDesign.Typography.metric)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 0)

                detail()

                Spacer(minLength: 0)
            }
            .padding(ZenDesign.Spacing.lg)
            .frame(minWidth: 206, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func metricEyebrow(_ label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .accessibilityHidden(true)
            Text(label.uppercased())
                .font(ZenDesign.Typography.eyebrow)
                .tracking(1.0)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: desktop usage

    private var desktopUsageCard: some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Desktop usage")
                        .font(ZenDesign.Typography.sectionTitle)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Spacer()
                    Text("TOTAL APPS USED | \(viewModel.snapshot.distinctApplicationCount)")
                        .font(ZenDesign.Typography.eyebrow)
                        .tracking(1.0)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                .padding(ZenDesign.Spacing.lg)

                if viewModel.snapshot.categories.isEmpty {
                    ZenRow(
                        icon: "square.grid.2x2",
                        title: "No categories yet",
                        subtitle: "Work categories appear after saved dictations."
                    )
                    .padding(ZenDesign.Spacing.lg)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(
                            Array(categoryRows.enumerated()),
                            id: \.offset
                        ) { index, row in
                            categoryBar(row: row)
                            if index < categoryRows.count - 1 {
                                ZenPanelDivider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .padding(.horizontal, ZenDesign.Spacing.lg)
                    .padding(.vertical, ZenDesign.Spacing.md)
                }
            }
            .frame(width: 448)
        }
    }

    private var categoryRows: [(category: DictationCategory, wordCount: Int, percent: Int)] {
        let total = max(1, viewModel.snapshot.totalWordCount)
        let rows = viewModel.snapshot.categories
            .sorted { $0.wordCount > $1.wordCount }
            .map { insight in
                (
                    insight.category,
                    insight.wordCount,
                    Int((Double(insight.wordCount) / Double(total) * 100).rounded())
                )
            }
        return Array(rows.prefix(6))
    }

    private func categoryBar(
        row: (category: DictationCategory, wordCount: Int, percent: Int)
    ) -> some View {
        HStack(spacing: ZenDesign.Spacing.md) {
            Image(systemName: categoryIcon(row.category))
                .font(.system(size: 18))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(row.category.displayName.uppercased())
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Spacer()
                    Text("\(row.wordCount.formatted())")
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                }

                barFill(percent: row.percent, color: categoryColor(row.category))
                    .frame(height: 8)
            }
        }
        .padding(.vertical, ZenDesign.Spacing.sm)
        .frame(minHeight: 44)
    }

    private func categoryIcon(_ category: DictationCategory) -> String {
        switch category {
        case .documents: return "doc.text"
        case .email: return "envelope"
        case .workMessages: return "briefcase"
        case .personalMessages: return "message"
        case .aiPrompts: return "sparkles"
        case .notes: return "note.text"
        case .development: return "terminal"
        case .other: return "ellipsis"
        }
    }

    private func categoryColor(_ category: DictationCategory) -> Color {
        switch category {
        case .documents: return ZenDesign.Semantic.accent
        case .email: return ZenDesign.Semantic.success
        case .workMessages: return ZenDesign.Semantic.warn
        case .personalMessages: return ZenDesign.Semantic.accentFill
        case .aiPrompts: return ZenDesign.Semantic.accentStrong
        case .notes: return ZenDesign.Semantic.successMuted
        case .development: return ZenDesign.Semantic.textTertiary
        case .other: return ZenDesign.Semantic.surfaceRaised
        }
    }

    // MARK: streak calendar

    private var streakCard: some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(viewModel.snapshot.currentStreakDays) day streak")
                        .font(ZenDesign.Typography.sectionTitle)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Spacer()
                    Text("LONGEST STREAK | \(viewModel.snapshot.longestStreakDays) DAYS")
                        .font(ZenDesign.Typography.eyebrow)
                        .tracking(1.0)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                .padding(ZenDesign.Spacing.lg)

                contributionCalendar
                    .frame(height: 130)
                    .padding(.horizontal, ZenDesign.Spacing.lg)
                    .padding(.bottom, ZenDesign.Spacing.md)

                HStack(spacing: ZenDesign.Spacing.sm) {
                    Text("More")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    ForEach(0..<4) { level in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(calendarColor(level: level))
                            .frame(width: 12, height: 12)
                    }
                    Text("Less")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)

                    Spacer()

                    Toggle("Current streak", isOn: .constant(true))
                        .toggleStyle(.checkbox)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .disabled(true)
                }
                .padding(ZenDesign.Spacing.lg)
            }
            .frame(width: 448)
        }
    }

    private var contributionCalendar: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weeks = Array(viewModel.snapshot.activityCalendar.chunked(into: 7).suffix(16))

        return HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .frame(height: 14)
                }
            }

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(alignment: .leading, spacing: 4) {
                    if let label = monthLabel(for: week, calendar: calendar, today: today) {
                        Text(label)
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                            .frame(height: 14)
                    } else {
                        Color.clear.frame(height: 14)
                    }

                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(calendarColor(for: day.wordCount))
                            .frame(width: 14, height: 14)
                            .accessibilityLabel(
                                "\(day.date.formatted(.dateTime.month().day())): \(day.wordCount) words"
                            )
                    }
                }
            }
        }
    }

    private func monthLabel(
        for week: [DailyActivityInsight],
        calendar: Calendar,
        today: Date
    ) -> String? {
        guard let firstDay = week.first?.date else { return nil }
        let components = calendar.dateComponents([.day], from: firstDay)
        guard components.day == 1 || firstDay == today else { return nil }
        return firstDay.formatted(.dateTime.month(.abbreviated))
    }

    private func calendarColor(for wordCount: Int) -> Color {
        let level: Int
        switch wordCount {
        case 0: level = 0
        case 1..<50: level = 1
        case 50..<200: level = 2
        case 200..<500: level = 3
        default: level = 4
        }
        return calendarColor(level: level)
    }

    private func calendarColor(level: Int) -> Color {
        switch level {
        case 0: return ZenDesign.Semantic.surfaceSunken
        case 1: return ZenDesign.Semantic.accent.opacity(0.18)
        case 2: return ZenDesign.Semantic.accent.opacity(0.40)
        case 3: return ZenDesign.Semantic.accent.opacity(0.65)
        default: return ZenDesign.Semantic.accent
        }
    }

    // MARK: helpers

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

    private func percentOfWords(_ count: Int) -> Int {
        let total = max(1, viewModel.snapshot.totalWordCount)
        return Int(
            (Double(count) / Double(total) * 100).rounded()
        )
    }

    private func barFill(percent: Int, color: Color? = nil) -> some View {
        let fillColor = color ?? ZenDesign.Semantic.accent
        let clamped = CGFloat(max(0, min(percent, 100))) / 100
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ZenDesign.Semantic.surfaceSunken)
                Capsule()
                    .fill(fillColor)
                    .frame(width: proxy.size.width * clamped)
            }
        }
    }
}

// MARK: gauge

private struct ZenGauge: View {
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let clamped = max(0, min(1, progress))
            let center = CGPoint(x: size.width / 2, y: size.height)
            let radius = min(size.width, size.height * 2) / 2 - 8
            let startAngle = Angle.degrees(180)
            let endAngle = Angle.degrees(360)
            let progressEnd = Angle.degrees(180 + 180 * clamped)

            let trackPath = Path { path in
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
            }
            let progressPath = Path { path in
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: progressEnd,
                    clockwise: false
                )
            }

            context.stroke(
                trackPath,
                with: .color(ZenDesign.Semantic.surfaceSunken),
                lineWidth: 10
            )
            context.stroke(
                progressPath,
                with: .color(ZenDesign.Semantic.accent),
                lineWidth: 10
            )
        }
    }
}

// MARK: array chunking helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
