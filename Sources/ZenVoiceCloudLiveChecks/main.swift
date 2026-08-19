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
import Security
import ZenVoiceCore

// ZenVoiceCloudLiveChecks — closes the Phase 6 live-endpoint item.
//
// Deterministic request-shape and response-parse coverage already lives in
// ZenVoiceCoreChecks against fixtures. What was missing is evidence against
// the real wire: OpenAI, Groq, and Anthropic had never answered a request
// this app built. This executable sends one real enhancement per provider
// through the exact production path —
//
//     CloudAIEnhancementEngine.makeRequest
//   → CloudAIRequest.urlRequest(apiKey:)
//   → URLSessionCloudAITransport.send
//   → CloudAIEnhancementEngine.firstMessageContent
//
// so a wire-shape drift at any provider fails here before it fails a user.
//
// The API key never touches the command line, the repository, or logs. It is
// read from the production Keychain item the app's Formatting screen writes
// (service "<production bundle id>.vault", account "cloud-ai-api-key"). A
// foreign process cannot mint that identity through RuntimeIdentity — by
// design — so this check queries the item directly, read-only, and never
// writes or deletes it. Storing and removing the key stays a UI action the
// user performs.
//
// Environment:
//   ZENVOICE_CLOUD_LIVE_PROVIDER  required: openai | groq | anthropic | custom
//   ZENVOICE_CLOUD_LIVE_MODEL     optional; defaults to the provider default
//   ZENVOICE_CLOUD_LIVE_BASE_URL  required for custom, optional otherwise
//
// Verifies per run:
//   1. the stored key obtains a 2xx and the per-provider parser returns text
//   2. the Clean up template actually changes a deliberately messy transcript
//   3. a wrong key yields provider(status, message) with a readable message —
//      the failure taxonomy the preview flow surfaces — and never a crash
//
// Exits 0 when every check passes, 1 otherwise. Prints no key material and
// no user dictation; the transcript below is synthetic.

private let environment = ProcessInfo.processInfo.environment

private func report(_ message: String = "") {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("ZenVoiceCloudLiveChecks: \(message)\n").utf8))
    exit(1)
}

/// Reads the app's stored provider key. Direct Keychain query rather than
/// `CloudAIKeychainKeyStore` because the store's service name is derived
/// from `RuntimeIdentity.policy()`, which a CLI process cannot satisfy.
private func storedAPIKey() throws -> String? {
    let service = "\(RuntimeIdentity.productionBundleID).vault"
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "cloud-ai-api-key",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else {
        if status == errSecItemNotFound {
            return nil
        }
        throw CloudAIKeyStoreError.keychain(status)
    }
    guard let data = item as? Data,
          let key = String(data: data, encoding: .utf8),
          !key.isEmpty else {
        throw CloudAIKeyStoreError.invalidKey
    }
    return key
}

/// A messy but non-sensitive dictation: disfluencies, lowercase proper
/// nouns, and missing punctuation — enough that any competent cleanup model
/// must change it, so "enhanced equals input" is a real failure.
private let messyTranscript = """
um okay so the meeting moved to thursday at like 3 pm, can you uh update the \
calendar invite and maybe ping priya about the agenda whatever works for her
"""

private func configuration(
    provider: CloudAIProvider,
    model: String,
    baseURL: String?
) -> CloudAIConfiguration {
    CloudAIConfiguration(
        isEnabled: true,
        provider: provider,
        baseURL: baseURL ?? provider.defaultBaseURL ?? "",
        model: model,
        prompt: CloudAIPromptTemplate.cleanUp.text,
        autoApply: false
    )
}

// MARK: - Checks

/// One live enhancement with the stored key through the production path.
private func checkStoredKey(
    engine: CloudAIEnhancementEngine,
    config: CloudAIConfiguration,
    apiKey: String
) async throws -> Bool {
    let startedAt = Date()
    let result = try await engine.enhance(
        transcript: messyTranscript,
        configuration: config,
        apiKey: apiKey
    )
    let elapsed = Date().timeIntervalSince(startedAt)
    report(
        String(
            format: "  stored key: HTTP 2xx, parsed in %.2fs", elapsed
        )
    )
    report("  enhanced text: \(result.enhanced)")
    guard result.isChanged else {
        report("  FAIL — the model returned the input unchanged")
        return false
    }
    report("  cleanup changed the transcript: yes")
    return true
}

/// A deliberately wrong key must land in the provider-error taxonomy with a
/// message a user can read — never a crash, never a silent success.
private func checkWrongKey(
    engine: CloudAIEnhancementEngine,
    config: CloudAIConfiguration
) async -> Bool {
    let wrongKey = "sk-zenvoice-live-check-deliberately-wrong"
    do {
        let result = try await engine.enhance(
            transcript: messyTranscript,
            configuration: config,
            apiKey: wrongKey
        )
        report(
            "  FAIL — a wrong key was accepted (enhanced: "
                + "\"\(result.enhanced.prefix(80))\")"
        )
        return false
    } catch let error as CloudAIEnhancementError {
        guard case .provider(let status, let message) = error else {
            report(
                "  FAIL — wrong key produced \(error) instead of "
                    + "provider(status, message)"
            )
            return false
        }
        report("  wrong key: provider status \(status)")
        report("  readable message: \(error.localizedDescription)")
        guard (400..<500).contains(status), !message.isEmpty else {
            report(
                "  FAIL — expected a 4xx with a provider message, "
                    + "got \(status) with empty message"
            )
            return false
        }
        return true
    } catch {
        report("  FAIL — wrong key threw a non-taxonomy error: \(error)")
        return false
    }
}

// MARK: - Entry

guard let providerName = environment["ZENVOICE_CLOUD_LIVE_PROVIDER"] else {
    fail(
        "set ZENVOICE_CLOUD_LIVE_PROVIDER to openai, groq, anthropic, or custom"
    )
}

let provider: CloudAIProvider
switch providerName.lowercased() {
case "openai":
    provider = .openAI
case "groq":
    provider = .groq
case "anthropic":
    provider = .anthropic
case "custom":
    provider = .custom
default:
    fail(
        "unknown provider \"\(providerName)\" — use openai, groq, "
            + "anthropic, or custom"
    )
}

let model: String
if let requested = environment["ZENVOICE_CLOUD_LIVE_MODEL"] {
    model = requested
} else if let defaultModel = provider.defaultModel {
    model = defaultModel
} else {
    fail("custom requires ZENVOICE_CLOUD_LIVE_MODEL")
}
let baseURL = environment["ZENVOICE_CLOUD_LIVE_BASE_URL"]

if provider == .custom, baseURL == nil {
    fail("custom requires ZENVOICE_CLOUD_LIVE_BASE_URL")
}

let apiKey: String
do {
    guard let key = try storedAPIKey() else {
        fail(
            "no API key is stored. Open ZenVoice → Formatting → Cloud, "
                + "choose the provider, and save the key; it is read from "
                + "the Keychain, never from the command line."
        )
    }
    apiKey = key
} catch {
    fail("could not read the stored key: \(error.localizedDescription)")
}

let config = configuration(
    provider: provider,
    model: model,
    baseURL: baseURL
)
let endpoint: URL
do {
    endpoint = try config.resolvedEndpoint()
} catch {
    fail("invalid configuration: \(error.localizedDescription)")
}
report("provider: \(provider.displayName)")
report("model:    \(model)")
report("endpoint: \(endpoint.host ?? "?")\(endpoint.path)")

let semaphore = DispatchSemaphore(value: 0)
var passed = true
Task.detached {
    let engine = CloudAIEnhancementEngine(transport: URLSessionCloudAITransport())
    do {
        passed = try await checkStoredKey(
            engine: engine,
            config: config,
            apiKey: apiKey
        )
    } catch {
        report("  FAIL — live request failed: \(error.localizedDescription)")
        passed = false
    }
    if await checkWrongKey(engine: engine, config: config) == false {
        passed = false
    }
    semaphore.signal()
}
semaphore.wait()

if passed {
    report(
        "ZenVoiceCloudLiveChecks passed (\(provider.displayName), \(model))."
    )
    exit(0)
} else {
    report("ZenVoiceCloudLiveChecks FAILED (\(provider.displayName)).")
    exit(1)
}
