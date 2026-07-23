import Foundation

public struct DictationInsightEvent: Sendable {
    public let startedAt: Date
    public let durationSeconds: TimeInterval
    public let wordCount: Int
    public let correctionCount: Int
    public let targetBundleID: String?
    public let targetAppName: String?
    public let category: DictationCategory

    public init(
        startedAt: Date,
        durationSeconds: TimeInterval,
        wordCount: Int,
        correctionCount: Int,
        targetBundleID: String?,
        targetAppName: String?,
        category: DictationCategory
    ) {
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.correctionCount = correctionCount
        self.targetBundleID = targetBundleID
        self.targetAppName = targetAppName
        self.category = category
    }
}

public struct CategoryInsight: Identifiable, Sendable {
    public var id: DictationCategory { category }
    public let category: DictationCategory
    public let dictationCount: Int
    public let wordCount: Int
    public let durationSeconds: TimeInterval
}

public struct ApplicationInsight: Identifiable, Sendable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let displayName: String
    public let dictationCount: Int
    public let wordCount: Int
}

public struct DailyActivityInsight: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let dictationCount: Int
    public let wordCount: Int
}

public struct LocalInsightsSnapshot: Sendable {
    public let dictationCount: Int
    public let totalWordCount: Int
    public let totalDurationSeconds: TimeInterval
    public let weightedWordsPerMinute: Double
    public let correctionCount: Int
    public let distinctApplicationCount: Int
    public let currentStreakDays: Int
    public let longestStreakDays: Int
    public let categories: [CategoryInsight]
    public let topApplications: [ApplicationInsight]
    public let recentActivity: [DailyActivityInsight]

    public static let empty = LocalInsightsSnapshot(
        dictationCount: 0,
        totalWordCount: 0,
        totalDurationSeconds: 0,
        weightedWordsPerMinute: 0,
        correctionCount: 0,
        distinctApplicationCount: 0,
        currentStreakDays: 0,
        longestStreakDays: 0,
        categories: [],
        topApplications: [],
        recentActivity: []
    )

    public static func calculate(
        events: [DictationInsightEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LocalInsightsSnapshot {
        let totalWords = events.reduce(0) { $0 + $1.wordCount }
        let totalDuration = events.reduce(0) { $0 + $1.durationSeconds }
        let weightedWPM = DictationMetrics.wordsPerMinute(
            wordCount: totalWords,
            durationSeconds: totalDuration
        )
        let categories = Dictionary(grouping: events, by: \.category)
            .map { category, values in
                CategoryInsight(
                    category: category,
                    dictationCount: values.count,
                    wordCount: values.reduce(0) { $0 + $1.wordCount },
                    durationSeconds:
                        values.reduce(0) { $0 + $1.durationSeconds }
                )
            }
            .sorted {
                if $0.wordCount == $1.wordCount {
                    return $0.category.displayName < $1.category.displayName
                }
                return $0.wordCount > $1.wordCount
            }

        let applicationGroups = Dictionary(
            grouping: events.compactMap { event -> DictationInsightEvent? in
                event.targetBundleID == nil ? nil : event
            },
            by: { $0.targetBundleID! }
        )
        let applications = applicationGroups.map { bundleID, values in
            ApplicationInsight(
                bundleIdentifier: bundleID,
                displayName:
                    values.compactMap(\.targetAppName).first ?? bundleID,
                dictationCount: values.count,
                wordCount: values.reduce(0) { $0 + $1.wordCount }
            )
        }
        .sorted {
            if $0.wordCount == $1.wordCount {
                return $0.displayName < $1.displayName
            }
            return $0.wordCount > $1.wordCount
        }

        let activeDays = Set(
            events.filter { $0.wordCount >= 5 }.map {
                calendar.startOfDay(for: $0.startedAt)
            }
        )
        let currentStreak = streakEnding(
            at: calendar.startOfDay(for: now),
            activeDays: activeDays,
            calendar: calendar
        )
        let longestStreak = longestStreak(
            activeDays: activeDays,
            calendar: calendar
        )

        let today = calendar.startOfDay(for: now)
        let activity: [DailyActivityInsight] =
            (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: -offset,
                to: today
            ) else {
                return nil
            }
            let matching = events.filter {
                calendar.isDate($0.startedAt, inSameDayAs: date)
            }
            return DailyActivityInsight(
                date: date,
                dictationCount: matching.count,
                wordCount: matching.reduce(0) { $0 + $1.wordCount }
            )
        }

        return LocalInsightsSnapshot(
            dictationCount: events.count,
            totalWordCount: totalWords,
            totalDurationSeconds: totalDuration,
            weightedWordsPerMinute: weightedWPM,
            correctionCount: events.reduce(0) { $0 + $1.correctionCount },
            distinctApplicationCount: applications.count,
            currentStreakDays: currentStreak,
            longestStreakDays: longestStreak,
            categories: categories,
            topApplications: Array(applications.prefix(5)),
            recentActivity: activity
        )
    }

    private static func streakEnding(
        at date: Date,
        activeDays: Set<Date>,
        calendar: Calendar
    ) -> Int {
        var count = 0
        var cursor = date
        while activeDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(
                byAdding: .day,
                value: -1,
                to: cursor
            ) else {
                break
            }
            cursor = previous
        }
        return count
    }

    private static func longestStreak(
        activeDays: Set<Date>,
        calendar: Calendar
    ) -> Int {
        var longest = 0
        var current = 0
        var previous: Date?
        for day in activeDays.sorted() {
            if let previous,
               calendar.date(byAdding: .day, value: 1, to: previous) == day {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        return longest
    }
}

public enum ApplicationCategoryClassifier {
    public static func category(
        bundleIdentifier: String?,
        appName: String?
    ) -> DictationCategory {
        let bundleID = bundleIdentifier?.lowercased() ?? ""
        let name = appName?.lowercased() ?? ""

        if matches(
            bundleID,
            name,
            identifiers: [
                "com.apple.textedit", "com.apple.iwork.pages",
                "com.microsoft.word", "org.libreoffice.script"
            ],
            names: ["textedit", "pages", "microsoft word", "libreoffice"]
        ) {
            return .documents
        }
        if matches(
            bundleID,
            name,
            identifiers: [
                "com.apple.mail", "com.microsoft.outlook",
                "com.readdle.smartemail-macos", "com.mimestream.mimestream",
                "io.canarymail.mac"
            ],
            names: ["mail", "outlook", "spark", "mimestream", "canary mail"]
        ) {
            return .email
        }
        if matches(
            bundleID,
            name,
            identifiers: [
                "com.tinyspeck.slackmacgap", "com.microsoft.teams2"
            ],
            names: ["slack", "microsoft teams"]
        ) {
            return .workMessages
        }
        if matches(
            bundleID,
            name,
            identifiers: [
                "com.apple.messages", "net.whatsapp.whatsapp",
                "org.whispersystems.signal-desktop",
                "ru.keepcoder.telegram", "com.hnc.discord"
            ],
            names: ["messages", "whatsapp", "signal", "telegram", "discord"]
        ) {
            return .personalMessages
        }
        if matches(
            bundleID,
            name,
            identifiers: [
                "com.openai.chat", "com.openai.chatgpt",
                "com.openai.codex", "com.anthropic.claudefordesktop",
                "ai.perplexity.mac"
            ],
            names: ["chatgpt", "codex", "claude", "perplexity"]
        ) {
            return .aiPrompts
        }
        if matches(
            bundleID,
            name,
            identifiers: [
                "com.apple.notes", "notion.id", "md.obsidian",
                "net.shinyfrog.bear"
            ],
            names: ["notes", "notion", "obsidian", "bear"]
        ) {
            return .notes
        }
        if matches(
            bundleID,
            name,
            identifiers: [
                "com.apple.dt.xcode", "com.microsoft.vscode",
                "com.todesktop.230313mzl4w4u92", "dev.zed.zed",
                "com.apple.terminal", "com.googlecode.iterm2"
            ],
            names: [
                "xcode", "visual studio code", "cursor", "zed",
                "terminal", "iterm"
            ]
        ) {
            return .development
        }
        return .other
    }

    private static func matches(
        _ bundleIdentifier: String,
        _ appName: String,
        identifiers: [String],
        names: [String]
    ) -> Bool {
        identifiers.contains(bundleIdentifier) || names.contains(appName)
    }
}
