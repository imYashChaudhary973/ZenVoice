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
        var termsToProcess = terms
        if termsToProcess.isEmpty {
            termsToProcess = ["PR", "repo", "deploy", "k8s", "LLM", "API", "theek", "matlab", "acha", "bhai", "jugaad", "pakka"]
        }
        var vocabulary = ""
        for term in termsToProcess {
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

public enum LocalVoiceCommandCategory: String, CaseIterable, Sendable, Identifiable {
    case punctuation
    case symbols
    case pairs
    case structure
    case emoji
    case escape

    public var id: String { rawValue }

    /// Small-caps style header shown above the category's rows.
    public var displayName: String {
        switch self {
        case .punctuation: return "PUNCTUATION"
        case .symbols: return "SYMBOLS"
        case .pairs: return "PAIRS"
        case .structure: return "STRUCTURE"
        case .emoji: return "EMOJI"
        case .escape: return "ESCAPE"
        }
    }
}

/// One curated documentation row of the Spoken Commands reference sheet.
/// The right-hand `output` is what dictation produces; `note` carries the
/// small secondary explanation some rows show.
public struct LocalVoiceCommandReferenceRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let phrases: [String]
    public let output: String
    public let note: String?
    public let category: LocalVoiceCommandCategory

    public init(
        phrases: [String],
        output: String,
        note: String? = nil,
        category: LocalVoiceCommandCategory
    ) {
        self.phrases = phrases
        self.output = output
        self.note = note
        self.category = category
        self.id = category.rawValue + phrases.joined(separator: "|")
    }
}

public struct LocalVoiceCommandReferenceGroup: Identifiable, Hashable, Sendable {
    public let category: LocalVoiceCommandCategory
    public let rows: [LocalVoiceCommandReferenceRow]
    public var id: String { category.rawValue }

    public init(
        category: LocalVoiceCommandCategory,
        rows: [LocalVoiceCommandReferenceRow]
    ) {
        self.category = category
        self.rows = rows
    }
}

public struct LocalVoiceCommandEngine: Sendable {
    fileprivate struct Command {
        let phrases: [String]
        let replacement: String
        let category: LocalVoiceCommandCategory
        /// Consumes the space that follows the phrase — "gmail dot com"
        /// becomes "gmail.com" instead of "gmail. com".
        var joinsRight = false
        /// Consumes the spaces that precede the phrase — "quote hello
        /// unquote" becomes "\u201Chello\u201D" with the quote hugging the word.
        var joinsLeft = false
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

        var candidate = Self.protectEscapedPhrases(transcript)
        var correctionCount = 0
        // Join markers: a command may declare that its output hugs the word
        // on its left (quote → “hello”) or right (dot → gmail.com). The
        // markers are unambiguous sentinels the join pass below collapses;
        // they are stripped once joins are done.
        let leftMarker = "\u{E000}"
        let rightMarker = "\u{E001}"
        for command in commands(languageCode: languageCode) {
            var replacement = command.replacement
            if command.joinsLeft {
                replacement = leftMarker + replacement
            }
            if command.joinsRight {
                replacement += rightMarker
            }
            for phrase in command.phrases.sorted(by: {
                $0.count > $1.count
            }) {
                correctionCount += replace(
                    phrase: phrase,
                    with: replacement,
                    in: &candidate
                )
            }
        }

        // The join pass: a space on the hugging side of a marker collapses.
        candidate = candidate.replacingOccurrences(
            of: "[ \\t]+\u{E000}",
            with: "\u{E000}",
            options: .regularExpression
        )
        candidate = candidate.replacingOccurrences(
            of: "\u{E001}[ \\t]+",
            with: "\u{E001}",
            options: .regularExpression
        )
        candidate = candidate
            .replacingOccurrences(of: leftMarker, with: "")
            .replacingOccurrences(of: rightMarker, with: "")

        let spanCorrections = Self.applySpans(&candidate)
        correctionCount += spanCorrections
        candidate = Self.unprotect(candidate)

        candidate = candidate
            .replacingOccurrences(
                of: #"[ \t]+([,.!?@/\\$€£%&*#+=|<>^~。，？！،؟])"#,
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

    /// Zero-width-space protector: "literally comma" becomes a form of the
    /// word that no command phrase can match, then the spacer is stripped
    /// after all commands have run.
    static let escapeSpacer = "\u{200B}"

    static func protectEscapedPhrases(_ text: String) -> String {
        var result = text
        let phrases = LocalVoiceCommandEngine()
            .commands(languageCode: "en")
            .flatMap { $0.phrases }
            .sorted { $0.count > $1.count }
        for phrase in phrases {
            let pattern =
                "(?i)(?<![\\p{L}\\p{N}])literally[ \\t]+("
                + NSRegularExpression.escapedPattern(for: phrase)
                + ")"
            guard let expression = try? NSRegularExpression(
                pattern: pattern
            ) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            guard expression.numberOfMatches(in: result, range: range) > 0
            else { continue }
            var rebuilt = ""
            var cursor = result.startIndex
            for match in expression.matches(
                in: result,
                range: range
            ) {
                guard let matchRange = Range(match.range, in: result),
                      let phraseRange = Range(match.range(at: 1), in: result)
                else { continue }
                rebuilt += result[cursor..<matchRange.lowerBound]
                rebuilt += Self.protect(String(result[phraseRange]))
                cursor = matchRange.upperBound
            }
            rebuilt += result[cursor...]
            result = rebuilt
        }
        return result
    }

    static func protect(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first) + escapeSpacer + word.dropFirst()
    }

    static func unprotect(_ text: String) -> String {
        text.replacingOccurrences(of: escapeSpacer, with: "")
    }

    /// Span commands that pair with surrounding words rather than replacing a
    /// single phrase: no space, ALL CAPS spans, camel and snake case.
    static func applySpans(_ text: inout String) -> Int {
        var corrections = 0

        // "no space" joins the words on either side of it.
        if let join = try? NSRegularExpression(
            pattern: "(?i)(?<=\\S)[ \\t]+no space[ \\t]+(?=\\S)"
        ) {
            let before = text
            text = join.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
            if text != before { corrections += 1 }
        }

        // "all caps on … all caps off" uppercases the span.
        if let caps = try? NSRegularExpression(
            pattern: "(?is)\\ball caps on\\b\\s*(.*?)\\s*\\ball caps off\\b"
        ) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = caps.matches(in: text, range: range)
            if !matches.isEmpty {
                var rebuilt = ""
                var cursor = text.startIndex
                for match in matches {
                    guard let full = Range(match.range, in: text),
                          let inner = Range(match.range(at: 1), in: text)
                    else { continue }
                    rebuilt += text[cursor..<full.lowerBound]
                    rebuilt += text[inner].uppercased()
                    cursor = full.upperBound
                }
                rebuilt += text[cursor...]
                text = rebuilt
                corrections += matches.count
            }
        }

        // "camel case …" / "snake case …" reshape the rest of their line.
        if let reshape = try? NSRegularExpression(
            pattern: "(?i)\\b(camel case|snake case)\\b[ \\t]+([^\\n]+)"
        ) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = reshape.matches(in: text, range: range)
            if !matches.isEmpty {
                var rebuilt = ""
                var cursor = text.startIndex
                for match in matches {
                    guard let full = Range(match.range, in: text),
                          let kind = Range(match.range(at: 1), in: text),
                          let words = Range(match.range(at: 2), in: text)
                    else { continue }
                    let wordsList = text[words]
                        .split(whereSeparator: \.isWhitespace)
                        .map(String.init)
                    guard !wordsList.isEmpty else { continue }
                    let reshaped: String
                    if text[kind].lowercased().hasPrefix("camel") {
                        guard let head = wordsList.first else { continue }
                        reshaped = head.lowercased()
                            + wordsList.dropFirst()
                                .map { $0.capitalized }
                                .joined()
                    } else {
                        reshaped = wordsList
                            .map { $0.lowercased() }
                            .joined(separator: "_")
                    }
                    rebuilt += text[cursor..<full.lowerBound]
                    rebuilt += reshaped
                    cursor = full.upperBound
                    corrections += 1
                }
                rebuilt += text[cursor...]
                text = rebuilt
            }
        }

        return corrections
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
        var commands: [Command] = []

        // STRUCTURE — line, paragraph, and span commands.
        commands += [
            Command(
                phrases: ["new paragraph"] + (localized["newParagraph"] ?? []),
                replacement: "\n\n",
                category: .structure
            ),
            Command(
                phrases: ["new line"] + (localized["newLine"] ?? []),
                replacement: "\n",
                category: .structure
            ),
            Command(
                phrases: ["tab key"],
                replacement: "\t",
                category: .structure,
                joinsRight: true,
                joinsLeft: true
            )
        ]

        // PUNCTUATION
        commands += [
            Command(
                phrases: ["full stop", "period"] + (localized["period"] ?? []),
                replacement: punctuation.period,
                category: .punctuation
            ),
            Command(
                phrases: ["comma"] + (localized["comma"] ?? []),
                replacement: punctuation.comma,
                category: .punctuation
            ),
            Command(
                phrases: ["question mark"] + (localized["questionMark"] ?? []),
                replacement: punctuation.questionMark,
                category: .punctuation
            ),
            Command(
                phrases: ["exclamation mark"] + (localized["exclamationMark"] ?? []),
                replacement: punctuation.exclamationMark,
                category: .punctuation
            ),
            Command(
                phrases: ["colon"],
                replacement: ":",
                category: .punctuation
            ),
            Command(
                phrases: ["semicolon"],
                replacement: ";",
                category: .punctuation
            ),
            Command(
                phrases: ["ellipsis"],
                replacement: "…",
                category: .punctuation
            ),
            Command(
                phrases: ["dash"],
                replacement: "-",
                category: .punctuation,
                joinsRight: true
            ),
            Command(
                phrases: ["dash dash force"],
                replacement: "---",
                category: .punctuation,
                joinsRight: true
            ),
            Command(
                phrases: ["em dash"],
                replacement: "—",
                category: .punctuation
            ),
            Command(
                phrases: ["hyphen"],
                replacement: "-",
                category: .punctuation,
                joinsRight: true
            ),
            Command(
                phrases: ["underscore"],
                replacement: "_",
                category: .punctuation,
                joinsRight: true
            )
        ]

        // SYMBOLS
        commands += [
            Command(
                phrases: ["dot"],
                replacement: ".",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["at sign"],
                replacement: "@",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["slash"],
                replacement: "/",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["backslash"],
                replacement: "\\",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["dollar sign"],
                replacement: "$",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["euro sign"],
                replacement: "€",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["pound sign"],
                replacement: "£",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["percent"],
                replacement: "%",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["ampersand"],
                replacement: "&",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["asterisk"],
                replacement: "*",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["hash"],
                replacement: "#",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["plus sign"],
                replacement: "+",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["equals sign"],
                replacement: "=",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["pipe"],
                replacement: "|",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["greater than"],
                replacement: ">",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["less than"],
                replacement: "<",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["caret"],
                replacement: "^",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            ),
            Command(
                phrases: ["tilde"],
                replacement: "~",
                category: .symbols,
                joinsRight: true,
                joinsLeft: true
            )
        ]

        // PAIRS — open and close are separate spoken commands.
        commands += [
            Command(
                phrases: ["open parenthesis", "open paren", "left parenthesis"],
                replacement: "(",
                category: .pairs
            ),
            Command(
                phrases: ["close parenthesis", "close paren", "right parenthesis"],
                replacement: ")",
                category: .pairs
            ),
            Command(
                phrases: ["open bracket", "left bracket"],
                replacement: "[",
                category: .pairs
            ),
            Command(
                phrases: ["close bracket", "right bracket"],
                replacement: "]",
                category: .pairs
            ),
            Command(
                phrases: ["open brace", "left brace"],
                replacement: "{",
                category: .pairs
            ),
            Command(
                phrases: ["close brace", "right brace"],
                replacement: "}",
                category: .pairs
            ),
            Command(
                phrases: ["quote"],
                replacement: "\u{201C}",
                category: .pairs,
                joinsRight: true
            ),
            Command(
                phrases: ["unquote"],
                replacement: "\u{201D}",
                category: .pairs,
                joinsLeft: true
            ),
            Command(
                phrases: ["open single quote"],
                replacement: "\u{2018}",
                category: .pairs,
                joinsRight: true
            ),
            Command(
                phrases: ["close single quote"],
                replacement: "\u{2019}",
                category: .pairs,
                joinsLeft: true
            )
        ]

        // EMOJI
        commands += [
            Command(
                phrases: ["thinking emoji"],
                replacement: "🤔",
                category: .emoji
            ),
            Command(
                phrases: ["raised hands emoji"],
                replacement: "🙌",
                category: .emoji
            ),
            Command(
                phrases: ["flex emoji", "muscle emoji"],
                replacement: "💪",
                category: .emoji
            ),
            Command(
                phrases: ["thumbs up", "thumbs up emoji"],
                replacement: "👍",
                category: .emoji
            ),
            Command(
                phrases: ["heart emoji"],
                replacement: "❤️",
                category: .emoji
            ),
            Command(
                phrases: ["fire emoji"],
                replacement: "🔥",
                category: .emoji
            ),
            Command(
                phrases: ["rocket emoji"],
                replacement: "🚀",
                category: .emoji
            ),
            Command(
                phrases: ["party emoji"],
                replacement: "🎉",
                category: .emoji
            ),
            Command(
                phrases: ["check emoji", "checkmark emoji"],
                replacement: "✅",
                category: .emoji
            ),
            Command(
                phrases: ["eyes emoji"],
                replacement: "👀",
                category: .emoji
            ),
            Command(
                phrases: ["laughing emoji", "cry laughing emoji"],
                replacement: "😂",
                category: .emoji
            ),
            Command(
                phrases: ["smile emoji"],
                replacement: "😊",
                category: .emoji
            ),
            Command(
                phrases: ["wink emoji"],
                replacement: "😉",
                category: .emoji
            ),
            Command(
                phrases: ["crying emoji"],
                replacement: "😢",
                category: .emoji
            ),
            Command(
                phrases: ["wave emoji"],
                replacement: "👋",
                category: .emoji
            ),
            Command(
                phrases: ["ok emoji", "okay emoji"],
                replacement: "👌",
                category: .emoji
            ),
            Command(
                phrases: ["pray emoji", "hands together emoji"],
                replacement: "🙏",
                category: .emoji
            ),
            Command(
                phrases: ["clap emoji"],
                replacement: "👏",
                category: .emoji
            ),
            Command(
                phrases: ["star emoji"],
                replacement: "⭐",
                category: .emoji
            ),
            Command(
                phrases: ["zap emoji", "lightning emoji"],
                replacement: "⚡",
                category: .emoji
            ),
            Command(
                phrases: ["sun emoji"],
                replacement: "☀️",
                category: .emoji
            ),
            Command(
                phrases: ["moon emoji"],
                replacement: "🌙",
                category: .emoji
            ),
            Command(
                phrases: ["coffee emoji"],
                replacement: "☕",
                category: .emoji
            ),
            Command(
                phrases: ["pizza emoji"],
                replacement: "🍕",
                category: .emoji
            ),
            Command(
                phrases: ["burger emoji"],
                replacement: "🍔",
                category: .emoji
            ),
            Command(
                phrases: ["cake emoji"],
                replacement: "🎂",
                category: .emoji
            ),
            Command(
                phrases: ["beer emoji"],
                replacement: "🍺",
                category: .emoji
            ),
            Command(
                phrases: ["dog emoji"],
                replacement: "🐶",
                category: .emoji
            ),
            Command(
                phrases: ["cat emoji"],
                replacement: "🐱",
                category: .emoji
            ),
            Command(
                phrases: ["bulb emoji", "light bulb emoji"],
                replacement: "💡",
                category: .emoji
            ),
            Command(
                phrases: ["money emoji", "money bag emoji"],
                replacement: "💰",
                category: .emoji
            ),
            Command(
                phrases: ["warning emoji"],
                replacement: "⚠️",
                category: .emoji
            ),
            Command(
                phrases: ["hundred emoji"],
                replacement: "💯",
                category: .emoji
            ),
            Command(
                phrases: ["ghost emoji"],
                replacement: "👻",
                category: .emoji
            ),
            Command(
                phrases: ["crown emoji"],
                replacement: "👑",
                category: .emoji
            ),
            Command(
                phrases: ["gift emoji"],
                replacement: "🎁",
                category: .emoji
            ),
            Command(
                phrases: ["flower emoji"],
                replacement: "🌸",
                category: .emoji
            ),
            Command(
                phrases: ["rainbow emoji"],
                replacement: "🌈",
                category: .emoji
            ),
            Command(
                phrases: ["computer emoji", "laptop emoji"],
                replacement: "💻",
                category: .emoji
            ),
            Command(
                phrases: ["phone emoji"],
                replacement: "📱",
                category: .emoji
            ),
            Command(
                phrases: ["poop emoji"],
                replacement: "💩",
                category: .emoji
            )
        ]

        return commands
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

public extension LocalVoiceCommandEngine {
    /// Curated rows for the Spoken Commands reference sheet. Mirrors the live
    /// vocabulary in `commands(languageCode:)` — both evolve together, and the
    /// emoji aggregate row derives its count from the live table.
    func referenceGroups() -> [LocalVoiceCommandReferenceGroup] {
        let emojiCount = commands(languageCode: "en")
            .filter { $0.category == .emoji }
            .count

        func group(
            _ category: LocalVoiceCommandCategory,
            _ rows: [LocalVoiceCommandReferenceRow]
        ) -> LocalVoiceCommandReferenceGroup {
            LocalVoiceCommandReferenceGroup(category: category, rows: rows)
        }

        func row(
            _ phrases: [String],
            _ output: String,
            note: String? = nil,
            _ category: LocalVoiceCommandCategory
        ) -> LocalVoiceCommandReferenceRow {
            LocalVoiceCommandReferenceRow(
                phrases: phrases,
                output: output,
                note: note,
                category: category
            )
        }

        return [
            group(.punctuation, [
                row(["period / full stop"], ".", .punctuation),
                row(["comma"], ",", .punctuation),
                row(["question mark"], "?", .punctuation),
                row(["exclamation mark"], "!", .punctuation),
                row(["colon / semicolon"], ": ;", .punctuation),
                row(["ellipsis"], "…", .punctuation),
                row(
                    ["dash"],
                    "-",
                    note: "joins right: \u{201C}dash dash force\u{201D} → ---",
                    .punctuation
                ),
                row(["em dash / hyphen / underscore"], "— – _", .punctuation)
            ]),
            group(.symbols, [
                row(
                    ["dot"],
                    ".",
                    note: "joins: gmail dot com → gmail.com",
                    .symbols
                ),
                row(["at sign"], "@", .symbols),
                row(["slash / backslash"], "/ \\", .symbols),
                row(
                    ["dollar sign / euro sign / pound sign"],
                    "$ € £",
                    .symbols
                ),
                row(["percent"], "%", .symbols),
                row(["ampersand / asterisk / hash"], "& * #", .symbols),
                row(["plus sign / equals sign / pipe"], "+ = |", .symbols),
                row(
                    ["greater than / less than / caret / tilde"],
                    "> < ^ ~",
                    .symbols
                )
            ]),
            group(.pairs, [
                row(["open / close paren"], "( )", .pairs),
                row(["open / close bracket"], "[ ]", .pairs),
                row(["open / close brace"], "{ }", .pairs),
                row(["quote … unquote"], "\u{201C} … \u{201D}", .pairs),
                row(["open / close single quote"], "\u{2018} … \u{2019}", .pairs)
            ]),
            group(.structure, [
                row(
                    ["new line / new paragraph"],
                    "line · paragraph break",
                    .structure
                ),
                row(["tab key"], "tab character", .structure),
                row(["no space"], "joins the surrounding words", .structure),
                row(["all caps on … all caps off"], "UPPERCASE SPAN", .structure),
                row(["camel case …"], "joinsTheRestLikeThis", .structure),
                row(["snake case …"], "joins_the_rest_like_this", .structure)
            ]),
            group(.emoji, [
                row(["thinking emoji"], "🤔", .emoji),
                row(["raised hands emoji"], "🙌", .emoji),
                row(["flex emoji"], "💪", .emoji),
                row(["thumbs up emoji"], "👍", .emoji),
                row(["fire emoji"], "🔥", .emoji),
                row(
                    ["heart · party · check · eyes … emoji"],
                    "❤️ 🎉 ✅ 👀 + \(max(emojiCount - 4, 0)) names",
                    .emoji
                )
            ]),
            group(.escape, [
                row(
                    ["literally comma"],
                    "the word instead of the symbol",
                    .escape
                ),
                row(
                    ["literally fire emoji"],
                    "the words, not 🔥",
                    .escape
                )
            ])
        ]
    }
}
