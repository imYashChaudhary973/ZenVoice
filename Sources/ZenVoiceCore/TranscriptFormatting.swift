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

/// A single formatting ladder that replaces the overlapping Instant Refine
/// and ZenIntelligence toggles.
///
/// - `off`:      keep the local transcript unchanged.
/// - `clean`:    deterministic cleanup (fillers, restarts, punctuation).
/// - `smart`:    local cleanup followed by Apple's on-device language model
///               behind strict semantic guards. It falls back to the existing
///               deterministic formatter when the model is unavailable.
/// - `cloud`:    send the transcript to the configured cloud provider for
///               enhancement, with a preview/apply step so the original is
///               never lost.
public enum TranscriptFormattingMode: String, Codable, CaseIterable, Sendable {
    case off
    case clean
    case smart
    case cloud

    public var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .clean:
            return "Clean"
        case .smart:
            return "Smart"
        case .cloud:
            return "Cloud"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            return "Keep the transcript exactly as the decoder produced it."
        case .clean:
            return "Remove fillers, repeated words, and clear spoken restarts."
        case .smart:
            return "Use the on-device model for punctuation and layout, with a local fallback."
        case .cloud:
            return "Enhance the transcript with the configured cloud provider."
        }
    }

    /// The Instant Refine mode that corresponds to this formatting rung.
    /// Used while the pipeline is being migrated to the single enum.
    public var instantRefineMode: InstantRefineMode {
        switch self {
        case .off:
            return .off
        case .clean, .smart, .cloud:
            return .clean
        }
    }

    /// The ZenIntelligence mode that corresponds to this formatting rung.
    ///
    /// Smart maps to `.contextAware`, not `.format`. `.format` left the
    /// context join unreachable: nothing returned `.contextAware`, so the
    /// `context:` argument threaded from `AppDelegate` through
    /// `TranscriptFormattingEngine` and `WriteModeEngine` was accepted and
    /// then ignored at every call site. Two things were wrong with that.
    /// Anyone migrated from ZenIntelligence = Context Aware — which the
    /// migration maps onto Smart — silently lost sentence joining with no
    /// setting left to restore it. And ADR 0007 describes Smart as
    /// "capitalisation, number formatting, spacing, and a conservative context
    /// join", which was no longer true of the code.
    ///
    /// The join is conservative by construction: it does nothing unless
    /// `NextDictationContext.sanitized` yields a non-empty context, and the
    /// meaning guard still rejects a destructive candidate.
    public var zenIntelligenceMode: ZenIntelligenceMode {
        switch self {
        case .off, .clean:
            return .off
        case .smart, .cloud:
            return .contextAware
        }
    }

    /// Builds a formatting mode from the old independent toggles.
    ///
    /// Used while per-application profiles still store the legacy fields.
    public static func from(
        instantRefine: InstantRefineMode,
        zenIntelligence: ZenIntelligenceMode?
    ) -> TranscriptFormattingMode {
        if zenIntelligence == .format || zenIntelligence == .contextAware {
            return .smart
        }
        switch instantRefine {
        case .off:
            return .off
        case .clean, .agentPrompt:
            return .clean
        }
    }
}

/// Persistent preference for the unified formatting ladder.
public enum TranscriptFormattingPreferences {
    public static let preferenceKey = "ZenVoice.formatting.mode"
    public static let migratedKey = "ZenVoice.formatting.migrated"

    public static func load(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> TranscriptFormattingMode {
        migrateIfNeeded(defaults: defaults)
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let mode = TranscriptFormattingMode(rawValue: rawValue) else {
            return .clean
        }
        return mode
    }

    public static func save(
        _ mode: TranscriptFormattingMode,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(mode.rawValue, forKey: preferenceKey)
    }

    /// One-time migration from the old Instant Refine / ZenIntelligence ladder.
    ///
    /// The old settings were independent, so this picks the highest rung that
    /// was active. A user who had ZenIntelligence enabled moves to Smart; a
    /// user who only had Instant Refine stays on Clean.
    public static func migrateIfNeeded(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        let instantRefine = InstantRefinePreferences.load(defaults: defaults)
        let zenIntelligence = ZenIntelligencePreferences.load(defaults: defaults)

        let mode: TranscriptFormattingMode
        switch (instantRefine, zenIntelligence) {
        case (.off, .off):
            mode = .off
        case (_, .format), (_, .contextAware):
            mode = .smart
        case (.agentPrompt, _):
            // Agent prompt handled layout commands; those moved to Commands.
            mode = .clean
        case (.clean, .off):
            mode = .clean
        case (.off, _):
            mode = .off
        }

        save(mode, defaults: defaults)
        defaults.set(true, forKey: migratedKey)
    }
}

/// The result of a formatting pass.
public struct TranscriptFormattingResult: Equatable, Sendable {
    public let text: String
    public let mode: TranscriptFormattingMode
    public let changed: Bool
    public let cloudUsed: Bool
    public let localModelUsed: Bool
    public let smartFallback: SmartFormattingFallback?

    public init(
        text: String,
        mode: TranscriptFormattingMode,
        changed: Bool,
        cloudUsed: Bool = false,
        localModelUsed: Bool = false,
        smartFallback: SmartFormattingFallback? = nil
    ) {
        self.text = text
        self.mode = mode
        self.changed = changed
        self.cloudUsed = cloudUsed
        self.localModelUsed = localModelUsed
        self.smartFallback = smartFallback
    }
}

/// Unified formatting engine.
///
/// For `.off` and `.clean` work stays deterministic. `.smart` invokes the
/// on-device model asynchronously; `.cloud` requires a valid API key.
public struct TranscriptFormattingEngine: Sendable {
    private let smartFormatter: SmartFormattingEngine

    public init(
        localModel: any LocalLanguageModel = AppleOnDeviceLanguageModel()
    ) {
        self.smartFormatter = SmartFormattingEngine(model: localModel)
    }

    /// Formats a transcript for the local rungs. Cloud uses the same guarded
    /// local formatter when its provider path is not invoked or accepted.
    public func format(
        _ transcript: String,
        mode: TranscriptFormattingMode,
        languageCode: String = "en",
        voiceCommandsEnabled: Bool = false,
        context: String? = nil
    ) async -> TranscriptFormattingResult {
        guard mode != .off else {
            return TranscriptFormattingResult(
                text: transcript,
                mode: .off,
                changed: false
            )
        }

        let refined = TranscriptRefinement.refine(
            transcript,
            mode: mode.instantRefineMode,
            languageCode: languageCode,
            voiceCommandsEnabled: voiceCommandsEnabled
        )
        let localText = refined.wasRejected ? transcript : refined.text

        var finalText = localText
        var localModelUsed = false
        var smartFallback: SmartFormattingFallback?
        if mode == .smart {
            let smart = await smartFormatter.format(
                localText,
                languageCode: languageCode,
                context: context
            )
            finalText = smart.text
            localModelUsed = smart.modelUsed
            smartFallback = smart.fallback
        } else {
            let intelligenceMode = mode.zenIntelligenceMode
            if intelligenceMode != .off {
                let enhanced = ZenIntelligenceEngine().enhance(
                    localText,
                    mode: intelligenceMode,
                    languageCode: languageCode,
                    context: context
                )
                finalText = enhanced.wasRejected ? localText : enhanced.text
            }
        }

        // Normalize common colloquial phrases and acoustic homophones
        finalText = BuiltInSlangLexicon.normalizeColloquialPhrases(finalText)

        return TranscriptFormattingResult(
            text: finalText,
            mode: mode,
            changed: finalText != transcript,
            localModelUsed: localModelUsed,
            smartFallback: smartFallback
        )
    }

    /// Formats a transcript asynchronously, including the cloud rung.
    ///
    /// For `.cloud` this sends the already-cleaned local transcript to the
    /// configured provider and returns the enhanced text. The original is
    /// preserved inside `result.text` only if enhancement succeeds; on failure
    /// the caller should keep the original.
    public func format(
        _ transcript: String,
        mode: TranscriptFormattingMode,
        languageCode: String = "en",
        voiceCommandsEnabled: Bool = false,
        context: String? = nil,
        cloudConfiguration: CloudAIConfiguration,
        apiKey: String
    ) async throws -> TranscriptFormattingResult {
        guard mode == .cloud else {
            return await format(
                transcript,
                mode: mode,
                languageCode: languageCode,
                voiceCommandsEnabled: voiceCommandsEnabled,
                context: context
            )
        }

        let local = await format(
            transcript,
            mode: .clean,
            languageCode: languageCode,
            voiceCommandsEnabled: voiceCommandsEnabled,
            context: context
        )

        let enhanced = try await CloudAIEnhancementEngine().enhance(
            transcript: local.text,
            configuration: cloudConfiguration,
            apiKey: apiKey
        )

        return TranscriptFormattingResult(
            text: enhanced.enhanced,
            mode: .cloud,
            changed: enhanced.isChanged,
            cloudUsed: true
        )
    }
}
