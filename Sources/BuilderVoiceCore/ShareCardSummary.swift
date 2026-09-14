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
