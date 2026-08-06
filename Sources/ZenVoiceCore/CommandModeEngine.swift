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

/// A deterministic phrase-to-action parser for voice command mode.
///
/// The engine only parses text into `CommandAction` values. It never executes
/// the action itself, so the parser can be tested, audited, and run inside the
/// process without needing permission-sensitive frameworks.
public struct CommandModeEngine: Sendable {
    public init() {}

    /// Parses a transcript against a command manifest.
    ///
    /// Matching is deterministic and local:
    /// - The transcript is normalized (lowercased, whitespace collapsed).
    /// - Each mapping is checked in manifest order.
    /// - Within a mapping, the longest phrase is tried first to avoid a short
    ///   phrase swallowing a longer command.
    /// - A match requires the phrase to sit on word boundaries (whitespace or
    ///   string edges), so "open safari" does not match inside
    ///   "open safari settings".
    ///
    /// Returns `.none` if no phrase matches.
    public func parse(
        transcript: String,
        manifest: CommandManifest?
    ) -> CommandAction {
        guard let manifest, !manifest.mappings.isEmpty else {
            return .none
        }
        let normalized = Self.normalized(transcript)
        guard !normalized.isEmpty else {
            return .none
        }

        for mapping in manifest.mappings {
            let phrases = mapping.phrases
                .map(Self.normalized)
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }
            for phrase in phrases {
                if Self.containsPhrase(normalized, phrase: phrase) {
                    return mapping.action
                }
            }
        }
        return .none
    }

    /// A built-in manifest with safe, read-only commands.
    ///
    /// These commands map to actions that the app layer can choose to execute in
    /// later phases. The parser itself never triggers execution.
    public static var defaultManifest: CommandManifest {
        CommandManifest(mappings: [
            CommandMapping(
                phrases: [
                    "open safari",
                    "launch safari"
                ],
                action: .launchApp(
                    bundleID: "com.apple.Safari"
                )
            ),
            CommandMapping(
                phrases: [
                    "open mail",
                    "launch mail",
                    "open apple mail"
                ],
                action: .launchApp(
                    bundleID: "com.apple.mail"
                )
            ),
            CommandMapping(
                phrases: [
                    "copy last transcript",
                    "copy what i said",
                    "copy last dictation"
                ],
                action: .systemAction(.copyLastTranscript)
            ),
            CommandMapping(
                phrases: [
                    "paste last dictation",
                    "paste what i said"
                ],
                action: .systemAction(.pasteLastDictation)
            ),
            CommandMapping(
                phrases: [
                    "open zen voice settings",
                    "open zen voice preferences",
                    "show zen voice settings"
                ],
                action: .systemAction(.showPreferences)
            ),
            CommandMapping(
                phrases: [
                    "lock screen",
                    "lock my mac"
                ],
                action: .systemAction(.lockScreen)
            ),
            CommandMapping(
                phrases: [
                    "search selected text",
                    "search the selected text",
                    "look up selected text"
                ],
                action: .systemAction(.searchSelectedText)
            ),
            CommandMapping(
                phrases: [
                    "turn up the volume",
                    "increase volume",
                    "volume up"
                ],
                action: .systemAction(.increaseVolume)
            ),
            CommandMapping(
                phrases: [
                    "turn down the volume",
                    "decrease volume",
                    "volume down"
                ],
                action: .systemAction(.decreaseVolume)
            ),
            CommandMapping(
                phrases: [
                    "mute",
                    "mute the volume"
                ],
                action: .systemAction(.mute)
            ),
            CommandMapping(
                phrases: [
                    "increase brightness",
                    "brightness up",
                    "turn up brightness"
                ],
                action: .systemAction(.increaseBrightness)
            ),
            CommandMapping(
                phrases: [
                    "decrease brightness",
                    "brightness down",
                    "turn down brightness"
                ],
                action: .systemAction(.decreaseBrightness)
            ),
            CommandMapping(
                phrases: [
                    "sleep displays",
                    "sleep the displays",
                    "turn off the screen"
                ],
                action: .systemAction(.sleepDisplays)
            )
        ])
    }

    private static func normalized(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func containsPhrase(_ text: String, phrase: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = "(?<!\\\\S)\(escaped)(?!\\\\S)"
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: []
        ) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.firstMatch(in: text, options: [], range: range) != nil
    }
}

/// A user-editable collection of phrase-to-action mappings.
///
/// The manifest is intentionally separate from the parser so the same parser
/// can be tested with default, custom, or empty manifests without changing
/// behavior.
public struct CommandManifest: Equatable, Sendable, Codable {
    public var mappings: [CommandMapping]

    public init(mappings: [CommandMapping]) {
        self.mappings = mappings
    }
}

/// A single phrase-to-action mapping.
///
/// Multiple phrases can trigger the same action. Phrases are normalized before
/// matching, so punctuation and extra spaces in the manifest are ignored.
public struct CommandMapping: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public var phrases: [String]
    public var action: CommandAction

    public init(
        id: UUID = UUID(),
        phrases: [String],
        action: CommandAction
    ) {
        self.id = id
        self.phrases = phrases
        self.action = action
    }
}
