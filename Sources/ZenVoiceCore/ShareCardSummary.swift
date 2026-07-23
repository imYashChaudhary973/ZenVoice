import Foundation

public struct ShareCardSummary: Equatable, Sendable {
    public let totalWordCount: Int
    public let weightedWordsPerMinute: Int
    public let currentStreakDays: Int
    public let distinctApplicationCount: Int

    public init(
        totalWordCount: Int,
        weightedWordsPerMinute: Int,
        currentStreakDays: Int,
        distinctApplicationCount: Int
    ) {
        self.totalWordCount = max(0, totalWordCount)
        self.weightedWordsPerMinute = max(0, weightedWordsPerMinute)
        self.currentStreakDays = max(0, currentStreakDays)
        self.distinctApplicationCount = max(
            0,
            distinctApplicationCount
        )
    }
}
