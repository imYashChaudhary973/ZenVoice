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

/// Resolves a cloud-review decision without risking the local transcript.
///
/// Closing, cancelling, timing out, or receiving an empty provider result all
/// keep the exact local text. Only a non-empty accepted result is allowed to
/// replace it.
public struct CloudTranscriptResolution: Equatable, Sendable {
    public let transcript: String
    public let didApply: Bool

    public static func resolve(
        localTranscript: String,
        acceptedTranscript: String?
    ) -> CloudTranscriptResolution {
        guard let acceptedTranscript,
              !acceptedTranscript.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            return CloudTranscriptResolution(
                transcript: localTranscript,
                didApply: false
            )
        }
        return CloudTranscriptResolution(
            transcript: acceptedTranscript,
            didApply: true
        )
    }
}

// MARK: - Providers

/// A hosted provider ZenVoice can send a transcript to, when the user opts in.
///
/// OpenAI-compatible providers use the chat-completions shape. Anthropic uses
/// the Messages API. `custom` is any other OpenAI-compatible endpoint.
public enum CloudAIProvider: String, Codable, CaseIterable, Sendable {
    case openAI
    case groq
    case anthropic
    case openRouter
    case ollamaCloud
    case ollama
    case custom

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .groq: return "Groq"
        case .anthropic: return "Anthropic"
        case .openRouter: return "OpenRouter"
        case .ollamaCloud: return "Ollama Cloud"
        case .ollama: return "Ollama"
        case .custom: return "Custom endpoint"
        }
    }

    /// The endpoint used when the user has not supplied one. `custom` has no
    /// default on purpose — the user must state where their data is going.
    public var defaultBaseURL: String? {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .ollamaCloud: return "https://ollama.com/v1"
        case .ollama: return "http://127.0.0.1:11434/v1"
        case .custom: return nil
        }
    }

    public var defaultModel: String? {
        switch self {
        case .openAI, .groq, .anthropic, .openRouter:
            return knownModels.first
        case .ollamaCloud:
            return "gpt-oss:120b"
        case .ollama:
            return "llama3.2"
        case .custom:
            return nil
        }
    }

    /// Empty means the user types the model id — OpenRouter, Ollama, and
    /// custom each have more models than we can honestly curate.
    public var knownModels: [String] {
        switch self {
        case .openAI:
            return [
                "gpt-4o-mini",
                "gpt-4o",
                "gpt-4.1-mini",
                "gpt-4.1",
            ]
        case .groq:
            return [
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b",
                "groq/compound",
                "groq/compound-mini",
                "qwen/qwen3.6-27b",
            ]
        case .anthropic:
            return [
                "claude-3-5-sonnet-20241022",
                "claude-3-5-haiku-20241022",
                "claude-3-opus-20240229",
                "claude-3-7-sonnet-20250219",
            ]
        case .openRouter:
            return [
                "openai/gpt-4o-mini",
                "openai/gpt-4o",
                "anthropic/claude-sonnet-4",
                "google/gemini-2.5-flash",
                "meta-llama/llama-3.3-70b-instruct",
            ]
        case .ollamaCloud, .ollama, .custom:
            return []
        }
    }

    /// Local Ollama ignores the key. Everything else needs one.
    public var requiresAPIKey: Bool {
        self != .ollama
    }

    fileprivate var usesChatCompletions: Bool {
        self != .anthropic
    }

    fileprivate var endpointPath: String {
        usesChatCompletions ? "/chat/completions" : "/messages"
    }

    fileprivate func authHeader(apiKey: String) -> (
        field: String,
        value: String
    ) {
        switch self {
        case .anthropic:
            return ("x-api-key", apiKey)
        default:
            return ("Authorization", "Bearer \(apiKey)")
        }
    }

    fileprivate var extraHeaders: [(String, String)] {
        switch self {
        case .anthropic:
            return [("anthropic-version", "2023-06-01")]
        case .openRouter:
            return [("X-Title", "ZenVoice")]
        default:
            return []
        }
    }

    fileprivate func requestBody(
        model: String,
        systemPrompt: String,
        userContent: String
    ) -> [String: Any] {
        if usesChatCompletions {
            return [
                "model": model,
                "temperature": 0.2,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userContent]
                ]
            ]
        }
        return [
            "model": model,
            "max_tokens": 4096,
            "temperature": 0.2,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]
    }

    fileprivate func extractContent(
        from object: [String: Any]
    ) -> String? {
        if usesChatCompletions {
            guard let choices = object["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            return content
        }
        guard let contentArray = object["content"] as? [[String: Any]],
              let first = contentArray.first,
              let text = first["text"] as? String else {
            return nil
        }
        return text
    }
}

// MARK: - Configuration

public enum CloudAIEnhancementError: LocalizedError, Equatable {
    case disabled
    case missingAPIKey
    case missingBaseURL
    case missingModel
    case insecureBaseURL(String)
    case invalidBaseURL(String)
    case emptyTranscript
    case transport(String)
    case provider(status: Int, message: String)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "Cloud AI Enhancement is off."
        case .missingAPIKey:
            return "Add your provider API key to use Cloud AI Enhancement."
        case .missingBaseURL:
            return "Set the provider's base URL."
        case .missingModel:
            return "Set the model name."
        case .insecureBaseURL:
            return "The endpoint must use HTTPS."
        case .invalidBaseURL:
            return "That endpoint is not a valid URL."
        case .emptyTranscript:
            return "There is no transcript to enhance."
        case .transport(let message):
            return "The request could not be completed: \(message)"
        case .provider(let status, let message):
            return message.isEmpty
                ? "The provider returned status \(status)."
                : "The provider returned status \(status): \(message)"
        case .malformedResponse:
            return "The provider's response could not be read."
        }
    }
}

/// Everything needed to build a request, minus the API key.
///
/// The key is deliberately absent: it lives in the Keychain and is supplied
/// separately at send time, so a configuration value can never be logged or
/// serialised with the secret inside it.
public struct CloudAIConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var provider: CloudAIProvider
    public var baseURL: String
    public var model: String
    public var prompt: String
    /// Whether an enhanced transcript replaces the local one without stopping
    /// to ask each time.
    ///
    /// Consent to send text off-device is given once, by enabling the feature
    /// and storing a key. Re-asking after every sentence is a different
    /// question — "did the model do a good job?" — and the user is entitled to
    /// answer it once. Off by default so the first few dictations are
    /// reviewable; `CloudAIPreferences` upgrades old stored configurations to
    /// `false` rather than failing to decode them.
    public var autoApply: Bool

    public init(
        isEnabled: Bool = false,
        provider: CloudAIProvider = .openAI,
        baseURL: String = CloudAIProvider.openAI.defaultBaseURL ?? "",
        model: String = CloudAIProvider.openAI.defaultModel ?? "",
        prompt: String = CloudAIPromptTemplate.cleanUp.text,
        autoApply: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.prompt = prompt
        self.autoApply = autoApply
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case provider
        case baseURL
        case model
        case prompt
        case autoApply
    }

    /// Decoded field by field so that adding a preference never invalidates a
    /// configuration already on disk. Synthesised decoding would throw on the
    /// missing `autoApply` key, and `CloudAIPreferences.load` would silently
    /// hand back a default configuration — turning the feature off and losing
    /// the user's endpoint and prompt.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CloudAIConfiguration()
        isEnabled = try container.decodeIfPresent(
            Bool.self, forKey: .isEnabled
        ) ?? fallback.isEnabled
        provider = try container.decodeIfPresent(
            CloudAIProvider.self, forKey: .provider
        ) ?? fallback.provider
        baseURL = try container.decodeIfPresent(
            String.self, forKey: .baseURL
        ) ?? provider.defaultBaseURL ?? ""
        model = try container.decodeIfPresent(
            String.self, forKey: .model
        ) ?? provider.defaultModel ?? ""
        prompt = try container.decodeIfPresent(
            String.self, forKey: .prompt
        ) ?? fallback.prompt
        autoApply = try container.decodeIfPresent(
            Bool.self, forKey: .autoApply
        ) ?? false
    }

    /// Validates the configuration and returns the endpoint to POST to.
    ///
    /// HTTPS is required except for loopback, so a local Ollama install can
    /// stay on `http://127.0.0.1` without opening the LAN.
    public func resolvedEndpoint() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudAIEnhancementError.missingBaseURL
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CloudAIEnhancementError.missingModel
        }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme,
              let host = components.host,
              !host.isEmpty else {
            throw CloudAIEnhancementError.invalidBaseURL(trimmed)
        }
        let isHTTPS = scheme.lowercased() == "https"
        let isLoopbackHTTP = scheme.lowercased() == "http"
            && Self.isLoopback(host)
        guard isHTTPS || isLoopbackHTTP else {
            throw CloudAIEnhancementError.insecureBaseURL(trimmed)
        }
        let base = trimmed.hasSuffix("/")
            ? String(trimmed.dropLast())
            : trimmed
        guard let url = URL(string: base + provider.endpointPath) else {
            throw CloudAIEnhancementError.invalidBaseURL(trimmed)
        }
        return url
    }

    private static func isLoopback(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return lowered == "localhost"
            || lowered == "127.0.0.1"
            || lowered == "::1"
    }

}

// MARK: - Prompts

public struct CloudAIPromptTemplate: Equatable, Sendable {
    public let name: String
    public let text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }

    public static let cleanUp = CloudAIPromptTemplate(
        name: "Clean up",
        text: """
        Clean up this dictated transcript. Fix punctuation, capitalisation, \
        and obvious speech-recognition errors. Preserve the speaker's wording \
        and meaning. Do not add information, do not answer questions in the \
        text, and do not summarise. Reply with the corrected text only.
        """
    )

    public static let tightenUp = CloudAIPromptTemplate(
        name: "Tighten",
        text: """
        Rewrite this dictated transcript to be more concise while preserving \
        every fact and the speaker's intent. Do not add information. Reply \
        with the rewritten text only.
        """
    )

    public static let lecture = CloudAIPromptTemplate(
        name: "Lecture summary",
        text: """
        Summarize this lecture transcript. Use only the words in the \
        transcript. Do not invent speakers, names, or facts.

        Reply with three sections:
        1. Outline — the main topics in order
        2. Key terms — important words or definitions
        3. Questions asked — questions that appear in the text. If none, \
        write "None."

        Do not label speakers as teacher or student. Reply with the summary \
        only.
        """
    )

    public static let builtIns: [CloudAIPromptTemplate] = [
        .cleanUp, .tightenUp
    ]
}

// MARK: - Request construction

/// The exact bytes ZenVoice will send, built without touching the network.
///
/// Keeping construction pure is what makes the privacy rule in ADR 0011
/// testable: a check can encode a request and assert that app identity,
/// context, and audio never appear in it.
public struct CloudAIRequest: Equatable, Sendable {
    public let url: URL
    public let provider: CloudAIProvider
    public let model: String
    public let systemPrompt: String
    public let userContent: String

    /// The JSON body. Only the model, the prompt, and the transcript appear —
    /// no app identity, no bundle ID, no surrounding text, no device or
    /// install identifier, no telemetry.
    public func encodedBody() throws -> Data {
        let body = provider.requestBody(
            model: model,
            systemPrompt: systemPrompt,
            userContent: userContent
        )
        return try JSONSerialization.data(
            withJSONObject: body,
            options: [.sortedKeys]
        )
    }

    /// Builds the URLRequest. The API key is passed in rather than stored on
    /// the request so it is never part of an `Equatable` value that could be
    /// logged or diffed.
    public func urlRequest(apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let auth = provider.authHeader(apiKey: apiKey)
        request.setValue(auth.value, forHTTPHeaderField: auth.field)
        for (field, value) in provider.extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try encodedBody()
        request.timeoutInterval = 30
        // Nothing about this request should be reused or cached.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false
        return request
    }
}

// MARK: - Transport

/// The single seam through which ZenVoice touches the network.
///
/// One method, one verb, one destination. Checks inject a fake so the rest of
/// the feature is testable without a live endpoint.
public protocol CloudAITransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionCloudAITransport: CloudAITransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.httpAdditionalHeaders = [:]
            self.session = URLSession(configuration: configuration)
        }
    }

    public func send(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudAIEnhancementError.malformedResponse
        }
        return (data, http)
    }
}

// MARK: - Engine

public struct CloudAIEnhancementResult: Equatable, Sendable {
    public let original: String
    public let enhanced: String

    public init(original: String, enhanced: String) {
        self.original = original
        self.enhanced = enhanced
    }

    /// Whether the model actually changed anything worth previewing.
    public var isChanged: Bool {
        original.trimmingCharacters(in: .whitespacesAndNewlines)
            != enhanced.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Sends a transcript to the configured provider and returns the result for
/// preview. Nothing is applied automatically — see ADR 0011.
public struct CloudAIEnhancementEngine: Sendable {
    private let transport: CloudAITransport

    public init(transport: CloudAITransport = URLSessionCloudAITransport()) {
        self.transport = transport
    }

    /// Builds the request for a transcript without sending it.
    public func makeRequest(
        transcript: String,
        configuration: CloudAIConfiguration
    ) throws -> CloudAIRequest {
        guard configuration.isEnabled else {
            throw CloudAIEnhancementError.disabled
        }
        let trimmed = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            throw CloudAIEnhancementError.emptyTranscript
        }
        return CloudAIRequest(
            url: try configuration.resolvedEndpoint(),
            provider: configuration.provider,
            model: configuration.model,
            systemPrompt: configuration.prompt,
            userContent: trimmed
        )
    }

    public func enhance(
        transcript: String,
        configuration: CloudAIConfiguration,
        apiKey: String
    ) async throws -> CloudAIEnhancementResult {
        let resolvedKey =
            apiKey.isEmpty && !configuration.provider.requiresAPIKey
            ? "ollama"
            : apiKey
        guard !resolvedKey.isEmpty else {
            throw CloudAIEnhancementError.missingAPIKey
        }
        let request = try makeRequest(
            transcript: transcript,
            configuration: configuration
        )

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(
                request.urlRequest(apiKey: resolvedKey)
            )
        } catch let error as CloudAIEnhancementError {
            throw error
        } catch {
            throw CloudAIEnhancementError.transport(error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw CloudAIEnhancementError.provider(
                status: response.statusCode,
                message: Self.providerMessage(from: data)
            )
        }

        let enhanced = try Self.firstMessageContent(
            from: data,
            provider: configuration.provider
        )
        return CloudAIEnhancementResult(
            original: transcript,
            enhanced: enhanced
        )
    }

    /// Extracts the assistant text from a provider response.
    public static func firstMessageContent(
        from data: Data,
        provider: CloudAIProvider = .openAI
    ) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any],
              let content = provider.extractContent(from: object) else {
            throw CloudAIEnhancementError.malformedResponse
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudAIEnhancementError.malformedResponse
        }
        return trimmed
    }

    /// Best-effort provider error text, for the user-facing message.
    public static func providerMessage(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any] else {
            return ""
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return ""
    }
}
