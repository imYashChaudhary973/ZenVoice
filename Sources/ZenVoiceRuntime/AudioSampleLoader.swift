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
import Foundation

enum AudioSampleLoaderError: LocalizedError {
    case cannotOpen(URL)
    case invalidFormat
    case conversionFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let url):
            return "Could not open audio at \(url)."
        case .invalidFormat:
            return "Audio is not a readable PCM format."
        case .conversionFailed(let error):
            return "Audio conversion failed"
                + (error.map { ": \($0.localizedDescription)" } ?? "")
        }
    }
}

/// Loads mono 16 kHz float PCM from an arbitrary audio file.
///
/// The streaming `parakeet.cpp` API requires exactly 16 kHz mono float samples.
/// Offline functions accept WAV/CAF and resample internally, so this helper is
/// only used by streaming engines.
struct AudioSampleLoader {
    /// Returns 16 kHz mono float samples, or throws if the file cannot be read.
    static func load16kHzMonoFloatSamples(from url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioSampleLoaderError.cannotOpen(url)
        }

        let sourceFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioSampleLoaderError.invalidFormat
        }

        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioSampleLoaderError.invalidFormat
        }
        try file.read(into: sourceBuffer)

        if sourceFormat.sampleRate == targetFormat.sampleRate,
           sourceFormat.channelCount == 1,
           sourceFormat.commonFormat == .pcmFormatFloat32 {
            guard let channel = sourceBuffer.floatChannelData?.pointee,
                  sourceBuffer.frameLength > 0 else {
                throw AudioSampleLoaderError.invalidFormat
            }
            return Array(
                UnsafeBufferPointer(
                    start: channel,
                    count: Int(sourceBuffer.frameLength)
                )
            )
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else {
            throw AudioSampleLoaderError.invalidFormat
        }
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(
            (Double(sourceBuffer.frameLength) * ratio).rounded(.up) + 4_096
        )
        guard let targetBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            throw AudioSampleLoaderError.invalidFormat
        }

        var supplied = false
        var conversionError: NSError?
        converter.convert(to: targetBuffer, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return sourceBuffer
        }
        guard conversionError == nil,
              let channel = targetBuffer.floatChannelData?.pointee else {
            throw AudioSampleLoaderError.conversionFailed(conversionError)
        }
        return Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(targetBuffer.frameLength)
            )
        )
    }
}
