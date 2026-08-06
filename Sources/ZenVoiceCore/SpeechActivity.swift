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

import Accelerate
import Foundation

/// Tracks how quiet the room is, so speech can be judged relative to it.
///
/// Fixed thresholds fail in both directions: a quiet microphone or a soft
/// speaker never crosses them and gets no live preview at all, while a noisy
/// room crosses them constantly and never registers a pause. Neither failure
/// explains itself to the user — dictation simply stops behaving.
public struct NoiseFloorEstimator: Equatable, Sendable {
    /// How far above the noise floor a buffer must sit to count as speech.
    /// Conversational speech runs 15–25 dB above room tone, so 12 dB accepts
    /// soft talkers without letting a fan through.
    public static let marginDecibels: Float = 12
    /// A peak this far above the floor counts even when the average does not,
    /// which catches short consonants at the start of a phrase.
    public static let peakMarginDecibels: Float = 22

    /// Bounds stop a silent room from making the detector hair-trigger, and a
    /// loud one from raising the bar past ordinary speech.
    public static let minimumFloorDecibels: Float = -75
    public static let maximumFloorDecibels: Float = -30

    /// The floor drops instantly to a new quiet reading but climbs slowly, so a
    /// pause in speech re-establishes the true floor while a sustained noise
    /// increase is still tracked.
    public static let riseDecibelsPerBuffer: Float = 0.08

    private var floorDecibels: Float = Self.maximumFloorDecibels
    private var hasReading = false

    public init() {}

    public var floor: Float { floorDecibels }

    public var speechThreshold: Float {
        floorDecibels + Self.marginDecibels
    }

    public var peakThreshold: Float {
        floorDecibels + Self.peakMarginDecibels
    }

    public mutating func observe(averageDecibels: Float) {
        guard averageDecibels.isFinite else { return }
        if !hasReading {
            floorDecibels = averageDecibels
            hasReading = true
        } else if averageDecibels < floorDecibels {
            floorDecibels = averageDecibels
        } else {
            floorDecibels += Self.riseDecibelsPerBuffer
        }
        floorDecibels = min(
            max(floorDecibels, Self.minimumFloorDecibels),
            Self.maximumFloorDecibels
        )
    }
}

/// Decides whether a capture buffer contained speech.
///
/// Live dictation uses this to find the pauses it segments on, and the accuracy
/// harness uses it to reproduce that segmentation offline. Both must agree, so
/// the decision lives here rather than inside the recorder.
public struct SpeechActivityDetector: Sendable {
    private var estimator = NoiseFloorEstimator()

    public init() {}

    public var noiseFloor: Float { estimator.floor }

    public mutating func isSpeech(
        averageDecibels: Float,
        peakDecibels: Float
    ) -> Bool {
        // Judge against the floor as it stood *before* this buffer, otherwise a
        // loud buffer raises the bar it is being measured against.
        let speechThreshold = estimator.speechThreshold
        let peakThreshold = estimator.peakThreshold
        let detected = averageDecibels > speechThreshold
            || peakDecibels > peakThreshold
        // Only silence should teach the floor where silence is; feeding speech
        // back in would drag it upward until nothing registers.
        if !detected {
            estimator.observe(averageDecibels: averageDecibels)
        }
        return detected
    }

    /// Level summary for a block of mono samples, in dBFS.
    ///
    /// Vectorised because of where this runs: ``SpokenStructure/silences(in:)``
    /// walks the *entire* recording through it after every decode, one window
    /// at a time, and the same measurement runs again in the capture callback
    /// for every buffer that arrives. `vDSP_measqv` returns the mean of the
    /// squares directly and `vDSP_maxmgv` the largest magnitude, which is
    /// exactly what the scalar loop computed.
    public static func levels(
        of samples: ArraySlice<Float>
    ) -> (average: Float, peak: Float) {
        guard !samples.isEmpty else {
            return (-120, -120)
        }
        var meanSquare: Float = 0
        var peak: Float = 0
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            vDSP_measqv(base, 1, &meanSquare, vDSP_Length(buffer.count))
            vDSP_maxmgv(base, 1, &peak, vDSP_Length(buffer.count))
        }
        let rms = meanSquare.squareRoot()
        return (
            20 * log10(max(rms, 0.000_001)),
            20 * log10(max(peak, 0.000_001))
        )
    }
}
