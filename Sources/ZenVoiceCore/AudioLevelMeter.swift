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

public struct AudioLevelMeter {
    public private(set) var level = 0.0

    public init() {}

    public mutating func update(
        averageDecibels: Float,
        peakDecibels: Float
    ) -> Double {
        let averageLevel = Self.normalize(decibels: averageDecibels)
        let peakLevel = Self.normalize(decibels: peakDecibels)
        let measuredLevel = (averageLevel * 0.68) + (peakLevel * 0.32)

        let smoothing = measuredLevel > level ? 0.58 : 0.16
        level += (measuredLevel - level) * smoothing
        return level
    }

    public static func normalize(decibels: Float) -> Double {
        let noiseFloor = -55.0
        let loudSpeechLevel = -6.0
        let value = (Double(decibels) - noiseFloor) /
            (loudSpeechLevel - noiseFloor)
        return max(0, min(1, value))
    }
}
