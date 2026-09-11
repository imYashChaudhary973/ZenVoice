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

public enum CloudSpeechError: LocalizedError, Equatable {
    case missingAPIKey
    case emptyAudio
    case malformedResponse
    case provider(Int, String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an API key in Models to use cloud speech."
        case .emptyAudio:
            return "The recording was empty."
        case .malformedResponse:
            return "The speech provider returned an unreadable response."
        case .provider(let status, let message):
            let trimmed = message.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if trimmed.isEmpty {
                return "Cloud speech failed (HTTP \(status))."
            }
            return trimmed
        case .transport(let message):
            return message
        }
    }
}

public protocol CloudSpeechTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
    func warm(url: URL) async
}

/// One reused ephemeral session so TLS is not negotiated per dictation.
public final class SharedCloudSpeechTransport: CloudSpeechTransport,
    @unchecked Sendable
{
    public static let shared = SharedCloudSpeechTransport()

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    public func warm(url: URL) async {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        request.httpShouldHandleCookies = false
        _ = try? await session.data(for: request)
    }
}

/// OpenAI-compatible audio transcription request. Pure: no network, no key.
public struct CloudSpeechRequest: Equatable, Sendable {
    public let endpoint: URL
    public let model: String
    public let languageCode: String?
    public let filename: String
    public let audio: Data
    public let boundary: String

    public init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        model: String = CloudSpeechEngine.openAIModel,
        languageCode: String? = nil,
        filename: String = "speech.wav",
        audio: Data,
        boundary: String = "ZenVoiceBoundary"
    ) {
        self.endpoint = endpoint
        self.model = model
        self.languageCode = languageCode
        self.filename = filename
        self.audio = audio
        self.boundary = boundary
    }

    public func urlRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.httpShouldHandleCookies = false
        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = encodedBody()
        return request
    }

    public func encodedBody() -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append(
                "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            )
            append("\(value)\r\n")
        }
        field("model", model)
        if let languageCode, !languageCode.isEmpty,
           languageCode != LanguageProfile.automaticCode {
            field("language", languageCode)
        }
        field("response_format", "json")
        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"file\"; "
                + "filename=\"\(filename)\"\r\n"
        )
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}

/// Gemini generateContent audio transcription. Pure: no network, no key.
public struct GeminiSpeechRequest: Equatable, Sendable {
    public static let defaultModel = "gemini-2.0-flash"
    public static let transcribePrompt =
        "Transcribe this audio. Reply with the spoken words only. "
        + "No labels, quotes, or commentary."

    public let model: String
    public let languageCode: String?
    public let audio: Data

    public init(
        model: String = GeminiSpeechRequest.defaultModel,
        languageCode: String? = nil,
        audio: Data
    ) {
        self.model = model
        self.languageCode = languageCode
        self.audio = audio
    }

    public var endpoint: URL {
        URL(
            string:
                "https://generativelanguage.googleapis.com/v1beta/models/"
                + model
                + ":generateContent"
        )!
    }

    public func urlRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.httpShouldHandleCookies = false
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = encodedBody()
        return request
    }

    public func encodedBody() -> Data {
        var prompt = Self.transcribePrompt
        if let languageCode, !languageCode.isEmpty,
           languageCode != LanguageProfile.automaticCode {
            prompt += " The spoken language is \(languageCode)."
        }
        let payload = GeminiSpeechJSON(
            contents: [
                .init(
                    parts: [
                        .init(text: prompt, inlineData: nil),
                        .init(
                            text: nil,
                            inlineData: .init(
                                mimeType: "audio/wav",
                                data: audio.base64EncodedString()
                            )
                        )
                    ]
                )
            ],
            generationConfig: .init(temperature: 0)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(payload)) ?? Data()
    }
}

private struct GeminiSpeechJSON: Encodable {
    struct Contents: Encodable {
        var parts: [Part]
    }

    struct Part: Encodable {
        var text: String?
        var inlineData: Inline?

        enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }
    }

    struct Inline: Encodable {
        var mimeType: String
        var data: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }
    }

    struct GenerationConfig: Encodable {
        var temperature: Int
    }

    var contents: [Contents]
    var generationConfig: GenerationConfig
}

public struct CloudSpeechEngine: SpeechEngine {
    public static let openAIModel = "gpt-4o-mini-transcribe"
    public static let geminiModel = GeminiSpeechRequest.defaultModel

    public enum Provider: String, Sendable {
        case openAI
        case gemini
    }

    public let descriptor: EngineDescriptor
    public let languageCapability: ModelLanguageCapability = .multilingual
    public let provider: Provider

    private let keyStore: any CloudAIKeyStoring
    private let transport: any CloudSpeechTransport
    private let model: String
    private let warmURL: URL

    public static func openAI(
        keyStore: any CloudAIKeyStoring,
        transport: any CloudSpeechTransport = SharedCloudSpeechTransport.shared
    ) -> CloudSpeechEngine {
        CloudSpeechEngine(
            provider: .openAI,
            keyStore: keyStore,
            transport: transport,
            model: openAIModel,
            descriptor: EngineDescriptor(
                id: EngineIdentifiers.openaiTranscribe,
                displayName: "OpenAI Transcribe",
                family: .cloud,
                supportedLanguages: [],
                requiresDownload: false,
                requiresInternet: true,
                format: "OpenAI Audio Transcriptions API",
                publisher: "OpenAI",
                license: "Provider terms",
                licenseURL: "https://openai.com/policies",
                attribution:
                    "gpt-4o-mini-transcribe via the user's OpenAI key.",
                privacyNote:
                    "Audio leaves this Mac and is billed to your OpenAI account."
            ),
            warmURL: URL(string: "https://api.openai.com/v1")!
        )
    }

    public static func gemini(
        keyStore: any CloudAIKeyStoring,
        transport: any CloudSpeechTransport = SharedCloudSpeechTransport.shared
    ) -> CloudSpeechEngine {
        CloudSpeechEngine(
            provider: .gemini,
            keyStore: keyStore,
            transport: transport,
            model: geminiModel,
            descriptor: EngineDescriptor(
                id: EngineIdentifiers.geminiTranscribe,
                displayName: "Gemini Transcribe",
                family: .cloud,
                supportedLanguages: [],
                requiresDownload: false,
                requiresInternet: true,
                format: "Gemini generateContent audio",
                publisher: "Google",
                license: "Provider terms",
                licenseURL: "https://ai.google.dev/gemini-api/terms",
                attribution:
                    "gemini-2.0-flash via the user's Google AI Studio key.",
                privacyNote:
                    "Audio leaves this Mac and is billed to your Google account."
            ),
            warmURL: URL(string: "https://generativelanguage.googleapis.com")!
        )
    }

    private init(
        provider: Provider,
        keyStore: any CloudAIKeyStoring,
        transport: any CloudSpeechTransport,
        model: String,
        descriptor: EngineDescriptor,
        warmURL: URL
    ) {
        self.provider = provider
        self.keyStore = keyStore
        self.transport = transport
        self.model = model
        self.descriptor = descriptor
        self.warmURL = warmURL
    }

    public var isAvailable: Bool {
        guard let key = try? keyStore.loadKey() else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func prepare() async throws {
        await transport.warm(url: warmURL)
    }

    public func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        let started = Date()
        guard let key = try keyStore.loadKey()?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !key.isEmpty else {
            throw CloudSpeechError.missingAPIKey
        }
        let audio = try Data(contentsOf: audioURL)
        guard !audio.isEmpty else {
            throw CloudSpeechError.emptyAudio
        }
        let language =
            languageProfile.inputLanguageCode == LanguageProfile.automaticCode
            ? nil
            : languageProfile.inputLanguageCode
        let urlRequest: URLRequest
        switch provider {
        case .openAI:
            urlRequest = CloudSpeechRequest(
                model: model,
                languageCode: language,
                filename: audioURL.lastPathComponent,
                audio: audio
            ).urlRequest(apiKey: key)
        case .gemini:
            urlRequest = GeminiSpeechRequest(
                model: model,
                languageCode: language,
                audio: audio
            ).urlRequest(apiKey: key)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(urlRequest)
        } catch {
            throw CloudSpeechError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CloudSpeechError.provider(
                status,
                Self.providerMessage(from: data)
            )
        }
        let text: String
        switch provider {
        case .openAI:
            text = try Self.parseOpenAITranscript(from: data)
        case .gemini:
            text = try Self.parseGeminiTranscript(from: data)
        }
        return TranscriptionResult(
            rawTranscript: text,
            finalTranscript: text,
            correctionCount: 0,
            modelID: descriptor.id,
            processingDurationSeconds: Date().timeIntervalSince(started)
        )
    }

    public static func parseOpenAITranscript(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let text = object["text"] as? String else {
            throw CloudSpeechError.malformedResponse
        }
        return try nonempty(text)
    }

    public static func parseGeminiTranscript(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw CloudSpeechError.malformedResponse
        }
        return try nonempty(text)
    }

    /// Back-compat name used by Phase 1 checks.
    public static func parseTranscript(from data: Data) throws -> String {
        try parseOpenAITranscript(from: data)
    }

    public static let defaultModel = openAIModel

    private static func nonempty(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudSpeechError.malformedResponse
        }
        return trimmed
    }

    private static func providerMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
