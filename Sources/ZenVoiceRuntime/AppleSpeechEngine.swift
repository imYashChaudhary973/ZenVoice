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
import os
@preconcurrency import Speech
import ZenVoiceCore

/// Thread-safe bridge between Speech's callback task and Swift concurrency.
///
/// Cancellation, timeout, a final result, and an error can arrive on different
/// threads. The first terminal event wins; every later callback is ignored.
private final class AppleSpeechRecognitionOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation:
        CheckedContinuation<SFSpeechRecognitionResult, Error>?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var completion: Result<SFSpeechRecognitionResult, Error>?

    func install(
        continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>
    ) {
        lock.lock()
        if let completion {
            lock.unlock()
            continuation.resume(with: completion)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func install(recognitionTask: SFSpeechRecognitionTask) {
        lock.lock()
        let alreadyCompleted = completion != nil
        if !alreadyCompleted {
            self.recognitionTask = recognitionTask
        }
        lock.unlock()
        if alreadyCompleted {
            recognitionTask.cancel()
        }
    }

    func install(timeoutTask: Task<Void, Never>) {
        lock.lock()
        let alreadyCompleted = completion != nil
        if !alreadyCompleted {
            self.timeoutTask = timeoutTask
        }
        lock.unlock()
        if alreadyCompleted {
            timeoutTask.cancel()
        }
    }

    func receive(
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        if let error {
            finish(.failure(error), cancelRecognition: true)
        } else if let result, result.isFinal {
            finish(.success(result), cancelRecognition: false)
        }
    }

    func cancel() {
        finish(.failure(CancellationError()), cancelRecognition: true)
    }

    func timeout() {
        finish(
            .failure(AppleSpeechEngine.AppleSpeechError.timedOut),
            cancelRecognition: true
        )
    }

    private func finish(
        _ result: Result<SFSpeechRecognitionResult, Error>,
        cancelRecognition: Bool
    ) {
        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return
        }
        completion = result
        let continuation = continuation
        self.continuation = nil
        let recognitionTask = recognitionTask
        self.recognitionTask = nil
        let timeoutTask = timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        if cancelRecognition {
            recognitionTask?.cancel()
        }
        continuation?.resume(with: result)
    }
}

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
            LanguageCatalog.language(code: Self.languageCode(for: locale))
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
        let operation = AppleSpeechRecognitionOperation()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<
                    SFSpeechRecognitionResult, Error
                >) in
                operation.install(continuation: continuation)
                let task = recognizer.recognitionTask(
                    with: request
                ) { result, error in
                    operation.receive(result: result, error: error)
                }
                operation.install(recognitionTask: task)
                let timeoutTask = Task { [weak operation] in
                    try? await Task.sleep(for: .seconds(120))
                    guard !Task.isCancelled else { return }
                    operation?.timeout()
                }
                operation.install(timeoutTask: timeoutTask)
            }
        } onCancel: {
            operation.cancel()
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
            languageCode(for: $0) == code
        }) {
            return exact
        }
        // Fall back to a locale whose language code matches, ignoring region.
        if let fallback = supported.first(where: {
            languageCode(for: $0).hasPrefix(code)
                || code.hasPrefix(languageCode(for: $0))
        }) {
            return fallback
        }
        return Locale(identifier: code)
    }

    private static func languageCode(for locale: Locale) -> String {
        locale.language.languageCode?.identifier ?? locale.identifier
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
        case timedOut

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
            case .timedOut:
                return "Apple Speech timed out before returning a transcript."
            }
        }
    }
}
