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

// MARK: - Providers

/// A hosted provider ZenVoice can send a transcript to, when the user opts in.
///
/// All three speak the same OpenAI-style chat-completions shape. `custom`
/// exists so a user can point at a self-hosted or local endpoint and keep the
/// data on infrastructure they control.
public enum CloudAIProvider: String, Codable, CaseIterable, Sendable {
    case openAI
    case groq
    case custom

    public var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .groq:
            return "Groq"
        case .custom:
            return "Custom endpoint"
        }
    }

    /// The endpoint used when the user has not supplied one. `custom` has no
    /// default on purpose — the user must state where their data is going.
    public var defaultBaseURL: String? {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1"
        case .groq:
            return "https://api.groq.com/openai/v1"
        case .custom:
            return nil
        }
    }

    public var defaultModel: String? {
        switch self {
        case .openAI:
            return "gpt-4o-mini"
        case .groq:
            return "llama-3.3-70b-versatile"
        case .custom:
            return nil
        }
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

    public init(
        isEnabled: Bool = false,
        provider: CloudAIProvider = .openAI,
        baseURL: String = CloudAIProvider.openAI.defaultBaseURL ?? "",
        model: String = CloudAIProvider.openAI.defaultModel ?? "",
        prompt: String = CloudAIPromptTemplate.cleanUp.text
    ) {
        self.isEnabled = isEnabled
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.prompt = prompt
    }

    /// Validates the configuration and returns the endpoint to POST to.
    ///
    /// HTTPS is required here rather than at the call site so no caller can
    /// skip it, including for `custom` providers.
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
              components.host?.isEmpty == false else {
            throw CloudAIEnhancementError.invalidBaseURL(trimmed)
        }
        guard scheme.lowercased() == "https" else {
            throw CloudAIEnhancementError.insecureBaseURL(trimmed)
        }
        let base = trimmed.hasSuffix("/")
            ? String(trimmed.dropLast())
            : trimmed
        guard let url = URL(string: base + "/chat/completions") else {
            throw CloudAIEnhancementError.invalidBaseURL(trimmed)
        }
        return url
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
    public let model: String
    public let systemPrompt: String
    public let userContent: String

    /// The JSON body. Only the model, the prompt, and the transcript appear —
    /// no app identity, no bundle ID, no surrounding text, no device or
    /// install identifier, no telemetry.
    public func encodedBody() throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]
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
        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )
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
        guard !apiKey.isEmpty else {
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
                request.urlRequest(apiKey: apiKey)
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

        let enhanced = try Self.firstMessageContent(from: data)
        return CloudAIEnhancementResult(
            original: transcript,
            enhanced: enhanced
        )
    }

    /// Extracts `choices[0].message.content`.
    public static func firstMessageContent(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
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
