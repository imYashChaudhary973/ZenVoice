import Foundation

// Reproduces ZenVoice's LocalTransliterator.latinScript exactly, to see what
// the Hinglish profile actually produces from Whisper's Devanagari output.

func latinScript(_ text: String) -> String {
    var result = ""
    var nativeScriptRun = ""

    func appendTransliteratedRun() {
        guard !nativeScriptRun.isEmpty else { return }
        let latin = nativeScriptRun.applyingTransform(.toLatin, reverse: false)
            ?? nativeScriptRun
        result += latin.applyingTransform(.stripDiacritics, reverse: false)
            ?? latin
        nativeScriptRun = ""
    }

    for character in text {
        let containsNonLatinLetter = character.unicodeScalars.contains {
            $0.properties.isAlphabetic && !$0.isASCII
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

// Left: what Whisper (language=hi) emits. Right: what a person actually writes.
let cases: [(devanagari: String, naturalHinglish: String)] = [
    ("क्या हाल है", "kya haal hai"),
    ("मैं कंप्यूटर पर काम कर रहा हूँ", "main computer par kaam kar raha hoon"),
    ("मुझे मीटिंग में जाना है", "mujhe meeting mein jaana hai"),
    ("यह फ़ाइल डाउनलोड कर दो", "yeh file download kar do"),
    ("प्रोजेक्ट का स्टेटस क्या है", "project ka status kya hai"),
    ("थोड़ा सा वेट करो", "thoda sa wait karo"),
    ("मैंने ईमेल भेज दिया", "maine email bhej diya"),
    ("सर्वर डाउन है", "server down hai")
]

print("ICU .toLatin + .stripDiacritics — what ZenVoice produces today\n")
print(String(repeating: "─", count: 92))
print("Whisper output (hi)".padding(toLength: 30, withPad: " ", startingAt: 0)
    + "| ZenVoice produces".padding(toLength: 32, withPad: " ", startingAt: 0)
    + "| natural Hinglish")
print(String(repeating: "─", count: 92))

var mismatches = 0
for testCase in cases {
    let produced = latinScript(testCase.devanagari)
    if produced.lowercased() != testCase.naturalHinglish.lowercased() {
        mismatches += 1
    }
    print(testCase.devanagari.padding(toLength: 30, withPad: " ", startingAt: 0)
        + "| \(produced)".padding(toLength: 32, withPad: " ", startingAt: 0)
        + "| \(testCase.naturalHinglish)")
}
print(String(repeating: "─", count: 92))
print("\n\(mismatches)/\(cases.count) differ from what a person would write.")

// The mixed-script case: Whisper with language=hi writes English words in
// Devanagari, so the loanword is destroyed before romanization even runs.
print("\nRound-trip of English loanwords through Devanagari:")
for (devanagari, english) in [
    ("कंप्यूटर", "computer"), ("मीटिंग", "meeting"), ("डाउनलोड", "download"),
    ("स्टेटस", "status"), ("सर्वर", "server"), ("ईमेल", "email")
] {
    print("  \(english) → \(devanagari) → \(latinScript(devanagari))")
}
