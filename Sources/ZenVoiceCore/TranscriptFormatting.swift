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
public enum TranscriptFormattingMode: String, Codable, CaseIterable, Sendable {
    case off
    case clean
    case smart


    public var displayName: String {
        switch self {
        case .off:
            return "Verbatim"
        case .clean:
            return "Clean"
        case .smart:
            return "Polished"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            return "Your exact words, untouched."
        case .clean:
            return "Filter fillers and fix numbers."
        case .smart:
            return "Read like you wrote it. Apple Intelligence on this Mac."
        }
    }

    /// The Instant Refine mode that corresponds to this formatting rung.
    /// Used while the pipeline is being migrated to the single enum.
    public var instantRefineMode: InstantRefineMode {
        switch self {
        case .off:
            return .off
        case .clean, .smart:
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
        case .smart:
            return .contextAware
        }
    }

    /// Builds a formatting mode from the old independent toggles.
    ///
    /// Used to migrate stored independent toggles into one formatting mode.
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

public enum TranscriptTone: String, Codable, CaseIterable, Sendable {
    case auto
    case casual
    case veryCasual
    case neutral
    case professional
    case enthusiastic

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .casual: return "Casual"
        case .veryCasual: return "Very casual"
        case .neutral: return "Neutral"
        case .professional: return "Professional"
        case .enthusiastic: return "Enthusiastic"
        }
    }
}

public enum TranscriptTonePreferences {
    public static let preferenceKey = "ZenVoice.formatting.tone"

    public static func load(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> TranscriptTone {
        guard let raw = defaults.string(forKey: preferenceKey),
              let tone = TranscriptTone(rawValue: raw) else {
            return .auto
        }
        return tone
    }

    public static func save(
        _ tone: TranscriptTone,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(tone.rawValue, forKey: preferenceKey)
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
        guard let rawValue = defaults.string(forKey: preferenceKey) else {
            return .clean
        }
        if rawValue == "cloud" {
            return .smart
        }
        return TranscriptFormattingMode(rawValue: rawValue) ?? .clean
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
            // Re-enable the command pass so installs that relied on "new
            // paragraph" and friends keep them after the rung collapses.
            mode = .clean
            LocalVoiceCommandPreferences.setEnabled(true, defaults: defaults)
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
    public let localModelUsed: Bool
    public let smartFallback: SmartFormattingFallback?

    public init(
        text: String,
        mode: TranscriptFormattingMode,
        changed: Bool,
        localModelUsed: Bool = false,
        smartFallback: SmartFormattingFallback? = nil
    ) {
        self.text = text
        self.mode = mode
        self.changed = changed
        self.localModelUsed = localModelUsed
        self.smartFallback = smartFallback
    }
}

/// Unified formatting engine.
///
/// For `.off` and `.clean` work stays deterministic. `.smart` invokes the
/// on-device model asynchronously.
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
        if mode == .off {
            let commands = LocalVoiceCommandEngine().apply(
                to: transcript,
                languageCode: languageCode,
                isEnabled: voiceCommandsEnabled
            )
            return TranscriptFormattingResult(
                text: commands.text,
                mode: .off,
                changed: commands.text != transcript
            )
        }

        // Normalize common colloquial phrases and acoustic homophones before
        // the guarded stages: every gate must see — and approve — exactly the
        // text that gets delivered.
        let normalized = BuiltInSlangLexicon.normalizeColloquialPhrases(
            transcript
        )

        let refined = TranscriptRefinement.refine(
            normalized,
            mode: mode.instantRefineMode,
            languageCode: languageCode,
            voiceCommandsEnabled: voiceCommandsEnabled
        )
        let localText = refined.wasRejected ? normalized : refined.text

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

        return TranscriptFormattingResult(
            text: finalText,
            mode: mode,
            changed: finalText != transcript,
            localModelUsed: localModelUsed,
            smartFallback: smartFallback
        )
    }

}
