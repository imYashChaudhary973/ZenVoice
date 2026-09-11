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
/// engine catalogue, so they must never change. Whisper engine IDs match the
/// catalogue model IDs so choosing an engine selects its file.
public enum EngineIdentifiers {
    /// Pre-unification ID. Canonicalized to ``whisperLargeV3Turbo``.
    public static let whisper = "whisper"
    public static let whisperLargeV3Turbo = "whisper-large-v3-turbo"
    public static let whisperLargeV3 = "whisper-large-v3"
    public static let whisperDistilLargeV3 = "whisper-distil-large-v3"
    public static let hinglishApex = "hindi2hinglish-apex"
    public static let parakeetTDTv3 = "parakeet-tdt-v3"
    public static let openaiTranscribe = "openai-transcribe"
    public static let geminiTranscribe = "gemini-transcribe"

    public static func canonical(_ engineID: String) -> String {
        engineID == whisper ? whisperLargeV3Turbo : engineID
    }

    public static func isKnown(_ engineID: String) -> Bool {
        let id = canonical(engineID)
        return id == parakeetTDTv3
            || id == openaiTranscribe
            || id == geminiTranscribe
            || VerifiedModelCatalog.model(id: id) != nil
    }

    public static func isCloudSpeech(_ engineID: String) -> Bool {
        let id = canonical(engineID)
        return id == openaiTranscribe || id == geminiTranscribe
    }

    public static func isWhisperFamily(_ engineID: String) -> Bool {
        let id = canonical(engineID)
        guard let model = VerifiedModelCatalog.model(id: id) else {
            return false
        }
        return model.format.contains("whisper.cpp")
    }
}
