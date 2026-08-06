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
/// - `smart`:    local cleanup plus formatting (capitalisation, numbers,
///               whitespace). The implementation is currently deterministic;
///               the rung name is reserved for when a local model replaces it.
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
            return "Clean up plus capitalisation, number formatting, and spacing."
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
    public var zenIntelligenceMode: ZenIntelligenceMode {
        switch self {
        case .off, .clean:
            return .off
        case .smart, .cloud:
            return .format
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

    public init(
        text: String,
        mode: TranscriptFormattingMode,
        changed: Bool,
        cloudUsed: Bool = false
    ) {
        self.text = text
        self.mode = mode
        self.changed = changed
        self.cloudUsed = cloudUsed
    }
}

/// Unified formatting engine.
///
/// For `.off`, `.clean`, and `.smart` the work is synchronous and stays on the
/// Mac. For `.cloud` the work is asynchronous and requires a valid API key;
/// failures throw so the caller can fall back to the local transcript.
public struct TranscriptFormattingEngine: Sendable {
    public init() {}

    /// Formats a transcript synchronously for the local rungs.
    ///
    /// Returns the original text unchanged for `.cloud` so the caller can
    /// decide whether to invoke the async cloud path.
    public func format(
        _ transcript: String,
        mode: TranscriptFormattingMode,
        languageCode: String = "en",
        voiceCommandsEnabled: Bool = false,
        context: String? = nil
    ) -> TranscriptFormattingResult {
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

        let intelligenceMode = mode.zenIntelligenceMode
        var finalText = localText
        if intelligenceMode != .off {
            let enhanced = ZenIntelligenceEngine().enhance(
                localText,
                mode: intelligenceMode,
                languageCode: languageCode,
                context: context
            )
            finalText = enhanced.wasRejected ? localText : enhanced.text
        }

        return TranscriptFormattingResult(
            text: finalText,
            mode: mode,
            changed: finalText != transcript
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
            return format(
                transcript,
                mode: mode,
                languageCode: languageCode,
                voiceCommandsEnabled: voiceCommandsEnabled,
                context: context
            )
        }

        let local = format(
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
