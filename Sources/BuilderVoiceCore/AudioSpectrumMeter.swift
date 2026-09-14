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

/// Live waveform heights for the recording HUD.
///
/// This is not a frequency analyser. Each bar is the peak of a slice of the
/// latest audio, mixed with overall loudness so the *whole* meter rises and
/// jitters while someone is speaking, and falls when they stop. A spectrum
/// left two bars twitching; that read as "nothing is being recorded".
public struct AudioSpectrumMeter {
    public static let barCount = 17

    private static let window = 1_024
    /// Centre-weighted so the HUD still reads as a voiceprint, without
    /// pinning the motion to two bars.
    private static let envelope: [Double] = {
        let centre = Double(barCount - 1) / 2
        return (0..<barCount).map { index in
            let x = abs(Double(index) - centre) / centre
            return 0.42 + 0.58 * (1 - x * x)
        }
    }()

    private var ring = [Float](repeating: 0, count: window)
    private var writeIndex = 0
    private var filled = 0
    private var smoothed = [Double](repeating: 0, count: barCount)
    private var lastBars = [Double](repeating: 0, count: barCount)

    public init() {}

    public mutating func reset() {
        ring = [Float](repeating: 0, count: Self.window)
        writeIndex = 0
        filled = 0
        smoothed = Array(repeating: 0, count: Self.barCount)
        lastBars = Array(repeating: 0, count: Self.barCount)
    }

    /// Returns `barCount` values in 0...1, left-to-right through the latest
    /// audio window.
    public mutating func update(
        samples: UnsafePointer<Float>,
        count: Int
    ) -> [Double] {
        guard count > 0 else {
            return lastBars
        }

        for index in 0..<count {
            ring[writeIndex] = samples[index]
            writeIndex = (writeIndex + 1) % Self.window
            if filled < Self.window {
                filled += 1
            }
        }
        guard filled >= Self.barCount else {
            return lastBars
        }

        let oldest = filled == Self.window ? writeIndex : 0
        let sliceLength = filled / Self.barCount
        var slicePeaks = [Double](repeating: 0, count: Self.barCount)
        var overallPeak: Float = 0

        for bar in 0..<Self.barCount {
            var peak: Float = 0
            let start = bar * sliceLength
            for offset in 0..<sliceLength {
                let sample = abs(ring[(oldest + start + offset) % Self.window])
                if sample > peak {
                    peak = sample
                }
            }
            if peak > overallPeak {
                overallPeak = peak
            }
            slicePeaks[bar] = AudioLevelMeter.normalize(
                decibels: 20 * log10(max(peak, 1e-6))
            )
        }

        let overall = AudioLevelMeter.normalize(
            decibels: 20 * log10(max(overallPeak, 1e-6))
        )

        for bar in 0..<Self.barCount {
            // Slice peaks make the shape change every buffer. Overall loudness
            // lifts every bar so speech never hides in two of them.
            let measured = min(
                1,
                0.58 * slicePeaks[bar]
                    + 0.42 * overall * Self.envelope[bar]
            )
            let smoothing = measured > smoothed[bar] ? 0.82 : 0.32
            smoothed[bar] += (measured - smoothed[bar]) * smoothing
        }

        lastBars = smoothed
        return lastBars
    }
}
