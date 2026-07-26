import Foundation

public enum LanguageSupportLevel: String, Codable, Sendable {
    case recommended
    case preview

    public var displayName: String {
        switch self {
        case .recommended:
            return "Recommended"
        case .preview:
            return "Preview"
        }
    }
}

public struct SupportedLanguage:
    Codable, Equatable, Hashable, Identifiable, Sendable
{
    public let code: String
    public let displayName: String
    public let nativeName: String
    public let supportLevel: LanguageSupportLevel

    public var id: String { code }

    public init(
        code: String,
        displayName: String,
        nativeName: String,
        supportLevel: LanguageSupportLevel
    ) {
        self.code = code
        self.displayName = displayName
        self.nativeName = nativeName
        self.supportLevel = supportLevel
    }
}

public enum TranscriptionOutputMode:
    String, Codable, CaseIterable, Identifiable, Sendable
{
    case spokenLanguage
    case englishTranslation
    case latinScript

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .spokenLanguage:
            return "As spoken"
        case .englishTranslation:
            return "Translate to English"
        case .latinScript:
            return "Latin script"
        }
    }

    public var detail: String {
        switch self {
        case .spokenLanguage:
            return "Keep the language and native writing system."
        case .englishTranslation:
            return "Whisper translates speech to English on this Mac."
        case .latinScript:
            return "Keep the spoken language, written with Latin characters."
        }
    }
}

public struct LanguageProfile:
    Codable, Equatable, Hashable, Identifiable, Sendable
{
    public static let automaticCode = "auto"
    public static let english = LanguageProfile(
        inputLanguageCode: "en",
        outputMode: .spokenLanguage
    )
    public static let hinglish = LanguageProfile(
        inputLanguageCode: "hi",
        outputMode: .latinScript
    )

    public let inputLanguageCode: String
    public let outputMode: TranscriptionOutputMode

    public var id: String {
        "\(inputLanguageCode)-\(outputMode.rawValue)"
    }

    public var whisperLanguageArgument: String {
        inputLanguageCode
    }

    /// The language token to decode with, which depends on the model.
    ///
    /// A Hinglish-native model is trained to emit Latin script under the
    /// **English** token — that is how Oriserve run it, and it is what makes
    /// the output Hinglish rather than Devanagari. Handing it `hi` instead puts
    /// it straight back into the script the profile exists to avoid.
    public func whisperLanguageArgument(
        for capability: ModelLanguageCapability
    ) -> String {
        capability.emitsLatinScriptNatively ? "en" : inputLanguageCode
    }

    public var shouldTranslateToEnglish: Bool {
        outputMode == .englishTranslation
    }

    public var shouldTransliterateToLatin: Bool {
        outputMode == .latinScript
    }

    public var requiresMultilingualModel: Bool {
        inputLanguageCode != "en"
    }

    public var inputDisplayName: String {
        guard inputLanguageCode != Self.automaticCode else {
            return "Automatic detection"
        }
        return LanguageCatalog.language(code: inputLanguageCode)?.displayName
            ?? inputLanguageCode.uppercased()
    }

    public var displayName: String {
        if self == Self.hinglish {
            return "Hinglish"
        }
        switch outputMode {
        case .spokenLanguage:
            return inputDisplayName
        case .englishTranslation:
            return "\(inputDisplayName) → English"
        case .latinScript:
            return "\(inputDisplayName) in Latin script"
        }
    }

    public var shortLabel: String {
        if self == Self.hinglish {
            return "HINGLISH"
        }
        if inputLanguageCode == Self.automaticCode {
            return "AUTO"
        }
        return inputLanguageCode.uppercased()
    }

    public init(
        inputLanguageCode: String,
        outputMode: TranscriptionOutputMode
    ) {
        self.inputLanguageCode = inputLanguageCode
        self.outputMode = outputMode
    }

    /// Reconstructs the language behavior saved with a History record.
    ///
    /// Older records store the input language and model identifier, but not
    /// the output mode. The Hinglish specialist is the one unambiguous case:
    /// it emits Latin-script Hindi, so its records must retry as Hinglish.
    /// Every other record keeps the spoken language.
    public static func historyRetryProfile(
        languageCode: String,
        modelID: String
    ) -> LanguageProfile {
        let recordedCapability =
            VerifiedModelCatalog.model(id: modelID)?.languageCapability
        return LanguageProfile(
            inputLanguageCode: languageCode,
            outputMode:
                recordedCapability == .hinglish
                ? .latinScript
                : .spokenLanguage
        )
    }

    public func isCompatible(with capability: ModelLanguageCapability) -> Bool {
        switch capability {
        case .english:
            return !requiresMultilingualModel
        case .multilingual:
            // A general multilingual model is not an option for Hinglish. It
            // was allowed on the theory that it "still works, just badly";
            // measured against 30 real code-switched recordings it does not
            // work at all. It preserves **0 of 31** English words, respelling
            // `document` as डोक्यूमेंट and `tutorial` as टिटूटूरल — every
            // English word phonetically rewritten in a script the reader did
            // not ask for. The specialist preserves 82 of 96.
            //
            // Some of them are also far slower, because general models can
            // fail to *terminate* on code-switched speech: one clip made
            // Whisper Tiny emit "We are in India" about a hundred times, and
            // Medium ran past fifteen minutes on thirty clips the specialist
            // finished in twenty-nine seconds. Turbo does terminate normally
            // on the same audio — it simply produces unusable output — so the
            // block rests on the loanwords, not on the speed.
            //
            // See docs/TRANSCRIPTION_ACCURACY.md.
            return self != .hinglish
        case .hinglish:
            // The reverse still holds: a Hinglish specialist is not a better
            // multilingual model. It scores 16.8% word error rate on English
            // against Medium's 2.0%.
            return self == .hinglish
        }
    }
}

public enum LanguageCatalog {
    public static let languages: [SupportedLanguage] = [
        language("en", "English", "English", .recommended),
        language("hi", "Hindi", "हिन्दी", .recommended),
        language("es", "Spanish", "Español", .recommended),
        language("fr", "French", "Français", .recommended),
        language("de", "German", "Deutsch", .recommended),
        language("zh", "Mandarin Chinese", "中文", .recommended),
        language("ja", "Japanese", "日本語", .recommended),
        language("ko", "Korean", "한국어", .recommended),
        language("pt", "Portuguese", "Português", .recommended),
        language("it", "Italian", "Italiano", .recommended),
        language("ar", "Arabic", "العربية", .recommended),
        language("ru", "Russian", "Русский", .recommended),
        language("tr", "Turkish", "Türkçe", .recommended),
        language("nl", "Dutch", "Nederlands", .recommended),
        language("pl", "Polish", "Polski", .recommended),
        language("uk", "Ukrainian", "Українська", .recommended),
        language("id", "Indonesian", "Bahasa Indonesia", .recommended),
        language("vi", "Vietnamese", "Tiếng Việt", .recommended),
        language("th", "Thai", "ไทย", .recommended),
        language("he", "Hebrew", "עברית", .recommended),
        language("sv", "Swedish", "Svenska", .recommended),
        language("da", "Danish", "Dansk", .recommended),
        language("no", "Norwegian", "Norsk", .recommended),
        language("fi", "Finnish", "Suomi", .recommended),
        language("cs", "Czech", "Čeština", .recommended),
        language("ro", "Romanian", "Română", .recommended),
        language("el", "Greek", "Ελληνικά", .recommended),
        language("hu", "Hungarian", "Magyar", .recommended),
        language("bn", "Bengali", "বাংলা", .preview),
        language("ta", "Tamil", "தமிழ்", .preview),
        language("te", "Telugu", "తెలుగు", .preview),
        language("ur", "Urdu", "اردو", .preview),
        language("mr", "Marathi", "मराठी", .preview),
        language("gu", "Gujarati", "ગુજરાતી", .preview),
        language("pa", "Punjabi", "ਪੰਜਾਬੀ", .preview),
        language("kn", "Kannada", "ಕನ್ನಡ", .preview),
        language("ml", "Malayalam", "മലയാളം", .preview),
        language("ne", "Nepali", "नेपाली", .preview),
        language("si", "Sinhala", "සිංහල", .preview),
        language("fa", "Persian", "فارسی", .preview),
        language("ms", "Malay", "Bahasa Melayu", .preview),
        language("ca", "Catalan", "Català", .preview),
        language("hr", "Croatian", "Hrvatski", .preview),
        language("bg", "Bulgarian", "Български", .preview),
        language("sr", "Serbian", "Српски", .preview),
        language("sk", "Slovak", "Slovenčina", .preview),
        language("sl", "Slovenian", "Slovenščina", .preview),
        language("lt", "Lithuanian", "Lietuvių", .preview),
        language("lv", "Latvian", "Latviešu", .preview),
        language("et", "Estonian", "Eesti", .preview),
        language("is", "Icelandic", "Íslenska", .preview),
        language("sw", "Swahili", "Kiswahili", .preview),
        language("af", "Afrikaans", "Afrikaans", .preview),
        language("cy", "Welsh", "Cymraeg", .preview),
        language("eu", "Basque", "Euskara", .preview),
        language("gl", "Galician", "Galego", .preview),
        language("sq", "Albanian", "Shqip", .preview),
        language("mk", "Macedonian", "Македонски", .preview),
        language("hy", "Armenian", "Հայերեն", .preview),
        language("ka", "Georgian", "ქართული", .preview),
        language("az", "Azerbaijani", "Azərbaycanca", .preview),
        language("kk", "Kazakh", "Қазақша", .preview),
        language("mn", "Mongolian", "Монгол", .preview),
        language("km", "Khmer", "ខ្មែរ", .preview)
    ]

    public static func language(code: String) -> SupportedLanguage? {
        languages.first { $0.code == code }
    }

    public static func isSupported(code: String) -> Bool {
        code == LanguageProfile.automaticCode || language(code: code) != nil
    }

    private static func language(
        _ code: String,
        _ displayName: String,
        _ nativeName: String,
        _ supportLevel: LanguageSupportLevel
    ) -> SupportedLanguage {
        SupportedLanguage(
            code: code,
            displayName: displayName,
            nativeName: nativeName,
            supportLevel: supportLevel
        )
    }
}

public enum LanguagePreferences {
    public static let preferenceKey = "ZenVoice.languageProfile"

    public static func load(
        defaults: UserDefaults = .standard
    ) -> LanguageProfile {
        guard let data = defaults.data(forKey: preferenceKey),
              let profile = try? JSONDecoder().decode(
                LanguageProfile.self,
                from: data
              ),
              LanguageCatalog.isSupported(code: profile.inputLanguageCode)
        else {
            return .english
        }
        return profile
    }

    public static func save(
        _ profile: LanguageProfile,
        defaults: UserDefaults = .standard
    ) {
        guard LanguageCatalog.isSupported(code: profile.inputLanguageCode),
              let data = try? JSONEncoder().encode(profile) else {
            return
        }
        defaults.set(data, forKey: preferenceKey)
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: preferenceKey)
    }
}

public enum LocalTransliterator {
    public static func latinScript(_ text: String) -> String {
        var result = ""
        var nativeScriptRun = ""

        func appendTransliteratedRun() {
            guard !nativeScriptRun.isEmpty else {
                return
            }
            let latin = nativeScriptRun.applyingTransform(
                .toLatin,
                reverse: false
            ) ?? nativeScriptRun
            result += latin.applyingTransform(
                .stripDiacritics,
                reverse: false
            ) ?? latin
            nativeScriptRun = ""
        }

        for character in text {
            let containsNonLatinLetter = character.unicodeScalars.contains {
                $0.properties.isAlphabetic
                    && !$0.isASCII
                    && !($0.properties.name ?? "").contains("LATIN")
            }
            if containsNonLatinLetter {
                nativeScriptRun.append(character)
            } else {
                appendTransliteratedRun()
                result.append(character)
            }
        }
        appendTransliteratedRun()
        return result
    }
}
