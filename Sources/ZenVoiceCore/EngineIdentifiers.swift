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

/// Stable identifiers for every speech engine ZenVoice knows about.
///
/// These strings are persisted in user defaults and referenced by the verified
/// engine catalogue, so they must never change. The runtime implementations in
/// `ZenVoiceRuntime` use the same values.
public enum EngineIdentifiers {
    public static let whisper = "whisper"
    public static let appleSpeech = "apple-speech"
    public static let parakeetTDTv2 = "parakeet-tdt-v2"
    public static let parakeetTDTv3 = "parakeet-tdt-v3"
    public static let parakeetFlash = "parakeet-flash"
    public static let nemotronSpeechUltraFast = "nemotron-speech-ultra-fast"
    public static let nemotronSpeechMultilingual = "nemotron-speech-multilingual"
    public static let cohereTranscribe = "cohere-transcribe"

    /// Streaming engines used for live preview only. Final insert never
    /// resolves to these IDs — they are too inaccurate as whole-file decoders
    /// (Flash 14.1% WER, Nemotron Ultra Fast 23.8% on the 2026-08-18 table).
    public static let previewOnlyIDs: Set<String> = [
        parakeetFlash,
        nemotronSpeechUltraFast
    ]

    public static func isPreviewOnly(_ engineID: String) -> Bool {
        previewOnlyIDs.contains(engineID)
    }
}
