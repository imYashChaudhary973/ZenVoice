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

/// Audio preprocessing for the Cohere Transcribe INT8 ONNX export.
///
/// The `cstr/cohere-transcribe-onnx-int8` encoder ONNX graph contains the
/// log-mel spectrogram frontend, so ZenVoice only needs to feed it normalized
/// 16 kHz mono float PCM with shape `(1, samples)`.
struct CohereMelSpectrogram {
    /// Normalize a 16 kHz mono float waveform to [-1, 1] and reshape for the
    /// encoder. The encoder expects shape `(1, samples)`.
    static func normalize(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let maxAbs = samples.reduce(0 as Float) { max($0, abs($1)) }
        guard maxAbs > 0 else {
            return samples
        }
        let scale = 1.0 / maxAbs
        return samples.map { $0 * scale }
    }
}
