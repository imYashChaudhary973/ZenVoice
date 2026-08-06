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
import Speech
import ZenVoiceCore

/// Apple Speech (SFSpeechRecognizer) configured for on-device recognition.
///
/// Audio never leaves the Mac: `requiresOnDeviceRecognition` is forced to `true`
/// and the engine only reports itself available for locales that support
/// on-device recognition on this machine.
public final class AppleSpeechEngine: @unchecked Sendable, SpeechEngine {
    public static let engineID = EngineIdentifiers.appleSpeech

    public var descriptor: EngineDescriptor {
        let locales = Self.supportedLocales()
        let languages = locales.compactMap { locale in
            LanguageCatalog.language(code: locale.languageCode ?? locale.identifier)
        }
        return EngineDescriptor(
            id: Self.engineID,
            displayName: "Apple Speech",
            family: .appleSpeech,
            supportedLanguages: languages,
            requiresDownload: false,
            requiresInternet: false,
            format: "SFSpeechRecognizer (on-device)",
            publisher: "Apple",
            license: "Apple Software License",
            licenseURL:
                "https://www.apple.com/legal/sla/docs/macOSSonoma.pdf",
            attribution:
                "On-device speech recognition provided by Apple Speech "
                + "framework on macOS.",
            privacyNote:
                "Audio is processed on this Mac. Nothing is sent to Apple."
        )
    }

    public var isAvailable: Bool {
        guard !descriptor.supportedLanguages.isEmpty else {
            return false
        }
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status != .denied, status != .restricted else {
            return false
        }
        return true
    }

    public var languageCapability: ModelLanguageCapability {
        .multilingual
    }

    public init() {}

    public func prepare() async throws {
        // Apple Speech has no model download, but it must have permission.
        try await requestAuthorizationIfNeeded()
    }

    public func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        try await requestAuthorizationIfNeeded()

        let locale = Self.locale(for: languageProfile)
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw AppleSpeechError.unsupportedLocale(locale.identifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        if let initialPrompt, !initialPrompt.isEmpty {
            request.contextualStrings = contextualStrings(from: initialPrompt)
        }

        let processingStartedAt = Date()
        let result = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<
                SFSpeechRecognitionResult?, Error
            >) in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    continuation.resume(returning: result)
                }
            }
            // Detach a timeout so a hung recognizer does not block forever.
            Task {
                try? await Task.sleep(for: .seconds(120))
                task.cancel()
            }
        }

        guard let result else {
            throw AppleSpeechError.noResult
        }

        let transcript = result.bestTranscription.formattedString
        return TranscriptionResult(
            rawTranscript: transcript,
            finalTranscript: transcript,
            correctionCount: 0,
            isPartial: false,
            modelID: Self.engineID,
            processingDurationSeconds:
                Date().timeIntervalSince(processingStartedAt)
        )
    }

    private func requestAuthorizationIfNeeded() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .notDetermined:
            let newStatus = await withCheckedContinuation {
                (continuation: CheckedContinuation<
                    SFSpeechRecognizerAuthorizationStatus, Never
                >) in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard newStatus == .authorized else {
                throw AppleSpeechError.notAuthorized
            }
        case .authorized:
            break
        case .denied, .restricted:
            throw AppleSpeechError.notAuthorized
        @unknown default:
            throw AppleSpeechError.notAuthorized
        }
    }

    private static func supportedLocales() -> [Locale] {
        Array(SFSpeechRecognizer.supportedLocales())
            .filter { locale in
                guard let recognizer = SFSpeechRecognizer(locale: locale) else {
                    return false
                }
                return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
            }
    }

    private static func locale(for profile: LanguageProfile) -> Locale {
        let code = profile.inputLanguageCode
        let supported = supportedLocales()
        if let exact = supported.first(where: {
            $0.languageCode == code
        }) {
            return exact
        }
        // Fall back to a locale whose language code matches, ignoring region.
        if let fallback = supported.first(where: {
            $0.languageCode?.hasPrefix(code) == true
                || code.hasPrefix($0.languageCode ?? "")
        }) {
            return fallback
        }
        return Locale(identifier: code)
    }

    private func contextualStrings(from prompt: String) -> [String] {
        prompt
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    public enum AppleSpeechError: LocalizedError {
        case notAuthorized
        case unsupportedLocale(String)
        case noResult

        public var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return
                    "Speech recognition permission is required. Enable it in "
                    + "System Settings › Privacy › Speech Recognition."
            case .unsupportedLocale(let locale):
                return
                    "Apple Speech on-device recognition is not available for "
                    + "\(locale)."
            case .noResult:
                return "Apple Speech did not return a transcript."
            }
        }
    }
}
