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

public struct ApplicationProfile:
    Codable, Equatable, Identifiable, Sendable
{
    public let bundleIdentifier: String
    public var applicationName: String
    public var languageProfile: LanguageProfile
    public var refinementMode: InstantRefineMode
    public var voiceCommandsEnabled: Bool

    public var id: String { bundleIdentifier }

    public init(
        bundleIdentifier: String,
        applicationName: String,
        languageProfile: LanguageProfile,
        refinementMode: InstantRefineMode,
        voiceCommandsEnabled: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.languageProfile = languageProfile
        self.refinementMode = refinementMode
        self.voiceCommandsEnabled = voiceCommandsEnabled
    }
}

public enum ApplicationProfilePreferences {
    public static let preferenceKey = "ZenVoice.applicationProfiles"

    public static func load(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> [ApplicationProfile] {
        guard let data = defaults.data(forKey: preferenceKey),
              let decoded = try? JSONDecoder().decode(
                [ApplicationProfile].self,
                from: data
              ) else {
            return []
        }
        var seen = Set<String>()
        return decoded.filter {
            !$0.bundleIdentifier.isEmpty
                && LanguageCatalog.isSupported(
                    code: $0.languageProfile.inputLanguageCode
                )
                && seen.insert($0.bundleIdentifier).inserted
        }
    }

    public static func profile(
        for bundleIdentifier: String?,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> ApplicationProfile? {
        guard let bundleIdentifier else {
            return nil
        }
        return load(defaults: defaults).first {
            $0.bundleIdentifier == bundleIdentifier
        }
    }

    public static func save(
        _ profile: ApplicationProfile,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        guard !profile.bundleIdentifier.isEmpty,
              LanguageCatalog.isSupported(
                code: profile.languageProfile.inputLanguageCode
              ) else {
            return
        }
        var profiles = load(defaults: defaults)
        if let index = profiles.firstIndex(where: {
            $0.bundleIdentifier == profile.bundleIdentifier
        }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist(profiles, defaults: defaults)
    }

    public static func remove(
        bundleIdentifier: String,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        persist(
            load(defaults: defaults).filter {
                $0.bundleIdentifier != bundleIdentifier
            },
            defaults: defaults
        )
    }

    private static func persist(
        _ profiles: [ApplicationProfile],
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(profiles) else {
            return
        }
        defaults.set(data, forKey: preferenceKey)
    }
}

public enum LocalVoiceCommandPreferences {
    public static let preferenceKey =
        "ZenVoice.localVoiceCommandsEnabled"

    public static func isEnabled(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        defaults.bool(forKey: preferenceKey)
    }

    public static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(enabled, forKey: preferenceKey)
    }
}

public enum NextDictationContext {
    public static let maximumCharacterCount = 500
    private static let maximumVocabularyCharacterCount = 240

    public static func sanitized(_ value: String) -> String {
        let withoutControlTokens = value
            .replacingOccurrences(of: "<|", with: " ")
            .replacingOccurrences(of: "|>", with: " ")
        let flattened = withoutControlTokens.unicodeScalars.map {
            scalar -> Character in
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return " "
            }
            return Character(String(scalar))
        }
        let normalized = String(flattened)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(normalized.prefix(Self.maximumCharacterCount))
    }

    public static func combined(
        context: String,
        preferredVocabulary: [String]
    ) -> String {
        var seen = Set<String>()
        let terms = preferredVocabulary.compactMap { value -> String? in
            let term = sanitized(value)
            guard !term.isEmpty,
                  seen.insert(term.lowercased()).inserted else {
                return nil
            }
            return term
        }
        var vocabulary = ""
        for term in terms {
            let candidate = vocabulary.isEmpty
                ? term
                : vocabulary + ", " + term
            guard candidate.count <= maximumVocabularyCharacterCount else {
                break
            }
            vocabulary = candidate
        }
        let cleanContext = sanitized(context)
        guard !vocabulary.isEmpty else {
            return cleanContext
        }
        let prefix = "Preferred vocabulary: \(vocabulary)."
        guard !cleanContext.isEmpty else {
            return prefix
        }
        return sanitized("\(prefix) Context: \(cleanContext)")
    }
}

public struct LocalVoiceCommandEngine: Sendable {
    private struct Command {
        let phrases: [String]
        let replacement: String
    }

    public init() {}

    public func apply(
        to transcript: String,
        languageCode: String,
        isEnabled: Bool
    ) -> InstantRefineResult {
        guard isEnabled, !transcript.isEmpty else {
            return InstantRefineResult(
                text: transcript,
                correctionCount: 0
            )
        }

        var candidate = transcript
        var correctionCount = 0
        for command in commands(languageCode: languageCode) {
            for phrase in command.phrases.sorted(by: {
                $0.count > $1.count
            }) {
                correctionCount += replace(
                    phrase: phrase,
                    with: command.replacement,
                    in: &candidate
                )
            }
        }

        candidate = candidate
            .replacingOccurrences(
                of: #"[ \t]+([,.!?。，？！،؟])"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[ \t]*\n[ \t]*"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return InstantRefineResult(
            text: candidate,
            correctionCount: correctionCount
        )
    }

    private func replace(
        phrase: String,
        with replacement: String,
        in text: inout String
    ) -> Int {
        let escaped = phrase.split(whereSeparator: \.isWhitespace)
            .map {
                NSRegularExpression.escapedPattern(for: String($0))
            }
            .joined(separator: #"\s+"#)
        let isCJK = phrase.unicodeScalars.contains {
            (0x3400...0x9FFF).contains($0.value)
        }
        let pattern = isCJK
            ? escaped
            : #"(?i)(?<![\p{L}\p{N}])"#
                + escaped
                + #"(?![\p{L}\p{N}])"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return 0
        }
        let range = NSRange(text.startIndex..., in: text)
        let count = expression.numberOfMatches(in: text, range: range)
        guard count > 0 else {
            return 0
        }
        text = expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: replacement
        )
        return count
    }

    private func commands(languageCode: String) -> [Command] {
        let localized = localizedPhrases[languageCode] ?? [:]
        let punctuation = punctuation(for: languageCode)
        return [
            Command(
                phrases: ["new paragraph"]
                    + (localized["newParagraph"] ?? []),
                replacement: "\n\n"
            ),
            Command(
                phrases: ["new line"] + (localized["newLine"] ?? []),
                replacement: "\n"
            ),
            Command(
                phrases: ["question mark"]
                    + (localized["questionMark"] ?? []),
                replacement: punctuation.questionMark
            ),
            Command(
                phrases: ["exclamation mark"]
                    + (localized["exclamationMark"] ?? []),
                replacement: punctuation.exclamationMark
            ),
            Command(
                phrases: ["full stop", "period"]
                    + (localized["period"] ?? []),
                replacement: punctuation.period
            ),
            Command(
                phrases: ["comma"] + (localized["comma"] ?? []),
                replacement: punctuation.comma
            )
        ]
    }

    private func punctuation(
        for languageCode: String
    ) -> (
        period: String,
        comma: String,
        questionMark: String,
        exclamationMark: String
    ) {
        switch languageCode {
        case "zh":
            return ("。", "，", "？", "！")
        case "ar":
            return (".", "،", "؟", "!")
        default:
            return (".", ",", "?", "!")
        }
    }

    private var localizedPhrases: [String: [String: [String]]] {
        [
            "hi": [
                "newParagraph": ["नया पैराग्राफ", "naya paragraph"],
                "newLine": ["नई पंक्ति", "nayi line"],
                "questionMark": ["प्रश्न चिन्ह", "prashn chinh"],
                "exclamationMark": ["विस्मयादिबोधक चिन्ह"],
                "period": ["पूर्ण विराम", "poorn viram"],
                "comma": ["अल्पविराम"]
            ],
            "es": [
                "newParagraph": ["nuevo párrafo"],
                "newLine": ["nueva línea"],
                "questionMark": ["signo de interrogación"],
                "exclamationMark": ["signo de exclamación"],
                "period": ["punto"],
                "comma": ["coma"]
            ],
            "fr": [
                "newParagraph": ["nouveau paragraphe"],
                "newLine": ["nouvelle ligne"],
                "questionMark": ["point d'interrogation"],
                "exclamationMark": ["point d'exclamation"],
                "period": ["point"],
                "comma": ["virgule"]
            ],
            "zh": [
                "newParagraph": ["新段落"],
                "newLine": ["换行", "新的一行"],
                "questionMark": ["问号"],
                "exclamationMark": ["感叹号"],
                "period": ["句号"],
                "comma": ["逗号"]
            ],
            "ar": [
                "newParagraph": ["فقرة جديدة"],
                "newLine": ["سطر جديد"],
                "questionMark": ["علامة استفهام"],
                "exclamationMark": ["علامة تعجب"],
                "period": ["نقطة"],
                "comma": ["فاصلة"]
            ]
        ]
    }
}
