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
