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

import AVFoundation
import Accelerate
import Foundation

/// Compact spectral fingerprint of a You-channel WAV.
///
/// ponytail: 16-band energy, replace with ECAPA/Wespeaker if collisions show up.
enum SpeakerFingerprint {
    static let bandCount = 16

    static func embedding(fromWav url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frames
              ) else {
            throw NSError(
                domain: "ZenVoice",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "The You recording is empty."
                ]
            )
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            throw NSError(
                domain: "ZenVoice",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "The You recording has no samples."
                ]
            )
        }
        let count = Int(buffer.frameLength)
        var bands = [Float](repeating: 0, count: bandCount)
        let hop = max(1, count / bandCount)
        for band in 0..<bandCount {
            let start = band * hop
            let end = min(count, start + hop)
            var sum: Float = 0
            vDSP_rmsqv(channel.advanced(by: start), 1, &sum, vDSP_Length(end - start))
            bands[band] = sum
        }
        var norm: Float = 0
        vDSP_svesq(bands, 1, &norm, vDSP_Length(bandCount))
        norm = sqrtf(norm)
        if norm > 0 {
            var scale = 1 / norm
            vDSP_vsmul(bands, 1, &scale, &bands, 1, vDSP_Length(bandCount))
        }
        return bands
    }
}
