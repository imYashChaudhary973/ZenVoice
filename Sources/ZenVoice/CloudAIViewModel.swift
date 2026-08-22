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

import AppKit
import Combine
import Foundation
import ZenVoiceCore

/// Drives the Cloud AI Enhancement screen.
///
/// Nothing here reaches the network until the user has both enabled the
/// feature and stored a key, and no enhanced text replaces anything without an
/// explicit accept (ADR 0011).
@MainActor
final class CloudAIViewModel: ObservableObject {
    @Published private(set) var configuration: CloudAIConfiguration
    @Published private(set) var hasStoredKey: Bool
    @Published var apiKeyDraft = ""
    @Published private(set) var isEnhancing = false
    @Published private(set) var preview: CloudAIEnhancementResult?
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let keyStore: CloudAIKeyStoring
    private let engine: CloudAIEnhancementEngine
    private let lastTranscript: () -> String
    private let applyEnhanced: (String) -> Void

    init(
        keyStore: CloudAIKeyStoring,
        engine: CloudAIEnhancementEngine = CloudAIEnhancementEngine(),
        lastTranscript: @escaping () -> String,
        applyEnhanced: @escaping (String) -> Void
    ) {
        self.keyStore = keyStore
        self.engine = engine
        self.lastTranscript = lastTranscript
        self.applyEnhanced = applyEnhanced
        configuration = CloudAIPreferences.load()
        hasStoredKey = ((try? keyStore.loadKey()) ?? nil) != nil
    }

    var isReady: Bool {
        configuration.isEnabled
            && (hasStoredKey || !configuration.provider.requiresAPIKey)
            && (try? configuration.resolvedEndpoint()) != nil
    }

    var providerDetail: String {
        guard configuration.isEnabled else {
            return "Nothing is sent. Everything stays on this Mac."
        }
        if configuration.provider == .ollama {
            return "Transcript text is sent to Ollama on this Mac."
        }
        return "Transcript text is sent to \(configuration.provider.displayName)."
    }

    // MARK: - Configuration

    func setEnabled(_ enabled: Bool) {
        configuration.isEnabled = enabled
        persist()
        if !enabled {
            // The key stays in the Keychain. Deleting it here made the toggle
            // destructive: flipping the feature off to compare output, or
            // switching formatting away from Cloud and back, silently threw
            // away a credential the user had to go and re-issue. Nothing is
            // sent while the feature is off, and "Remove" deletes the key
            // outright for anyone who wants it gone.
            preview = nil
            statusMessage = hasStoredKey
                ? "Cloud AI is off. Nothing is sent. Your key is still in the "
                    + "Keychain — use Remove to delete it."
                : "Cloud AI is off. Nothing is sent."
        }
    }

    /// Whether an enhanced transcript replaces the local one without asking.
    func setAutoApply(_ autoApply: Bool) {
        configuration.autoApply = autoApply
        persist()
        statusMessage = autoApply
            ? "Enhanced text will be applied automatically after each dictation."
            : "You will be asked to review each enhancement before it applies."
    }

    func setProvider(_ provider: CloudAIProvider) {
        configuration.provider = provider
        if let base = provider.defaultBaseURL {
            configuration.baseURL = base
        }
        if let model = provider.defaultModel {
            configuration.model = model
        }
        persist()
    }

    func setBaseURL(_ value: String) {
        configuration.baseURL = value
        persist()
    }

    func setModel(_ value: String) {
        configuration.model = value
        persist()
    }

    func setPrompt(_ value: String) {
        configuration.prompt = value
        persist()
    }

    func applyTemplate(_ template: CloudAIPromptTemplate) {
        setPrompt(template.text)
    }

    private func persist() {
        CloudAIPreferences.save(configuration)
        objectWillChange.send()
    }

    // MARK: - Key

    func saveKey() {
        do {
            try keyStore.saveKey(apiKeyDraft)
            hasStoredKey = ((try? keyStore.loadKey()) ?? nil) != nil
            apiKeyDraft = ""
            statusMessage = hasStoredKey
                ? "Key saved to the Keychain."
                : "Key cleared."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteKey() {
        do {
            try keyStore.deleteKey()
            hasStoredKey = false
            apiKeyDraft = ""
            statusMessage = "Key removed from the Keychain."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Preview

    /// Enhances the most recent transcript and shows the result for comparison.
    /// Nothing is applied until the user accepts.
    func enhanceLastTranscript() {
        let transcript = lastTranscript()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            errorMessage = "Dictate something first, then try again."
            return
        }
        guard let key = ((try? keyStore.loadKey()) ?? nil), !key.isEmpty else {
            errorMessage = CloudAIEnhancementError.missingAPIKey
                .localizedDescription
            return
        }

        isEnhancing = true
        errorMessage = nil
        statusMessage = nil
        preview = nil

        let configuration = configuration
        let engine = engine
        Task { [weak self] in
            do {
                let result = try await engine.enhance(
                    transcript: transcript,
                    configuration: configuration,
                    apiKey: key
                )
                await MainActor.run {
                    self?.isEnhancing = false
                    self?.preview = result
                    if !result.isChanged {
                        self?.statusMessage =
                            "The provider returned the same text."
                    }
                }
            } catch {
                await MainActor.run {
                    self?.isEnhancing = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func acceptPreview() {
        guard let preview else { return }
        applyEnhanced(preview.enhanced)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preview.enhanced, forType: .string)
        self.preview = nil
        statusMessage = "Enhanced text copied and set as the last transcript."
    }

    func discardPreview() {
        preview = nil
        statusMessage = "Kept the local transcript."
    }
}
