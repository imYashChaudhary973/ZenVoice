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
import ZenVoiceCore

/// Shared model filename for both Nemotron engine entries.
///
/// The same GGUF checkpoint is used in cache-aware streaming mode (Ultra Fast)
/// and in offline whole-file mode (Multilingual).
public enum NemotronEngineConstants {
    public static let modelFilename =
        VerifiedEngineCatalog.nemotronModelFilename
}

/// Base implementation for the Nemotron 3.5 ASR Streaming 0.6B checkpoint.
///
/// Two public subclasses expose the same model under different UX identities:
/// one optimized for low-latency streaming transcription, the other for offline
/// whole-file transcription. They share context loading and language-code
/// mapping.
public class NemotronSpeechEngineBase: @unchecked Sendable, SpeechEngine {
    public let descriptor: EngineDescriptor
    public let engineID: String

    public func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        fatalError("subclass must implement transcribe")
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    public var languageCapability: ModelLanguageCapability {
        .multilingual
    }

    private let modelURL: URL
    private var context: ParakeetContext?
    private let queue: DispatchQueue

    init(modelURL: URL, descriptor: EngineDescriptor, engineID: String) {
        self.modelURL = modelURL
        self.descriptor = descriptor
        self.engineID = engineID
        self.queue = DispatchQueue(
            label: "dev.yashchaudhary.ZenVoice.nemotron-\(engineID)",
            qos: .userInitiated
        )
    }

    public func prepare() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                do {
                    self.context = try ParakeetContext(
                        modelPath: self.modelURL.path
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func transcribeOffline(
        audioURL: URL,
        languageProfile: LanguageProfile
    ) async throws -> TranscriptionResult {
        guard isAvailable else {
            throw EngineError.noEngineAvailable
        }
        if context == nil {
            try await prepare()
        }
        guard let context else {
            throw EngineError.noEngineAvailable
        }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<TranscriptionResult, Error>)
            in
            queue.async {
                do {
                    let transcript = try context.transcribe(
                        url: audioURL,
                        languageCode: Self.nemotronLanguageCode(
                            for: languageProfile
                        )
                    )
                    let result = TranscriptionResult(
                        rawTranscript: transcript,
                        finalTranscript: transcript,
                        correctionCount: 0,
                        isPartial: false,
                        modelID: self.engineID,
                        processingDurationSeconds: 0
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func transcribeStreaming(
        audioURL: URL,
        languageProfile: LanguageProfile
    ) async throws -> TranscriptionResult {
        guard isAvailable else {
            throw EngineError.noEngineAvailable
        }
        if context == nil {
            try await prepare()
        }
        guard let context else {
            throw EngineError.noEngineAvailable
        }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<TranscriptionResult, Error>)
            in
            queue.async {
                do {
                    let samples = try AudioSampleLoader.load16kHzMonoFloatSamples(
                        from: audioURL
                    )
                    let transcript = try context.transcribeStreaming(
                        samples: samples,
                        languageCode: Self.nemotronLanguageCode(
                            for: languageProfile
                        )
                    )
                    let result = TranscriptionResult(
                        rawTranscript: transcript,
                        finalTranscript: transcript,
                        correctionCount: 0,
                        isPartial: false,
                        modelID: self.engineID,
                        processingDurationSeconds: 0
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func nemotronLanguageCode(
        for profile: LanguageProfile
    ) -> String? {
        let code = profile.inputLanguageCode
        if code == LanguageProfile.automaticCode {
            return nil
        }
        return localeForNemotron(languageCode: code)
    }

    /// Maps a BCP-47 style language code to a locale Nemotron recognises.
    ///
    /// Nemotron accepts both bare codes (`en`, `de`) and full locales (`en-US`,
    /// `de-DE`), but returns an error for unsupported locales. The mapping
    /// below pins the primary supported locale for each known language so the
    /// engine does not fail on a region variant it has not seen.
    private static func localeForNemotron(languageCode: String) -> String? {
        let canonical = languageCode.lowercased()
        let supportedLocales: Set<String> = [
            "en-us", "en-gb", "es-us", "es-es", "fr-fr", "fr-ca", "it-it",
            "pt-br", "pt-pt", "nl-nl", "de-de", "tr-tr", "ru-ru", "ar-ar",
            "hi-in", "ja-jp", "ko-kr", "vi-vn", "uk-ua", "pl-pl", "sv-se",
            "cs-cz", "nb-no", "da-dk", "bg-bg", "fi-fi", "hr-hr", "sk-sk",
            "zh-cn", "hu-hu", "ro-ro", "et-ee", "el-gr", "lt-lt", "lv-lv",
            "mt-mt", "sl-si", "he-il", "th-th", "nn-no"
        ]
        if supportedLocales.contains(canonical) {
            return canonical
        }
        let bare = canonical.split(separator: "-", maxSplits: 1).first
            .map(String.init) ?? canonical
        let primaryLocale: [String: String] = [
            "en": "en-US", "es": "es-US", "fr": "fr-FR", "it": "it-IT",
            "pt": "pt-BR", "nl": "nl-NL", "de": "de-DE", "tr": "tr-TR",
            "ru": "ru-RU", "ar": "ar-AR", "hi": "hi-IN", "ja": "ja-JP",
            "ko": "ko-KR", "vi": "vi-VN", "uk": "uk-UA", "pl": "pl-PL",
            "sv": "sv-SE", "cs": "cs-CZ", "nb": "nb-NO", "da": "da-DK",
            "bg": "bg-BG", "fi": "fi-FI", "hr": "hr-HR", "sk": "sk-SK",
            "zh": "zh-CN", "hu": "hu-HU", "ro": "ro-RO", "et": "et-EE",
            "el": "el-GR", "lt": "lt-LT", "lv": "lv-LV", "mt": "mt-MT",
            "sl": "sl-SI", "he": "he-IL", "th": "th-TH", "nn": "nn-NO"
        ]
        return primaryLocale[bare]
    }
}

/// Cache-aware streaming Nemotron 3.5 ASR.
public final class NemotronSpeechUltraFastEngine: NemotronSpeechEngineBase,
                                                   @unchecked Sendable {
    public static let engineID = EngineIdentifiers.nemotronSpeechUltraFast

    public convenience init(modelURL: URL) {
        self.init(
            modelURL: modelURL,
            descriptor: EngineDescriptor(
                id: Self.engineID,
                displayName: "Nemotron Speech 3.5 Ultra Fast",
                family: .nemotronSpeech,
                supportedLanguages: [],
                requiresDownload: true,
                requiresInternet: false,
                format: "GGUF (parakeet.cpp v0.5.0, streaming)",
                publisher: "NVIDIA",
                license: "OpenMDW-1.1",
                licenseURL: "https://openmdw.ai/license/1-1/",
                attribution:
                    "Nemotron 3.5 ASR Streaming 0.6B by NVIDIA. 40 locales. "
                    + "Runtime: parakeet.cpp v0.5.0 (MIT) by Ettore Di Giacinto "
                    + "/ LocalAI.",
                privacyNote:
                    "Runs entirely on this Mac. No audio leaves the device."
            ),
            engineID: Self.engineID
        )
    }

    public override func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        try await transcribeStreaming(
            audioURL: audioURL,
            languageProfile: languageProfile
        )
    }
}

/// Offline whole-file Nemotron 3.5 ASR for multilingual transcription.
public final class NemotronSpeechMultilingualEngine: NemotronSpeechEngineBase,
                                                     @unchecked Sendable {
    public static let engineID = EngineIdentifiers.nemotronSpeechMultilingual

    public convenience init(modelURL: URL) {
        self.init(
            modelURL: modelURL,
            descriptor: EngineDescriptor(
                id: Self.engineID,
                displayName: "Nemotron 3.5 Multilingual",
                family: .nemotronSpeech,
                supportedLanguages: [],
                requiresDownload: true,
                requiresInternet: false,
                format: "GGUF (parakeet.cpp v0.5.0)",
                publisher: "NVIDIA",
                license: "OpenMDW-1.1",
                licenseURL: "https://openmdw.ai/license/1-1/",
                attribution:
                    "Nemotron 3.5 ASR Streaming 0.6B by NVIDIA. 40 locales, "
                    + "run offline. Runtime: parakeet.cpp v0.5.0 (MIT) by "
                    + "Ettore Di Giacinto / LocalAI.",
                privacyNote:
                    "Runs entirely on this Mac. No audio leaves the device."
            ),
            engineID: Self.engineID
        )
    }

    public override func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        try await transcribeOffline(
            audioURL: audioURL,
            languageProfile: languageProfile
        )
    }
}
