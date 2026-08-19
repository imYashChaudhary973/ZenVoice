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

/// Write Mode sub-modes.
public enum WriteModeSubMode: String, Codable, CaseIterable, Sendable {
    case compose
    case rewrite

    public var displayName: String {
        switch self {
        case .compose:
            return "Compose"
        case .rewrite:
            return "Rewrite"
        }
    }
}

/// Persistent global preference for Write Mode.
public enum WriteModePreferences {
    public static let subModeKey = "ZenVoice.writeMode.subMode"
    public static let defaultPromptKey = "ZenVoice.writeMode.defaultPrompt"

    public static func loadSubMode(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> WriteModeSubMode {
        guard let rawValue = defaults.string(forKey: subModeKey),
              let mode = WriteModeSubMode(rawValue: rawValue) else {
            return .compose
        }
        return mode
    }

    public static func saveSubMode(
        _ mode: WriteModeSubMode,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(mode.rawValue, forKey: subModeKey)
    }

    public static func defaultPrompt(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> String {
        defaults.string(forKey: defaultPromptKey)
            ?? "Rewrite the selected text for clarity and concision."
    }

    public static func saveDefaultPrompt(
        _ prompt: String,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(prompt, forKey: defaultPromptKey)
    }
}

/// Request to read the current selection or focused text.
public struct WriteModeReadRequest: Sendable {
    public let sourceBundleIdentifier: String?
    public let fallbackToClipboard: Bool

    public init(
        sourceBundleIdentifier: String? = nil,
        fallbackToClipboard: Bool = true
    ) {
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.fallbackToClipboard = fallbackToClipboard
    }
}

/// Result of reading the current selection or focused text.
public struct WriteModeReadResult: Equatable, Sendable {
    public let text: String
    public let source: WriteModeReadSource
    public let isVerified: Bool

    public init(
        text: String,
        source: WriteModeReadSource,
        isVerified: Bool
    ) {
        self.text = text
        self.source = source
        self.isVerified = isVerified
    }
}

public enum WriteModeReadSource: String, Equatable, Sendable {
    case accessibility
    case clipboard
}

/// A type that reads the current selection or focused text.
///
/// The concrete implementation lives in the app target because it requires
/// Accessibility or clipboard access. The core module defines the interface.
public protocol WriteModeTextReader: Sendable {
    func read(_ request: WriteModeReadRequest) async throws -> WriteModeReadResult
}

/// Result of a Write Mode rewrite.
public struct WriteModeRewriteResult: Equatable, Sendable {
    public let text: String
    public let wasRejected: Bool
    public let requiresPreview: Bool
    public let changeDescription: String

    public init(
        text: String,
        wasRejected: Bool,
        requiresPreview: Bool,
        changeDescription: String
    ) {
        self.text = text
        self.wasRejected = wasRejected
        self.requiresPreview = requiresPreview
        self.changeDescription = changeDescription
    }
}

/// Engine that drives Write Mode compose and rewrite behavior.
///
/// Compose simply returns the transcript unchanged. Rewrite reads the current
/// selection, runs it through ZenIntelligence with a user prompt, and checks
/// whether a preview is required before the app target applies the replacement.
public struct WriteModeEngine: Sendable {
    public init() {}

    /// Composes text at the caret.
    ///
    /// In the `.compose` sub-mode the transcript is inserted exactly like
    /// normal dictation. This helper exists so the caller can switch behavior
    /// without branching on the sub-mode everywhere.
    public func compose(transcript: String) -> WriteModeRewriteResult {
        WriteModeRewriteResult(
            text: transcript,
            wasRejected: false,
            requiresPreview: false,
            changeDescription: "compose"
        )
    }

    /// Rewrites the current selection using the provided prompt.
    ///
    /// - Parameters:
    ///   - selectedText: the text read from Accessibility or clipboard.
    ///   - prompt: the user prompt describing the desired rewrite.
    ///   - mode: the ZenIntelligence mode used for the rewrite.
    ///   - languageCode: language code for locale-aware processing.
    /// - Returns: a `WriteModeRewriteResult`. `requiresPreview` is true when
    ///   the change is large enough that the UI should show a diff first.
    public func rewrite(
        selectedText: String,
        prompt: String,
        mode: ZenIntelligenceMode,
        languageCode: String = "en"
    ) -> WriteModeRewriteResult {
        guard !selectedText.isEmpty else {
            return WriteModeRewriteResult(
                text: selectedText,
                wasRejected: true,
                requiresPreview: false,
                changeDescription: "No text was selected."
            )
        }

        // Combine prompt with selection to form the input text. The
        // ZenIntelligence engine treats the prompt as context when in
        // contextAware mode.
        let context = NextDictationContext.sanitized(prompt)
        let enhanced = ZenIntelligenceEngine().enhance(
            selectedText,
            mode: mode == .off ? .format : mode,
            languageCode: languageCode,
            context: context
        )

        let requiresPreview = Self.requiresPreview(
            original: selectedText,
            rewritten: enhanced.text
        )

        return WriteModeRewriteResult(
            text: enhanced.text,
            wasRejected: enhanced.wasRejected,
            requiresPreview: requiresPreview,
            changeDescription: enhanced.changeDescription
        )
    }

    /// Checks whether a rewrite is large enough to require a preview.
    ///
    /// The threshold is 200 characters or a 30% change ratio.
    private static func requiresPreview(original: String, rewritten: String) -> Bool {
        let maxLength = max(original.count, 1)
        let distance = levenshtein(original, rewritten)
        let ratio = Double(distance) / Double(maxLength)
        return rewritten.count > 200 || ratio > 0.30
    }
}

/// Simple Levenshtein distance for preview thresholding.
private func levenshtein(_ source: String, _ target: String) -> Int {
    let a = Array(source)
    let b = Array(target)
    let m = a.count
    let n = b.count
    guard m > 0 else { return n }
    guard n > 0 else { return m }

    var previous = Array(0...n)
    var current = Array(repeating: 0, count: n + 1)

    for i in 1...m {
        current[0] = i
        for j in 1...n {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            current[j] = min(
                current[j - 1] + 1,
                previous[j] + 1,
                previous[j - 1] + cost
            )
        }
        swap(&previous, &current)
    }
    return previous[n]
}
