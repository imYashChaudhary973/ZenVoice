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

/// A transcription runtime that ZenVoice can select and use.
///
/// Conforming types live in `ZenVoiceRuntime` because they depend on their
/// own frameworks (`whisper`, `Speech`, Core ML, etc.). The protocol itself is
/// in `ZenVoiceCore` so the app and settings UI can reason about engines
/// without importing every runtime.
public protocol SpeechEngine: Sendable {
    var descriptor: EngineDescriptor { get }

    /// The broad language family this engine serves.
    ///
    /// Used when `descriptor.supportedLanguages` is empty, which is the case
    /// for download-based engines whose exact locale list is determined by the
    /// model file.
    var languageCapability: ModelLanguageCapability { get }

    /// Whether the engine can be used right now for its supported languages.
    ///
    /// This is a synchronous snapshot. Engines that need an expensive check
    /// should cache the result and refresh it in `prepare()`.
    var isAvailable: Bool { get }

    /// Pays any one-off setup cost before the user needs it.
    ///
    /// Loading is otherwise lazy — it happens inside the first `transcribe`,
    /// after the user has already stopped talking. Prepare is called at app
    /// launch and whenever the active engine changes, on a background queue.
    func prepare() async throws

    /// Transcribes the audio file at `url` for the given language profile.
    ///
    /// The engine is responsible for format conversion, language mapping, and
    /// returning a `TranscriptionResult` whose `modelID` identifies the engine
    /// or model that produced the text.
    ///
    /// - Parameter initialPrompt: Optional context the engine should consider
    ///   when decoding. Not every engine supports this; those that do not must
    ///   ignore it silently rather than fail.
    func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult
}

/// The family a transcription engine belongs to.
///
/// The identifier is used by the verified engine catalogue and by analytics-free
/// benchmark grouping. New families are added here as engines arrive.
public enum EngineFamily: String, Codable, CaseIterable, Sendable {
    case whisper
    case appleSpeech
    case parakeetTDT
    case parakeetFlash
    case nemotronSpeech
    case cohereTranscribe

    public var displayName: String {
        switch self {
        case .whisper:
            return "Whisper"
        case .appleSpeech:
            return "Apple Speech"
        case .parakeetTDT:
            return "Parakeet TDT"
        case .parakeetFlash:
            return "Parakeet Flash"
        case .nemotronSpeech:
            return "Nemotron Speech"
        case .cohereTranscribe:
            return "Cohere Transcribe"
        }
    }
}

/// Static metadata for an engine.
///
/// Descriptors are plain data so the settings UI can list engines without
/// constructing heavy runtime objects.
public struct EngineDescriptor: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let family: EngineFamily
    /// Locales the engine supports on this Mac. Empty means "any" for
    /// download-based engines; built-in engines list concrete locales.
    public let supportedLanguages: [SupportedLanguage]
    /// Whether the engine needs a model download before it can transcribe.
    public let requiresDownload: Bool
    /// Whether audio leaves this Mac for this engine.
    public let requiresInternet: Bool
    /// File or runtime format, for the Models/Engines screen.
    public let format: String
    public let publisher: String
    public let license: String
    public let licenseURL: String
    public let attribution: String
    /// A short privacy note shown next to the engine.
    public let privacyNote: String

    public init(
        id: String,
        displayName: String,
        family: EngineFamily,
        supportedLanguages: [SupportedLanguage] = [],
        requiresDownload: Bool,
        requiresInternet: Bool,
        format: String,
        publisher: String,
        license: String,
        licenseURL: String,
        attribution: String,
        privacyNote: String
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.supportedLanguages = supportedLanguages
        self.requiresDownload = requiresDownload
        self.requiresInternet = requiresInternet
        self.format = format
        self.publisher = publisher
        self.license = license
        self.licenseURL = licenseURL
        self.attribution = attribution
        self.privacyNote = privacyNote
    }
}

/// Why an engine is unavailable for a language profile.
public enum EngineUnavailabilityReason: Equatable, Sendable {
    case unsupportedLanguage(String)
    case requiresDownload
    case requiresInternet
    case runtimeNotReady(String)
    case platformNotSupported
}

/// Availability information returned by the registry for a given profile.
public struct EngineAvailability: Sendable {
    public let engine: EngineDescriptor
    public let isAvailable: Bool
    public let reason: EngineUnavailabilityReason?

    public init(
        engine: EngineDescriptor,
        isAvailable: Bool,
        reason: EngineUnavailabilityReason? = nil
    ) {
        self.engine = engine
        self.isAvailable = isAvailable
        self.reason = reason
    }
}

/// Errors thrown by engine resolution or transcription.
public enum EngineError: LocalizedError {
    case noEngineAvailable
    case engineUnavailable(String)
    case preparationFailed(String, Error)
    case transcriptionFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .noEngineAvailable:
            return "No speech engine is available for this language."
        case .engineUnavailable(let id):
            return "\(id) is not available for this language."
        case .preparationFailed(let id, let error):
            return "\(id) could not start: \(error.localizedDescription)"
        case .transcriptionFailed(let id, let error):
            return "\(id) failed: \(error.localizedDescription)"
        }
    }
}
