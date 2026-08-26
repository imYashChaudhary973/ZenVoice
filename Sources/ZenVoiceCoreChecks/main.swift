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

import ApplicationServices
import CryptoKit
import Foundation
import ZenVoiceCore

let cleaner = TranscriptCleaner()

let checks: [(name: String, actual: String, expected: String)] = [
    (
        "trims and collapses whitespace",
        cleaner.clean("   hello    from\nZenVoice   "),
        "Hello from ZenVoice"
    ),
    (
        "removes Whisper metadata",
        cleaner.clean("[BLANK_AUDIO]"),
        ""
    ),
    (
        "removes only a leading filler",
        cleaner.clean("um, this is, um, still meaningful."),
        "This is, um, still meaningful."
    ),
    (
        "drops a parenthesised non-speech annotation",
        cleaner.clean("(static)"),
        ""
    ),
    (
        "drops multiple non-speech annotations",
        cleaner.clean("(wind blowing) (computer speaking)"),
        ""
    ),
    (
        "keeps dictated asides in parentheses",
        cleaner.clean("the total (before tax) is fifty"),
        "The total (before tax) is fifty"
    ),
    (
        "drops a bare filler token",
        cleaner.clean("you"),
        ""
    ),
    (
        "drops a bare filler token with punctuation",
        cleaner.clean("You."),
        ""
    ),
    (
        "keeps you inside real speech",
        cleaner.clean("can you review this"),
        "Can you review this"
    ),
    (
        "keeps a standalone thank you",
        cleaner.clean("Thank you."),
        "Thank you."
    )
]

for check in checks {
    guard check.actual == check.expected else {
        FileHandle.standardError.write(
            Data(
                "FAIL: \(check.name)\nExpected: \(check.expected)\nActual: \(check.actual)\n"
                    .utf8
            )
        )
        exit(1)
    }
}

print("ZenVoiceCoreChecks: \(checks.count) checks passed")

let instantRefiner = InstantRefineEngine()
let cleanRefinement = instantRefiner.refine(
    "Um, create the the login page.",
    mode: .clean
)
guard cleanRefinement.text == "Create the login page.",
      cleanRefinement.correctionCount == 2,
      !cleanRefinement.wasRejected else {
    FileHandle.standardError.write(
        Data("FAIL: clean Instant Refine result is incorrect\n".utf8)
    )
    exit(1)
}

let restartRefinement = instantRefiner.refine(
    "Create a login page, no wait, a sign-up page using Swift.",
    mode: .clean
)
guard restartRefinement.text
        == "Create a sign-up page using Swift.",
      restartRefinement.correctionCount == 1 else {
    FileHandle.standardError.write(
        Data(
            (
                "FAIL: spoken restart was not refined safely: "
                    + "\(restartRefinement)\n"
            ).utf8
        )
    )
    exit(1)
}

let promptRefinement = instantRefiner.refine(
    "Create the API new paragraph Add tests",
    mode: .agentPrompt
)
guard promptRefinement.text == "Create the API\n\nAdd tests",
      promptRefinement.correctionCount == 1 else {
    FileHandle.standardError.write(
        Data("FAIL: agent prompt layout command was not applied\n".utf8)
    )
    exit(1)
}

let rejectedRefinement = instantRefiner.refine(
    "Um um um um um keep",
    mode: .clean
)
guard rejectedRefinement.text == "Um um um um um keep",
      rejectedRefinement.correctionCount == 0,
      rejectedRefinement.wasRejected else {
    FileHandle.standardError.write(
        Data("FAIL: destructive refinement was not rejected\n".utf8)
    )
    exit(1)
}

let semanticNoWait = instantRefiner.refine(
    "There is no wait time.",
    mode: .clean
)
guard semanticNoWait.text == "There is no wait time.",
      semanticNoWait.correctionCount == 0 else {
    FileHandle.standardError.write(
        Data("FAIL: semantic “no wait” phrase was changed\n".utf8)
    )
    exit(1)
}

let quantityRepeat =
    "Do you know what I mean one one way to improve it is to choose one option."
let rejectedQuantityRepeat = instantRefiner.refine(
    quantityRepeat,
    mode: .clean
)
guard rejectedQuantityRepeat.text == quantityRepeat,
      rejectedQuantityRepeat.correctionCount == 0,
      rejectedQuantityRepeat.wasRejected else {
    FileHandle.standardError.write(
        Data("FAIL: quantity-changing refinement was not rejected\n".utf8)
    )
    exit(1)
}

let negationRepeat = "No no no, do not deploy this build."
let rejectedNegationRepeat = instantRefiner.refine(
    negationRepeat,
    mode: .clean
)
guard rejectedNegationRepeat.text == negationRepeat,
      rejectedNegationRepeat.correctionCount == 0,
      rejectedNegationRepeat.wasRejected else {
    FileHandle.standardError.write(
        Data("FAIL: negation-changing refinement was not rejected\n".utf8)
    )
    exit(1)
}

let semanticGuardChecks: [(
    name: String,
    original: String,
    candidate: String,
    expected: Bool
)] = [
    (
        "allows protected terms to move without changing their counts",
        "Do not deploy version 2.",
        "Version 2 must not be deployed.",
        true
    ),
    (
        "rejects a deleted negation",
        "Do not deploy version 2.",
        "Deploy version 2.",
        false
    ),
    (
        "rejects an invented negation",
        "Deploy version 2.",
        "Do not deploy version 2.",
        false
    ),
    (
        "rejects a substituted numeric value",
        "Deploy version 2.",
        "Deploy version 3.",
        false
    ),
    (
        "normalizes apostrophes while comparing contractions",
        "Don't deploy this build.",
        "Dont deploy this build.",
        true
    ),
    (
        "allows a punctuation-delimited correction cue",
        "Use staging — no, wait — use production.",
        "Use production.",
        true
    ),
    (
        "protects semantic no-wait wording",
        "There is no wait time.",
        "There is wait time.",
        false
    )
]

for check in semanticGuardChecks {
    let actual = TranscriptSemanticGuard.preservesProtectedTerms(
        original: check.original,
        candidate: check.candidate
    )
    guard actual == check.expected else {
        FileHandle.standardError.write(
            Data(
                (
                    "FAIL: semantic guard \(check.name); expected "
                        + "\(check.expected), got \(actual)\n"
                ).utf8
            )
        )
        exit(1)
    }
}

let slangNormalizationChecks: [(
    name: String,
    input: String,
    expected: String
)] = [
    (
        "normalizes Hinglish acoustic variants",
        "Please confirm theek hey and pata nahee.",
        "Please confirm theek hai and pata nahi."
    ),
    (
        "normalizes technical multi-word terms",
        "Open the pull request after the k eights deploy.",
        "Open the PR after the k8s deploy."
    ),
    (
        "matches variants case-insensitively",
        "PATA NAHEE.",
        "pata nahi."
    ),
    (
        "does not replace inside larger words",
        "The pull requester opened a mat laboratory.",
        "The pull requester opened a mat laboratory."
    )
]

for check in slangNormalizationChecks {
    let actual = BuiltInSlangLexicon.normalizeColloquialPhrases(check.input)
    guard actual == check.expected else {
        FileHandle.standardError.write(
            Data(
                (
                    "FAIL: slang lexicon \(check.name)\nExpected: "
                        + "\(check.expected)\nActual: \(actual)\n"
                ).utf8
            )
        )
        exit(1)
    }
}

let formattedSlang = await TranscriptFormattingEngine().format(
    "Please confirm theek hey before merging the pull request.",
    mode: .clean
)
guard formattedSlang.text
        == "Please confirm theek hai before merging the PR.",
      formattedSlang.changed else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: slang normalization was not applied by formatting: "
                + "\(formattedSlang.text)\n").utf8
        )
    )
    exit(1)
}

guard BuiltInSlangLexicon.contextPrompt(for: .hinglish)
        .hasPrefix("Hinglish dictation:"),
      BuiltInSlangLexicon.contextPrompt(for: .english)
        .hasPrefix("Technical dictation:"),
      LanguageProfile.hinglish.isHinglish,
      !LanguageProfile.english.isHinglish else {
    FileHandle.standardError.write(
        Data("FAIL: built-in language prompt routing is incorrect\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: transcript safety and slang coverage passed")

// Discourse markers, measured escaping Clean by the accuracy harness. The
// reference is what the speaker meant, so both the markers and the commas
// bracketing them have to go.
let discourseRefinement = instantRefiner.refine(
    "The API, you know, returns a cached response, like, "
        + "when the token is valid.",
    mode: .clean
)
guard discourseRefinement.text
        == "The API returns a cached response when the token is valid.",
      !discourseRefinement.wasRejected else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: discourse markers survived Clean: "
                + "\(discourseRefinement.text)\n").utf8
        )
    )
    exit(1)
}

// "like" and "you know" are ordinary words when the speaker did not pause
// around them. Deleting them unconditionally would eat real content, so this
// pins the distinction the comma bracketing is carrying.
let meaningfulLike = instantRefiner.refine(
    "I like the way you know the answer.",
    mode: .clean
)
guard meaningfulLike.text == "I like the way you know the answer.",
      meaningfulLike.correctionCount == 0 else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: meaningful “like”/“you know” was removed: "
                + "\(meaningfulLike.text)\n").utf8
        )
    )
    exit(1)
}

// "ah" as a filler stem, and the recapitalization that removing a
// sentence-opening filler requires.
let ahRefinement = instantRefiner.refine(
    "Do not merge the branch. Ah, until the tests pass.",
    mode: .clean
)
guard ahRefinement.text
        == "Do not merge the branch. Until the tests pass.",
      !ahRefinement.wasRejected else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: sentence-opening filler was not cleaned: "
                + "\(ahRefinement.text)\n").utf8
        )
    )
    exit(1)
}

// Phrase-level restart. Found by the accuracy harness once the decode was
// pinned: the speaker says "we should" twice, and the single-word repetition
// rule cannot see it because no two adjacent words are equal.
let phraseRestart = instantRefiner.refine(
    "We should we should probably revert the change before the release.",
    mode: .clean
)
guard phraseRestart.text
        == "We should probably revert the change before the release.",
      !phraseRestart.wasRejected else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: repeated phrase survived Clean: "
                + "\(phraseRestart.text)\n").utf8
        )
    )
    exit(1)
}

// Three repeats collapse to one, not to two. A restart is often stuttered
// more than once, and a rule that halves it leaves the transcript still wrong.
let tripledRestart = instantRefiner.refine(
    "I want to I want to I want to add dark mode.",
    mode: .clean
)
guard tripledRestart.text == "I want to add dark mode.",
      !tripledRestart.wasRejected else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: tripled phrase was not fully collapsed: "
                + "\(tripledRestart.text)\n").utf8
        )
    )
    exit(1)
}

// A phrase that recurs without being adjacent is ordinary English, not a
// restart, and must survive untouched.
let recurringPhrase = instantRefiner.refine(
    "The more you test the more you learn.",
    mode: .clean
)
guard recurringPhrase.text == "The more you test the more you learn.",
      recurringPhrase.correctionCount == 0 else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: a non-adjacent recurring phrase was collapsed: "
                + "\(recurringPhrase.text)\n").utf8
        )
    )
    exit(1)
}

// Punctuation between the halves is the speaker marking the repeat as
// deliberate, so it is left alone.
let deliberateRepeat = instantRefiner.refine(
    "Come on, come on, the build is nearly done.",
    mode: .clean
)
guard deliberateRepeat.text
        == "Come on, come on, the build is nearly done." else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: a deliberate punctuated repeat was collapsed: "
                + "\(deliberateRepeat.text)\n").utf8
        )
    )
    exit(1)
}

// Devanagari repetition. This did not work at all until the character classes
// admitted combining marks: a Hindi vowel sign is a mark, not a letter, so
// [\p{L}\p{N}] broke "गूगल" after its first consonant and no repeat could
// ever match. The rules looked script-neutral and silently were not.
let devanagariRepeat = instantRefiner.refine(
    "गूगल गूगल फिट पर 100 पुशअप जोड़ो",
    mode: .clean
)
guard devanagariRepeat.text == "गूगल फिट पर 100 पुशअप जोड़ो" else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: Devanagari repetition survived: "
                + "\(devanagariRepeat.text)\n").utf8
        )
    )
    exit(1)
}

let devanagariPhraseRepeat = instantRefiner.refine(
    "आज रात आज रात की पार्टी के बारे में मैसेजेस दिखाओ",
    mode: .clean
)
guard devanagariPhraseRepeat.text
        == "आज रात की पार्टी के बारे में मैसेजेस दिखाओ" else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: Devanagari phrase repetition survived: "
                + "\(devanagariPhraseRepeat.text)\n").utf8
        )
    )
    exit(1)
}

// Hindi hesitation sounds, the counterparts of um and uh.
let hindiFiller = instantRefiner.refine(
    "मुझे उम्म, १२३४ स्ट्रीट से पिक करें",
    mode: .clean
)
guard hindiFiller.text == "मुझे १२३४ स्ट्रीट से पिक करें" else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: Hindi filler survived: \(hindiFiller.text)\n").utf8
        )
    )
    exit(1)
}

// "वो क्या कहते हैं" is a speaker stalling for a word, like "you know".
let hindiStall = instantRefiner.refine(
    "इस नंबर को पापा के वो क्या कहते हैं ऑफिस नंबर करके ऐड करो",
    mode: .clean
)
guard hindiStall.text == "इस नंबर को पापा के ऑफिस नंबर करके ऐड करो" else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: Hindi stall phrase survived: \(hindiStall.text)\n").utf8
        )
    )
    exit(1)
}

// A Hindi word that merely begins with the filler letters must survive. The
// filler needs a doubled म where अमेरिका has a vowel sign.
let hindiLookalike = instantRefiner.refine(
    "अमेरिका से मेरा पार्सल कब आएगा",
    mode: .clean
)
guard hindiLookalike.text == "अमेरिका से मेरा पार्सल कब आएगा",
      hindiLookalike.correctionCount == 0 else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: a Hindi word was mistaken for a filler: "
                + "\(hindiLookalike.text)\n").utf8
        )
    )
    exit(1)
}

// "err" is a verb, not a filler stem. Its near-miss with "er" is why "er" is
// not in the stem list at all.
let errRefinement = instantRefiner.refine(
    "Err on the side of caution.",
    mode: .clean
)
guard errRefinement.text == "Err on the side of caution.",
      errRefinement.correctionCount == 0 else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: “err” was treated as a filler: "
                + "\(errRefinement.text)\n").utf8
        )
    )
    exit(1)
}

// Sentence capitalization must not fire inside a decimal.
let decimalRefinement = instantRefiner.refine(
    "Set the timeout to 3.5 seconds.",
    mode: .clean
)
guard decimalRefinement.text == "Set the timeout to 3.5 seconds." else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: decimal was treated as a sentence break: "
                + "\(decimalRefinement.text)\n").utf8
        )
    )
    exit(1)
}

let disabledRefinement = instantRefiner.refine(
    "um keep this",
    mode: .off
)
guard disabledRefinement.text == "um keep this",
      disabledRefinement.correctionCount == 0 else {
    FileHandle.standardError.write(
        Data("FAIL: disabled Instant Refine changed text\n".utf8)
    )
    exit(1)
}

let refineSuite = "ZenVoiceCoreChecks.Refine.\(UUID().uuidString)"
guard let refineDefaults = UserDefaults(suiteName: refineSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create refinement preference fixture\n".utf8)
    )
    exit(1)
}
defer {
    refineDefaults.removePersistentDomain(forName: refineSuite)
}
guard InstantRefinePreferences.load(defaults: refineDefaults) == .clean else {
    FileHandle.standardError.write(
        Data("FAIL: Instant Refine did not default to Clean\n".utf8)
    )
    exit(1)
}
InstantRefinePreferences.save(.agentPrompt, defaults: refineDefaults)
guard InstantRefinePreferences.load(defaults: refineDefaults)
        == .agentPrompt else {
    FileHandle.standardError.write(
        Data("FAIL: Instant Refine preference did not persist\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: Instant Refine passed")

// A Hinglish user must be recommended the specialist, whatever their hardware.
//
// Recommending on hardware alone sent them to Whisper Turbo, which preserves
// none of the English half of a code-switched sentence: measured on real
// recordings it kept 0 of 5 English words on a clip the specialist handles.
let capableMac = HardwareProfile(
    physicalMemoryBytes: 32 * 1_073_741_824,
    logicalCoreCount: 12,
    architecture: "Apple Silicon",
    availableModelStorageBytes: 200 * 1_073_741_824
)
let intelMac = HardwareProfile(
    physicalMemoryBytes: 16 * 1_073_741_824,
    logicalCoreCount: 8,
    architecture: "Intel",
    availableModelStorageBytes: 200 * 1_073_741_824
)
// English on Apple Silicon now goes to Whisper Turbo: it is the best open
// multilingual model available through whisper.cpp. An Intel Mac — with no GPU
// transcription — must not be sent to a large model.
guard ModelRecommendationEngine.recommendedModelID(
        for: capableMac,
        language: .hinglish
      ) == "hindi2hinglish-apex",
      ModelRecommendationEngine.recommendedModelID(
        for: intelMac,
        language: .hinglish
      ) == "hindi2hinglish-apex",
      ModelRecommendationEngine.recommendedModelID(
        for: capableMac,
        language: .english
      ) == "whisper-large-v3-turbo",
      ModelRecommendationEngine.recommendedModelID(
        for: intelMac,
        language: .english
      ) != "whisper-large-v3-turbo" else {
    FileHandle.standardError.write(
        Data("FAIL: language-aware model recommendation is wrong\n".utf8)
    )
    exit(1)
}
// Every identifier the engine can return has to exist in the catalogue.
// Retiring a model that the recommender still points at would leave a Mac with
// no resolvable recommendation at all.
for profile in [capableMac, intelMac] {
    for language in [LanguageProfile.english, .hinglish] {
        let id = ModelRecommendationEngine.recommendedModelID(
            for: profile,
            language: language
        )
        guard let recommended = VerifiedModelCatalog.model(id: id),
              !VerifiedModelCatalog.isRetired(recommended) else {
            FileHandle.standardError.write(
                Data("FAIL: recommended \(id) is not offered\n".utf8)
            )
            exit(1)
        }
    }
}
// The catalogue is deliberately four. Each entry is the measured best at one
// job; the size ladders it replaced were not a speed-for-accuracy curve.
guard VerifiedModelCatalog.models.count == 4 else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: expected 4 offered models, found "
                + "\(VerifiedModelCatalog.models.count)\n").utf8
        )
    )
    exit(1)
}
// Retired models must stay resolvable, or an installed model becomes "no model
// installed" and discovery silently falls back to the legacy base.en path.
for id in [
    "whisper-medium-en",
    "whisper-tiny-en",
    "whisper-tiny-multilingual",
    "whisper-base-en",
    "whisper-base-multilingual",
    "whisper-small-en"
] {
    guard let retired = VerifiedModelCatalog.model(id: id),
          VerifiedModelCatalog.isRetired(retired) else {
        FileHandle.standardError.write(
            Data("FAIL: retired \(id) is no longer resolvable\n".utf8)
        )
        exit(1)
    }
}
guard let apex = VerifiedModelCatalog.model(id: "hindi2hinglish-apex"),
      let medium = VerifiedModelCatalog.model(
          id: "whisper-medium-multilingual"
      ),
      ModelRecommendationEngine.recommendation(
          for: apex,
          profile: capableMac,
          language: .hinglish
      ).rationale.contains("code-switching"),
      !ModelRecommendationEngine.recommendation(
          for: medium,
          profile: capableMac,
          language: .english
      ).rationale.contains("same accuracy") else {
    FileHandle.standardError.write(
        Data("FAIL: model recommendation copy is misleading\n".utf8)
    )
    exit(1)
}

// And a general multilingual model must not be offered for Hinglish at all.
guard !LanguageProfile.hinglish.isCompatible(with: .multilingual),
      LanguageProfile.hinglish.isCompatible(with: .hinglish),
      // The reverse still holds: the specialist is not a general model.
      !LanguageProfile.english.isCompatible(with: .hinglish),
      LanguageProfile.english.isCompatible(with: .multilingual),
      // A non-English language that is not Hinglish still uses a general
      // multilingual model, which is the only option it has.
      LanguageProfile(inputLanguageCode: "es", outputMode: .spokenLanguage)
        .isCompatible(with: .multilingual) else {
    FileHandle.standardError.write(
        Data("FAIL: language/model compatibility is wrong\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: language-aware model recommendation passed")

// Model and profile changes are one transition. Neither settings screen may
// reject the other side's current value and leave a user unable to move from
// a retired English model to the Hinglish specialist.
guard let retiredEnglish = VerifiedModelCatalog.model(
        id: "whisper-medium-en"
      ),
      let turbo = VerifiedModelCatalog.model(
          id: "whisper-large-v3-turbo"
      ),
      VerifiedModelCatalog.isRetired(retiredEnglish),
      !VerifiedModelCatalog.models.contains(where: {
          $0.id == retiredEnglish.id
      }),
      VerifiedModelCatalog.allModels.contains(where: {
          $0.id == retiredEnglish.id
      }),
      ModelProfileTransition.profileForSelecting(
          model: apex,
          currentProfile: .english
      ) == .hinglish,
      ModelProfileTransition.profileForSelecting(
          model: retiredEnglish,
          currentProfile: LanguageProfile(
              inputLanguageCode: "hi",
              outputMode: .spokenLanguage
          )
      ) == .english,
      ModelProfileTransition.profileForSelecting(
          model: turbo,
          currentProfile: .hinglish
      ) == nil,
      ModelProfileTransition.modelForSelecting(
          profile: .hinglish,
          currentModel: retiredEnglish,
          installedModels: [retiredEnglish, apex, turbo],
          recommendedModelID: apex.id
      ) == apex,
      ModelProfileTransition.modelForSelecting(
          profile: .english,
          currentModel: apex,
          installedModels: [retiredEnglish, apex, turbo],
          recommendedModelID: turbo.id
      ) == turbo,
      // Existing compatible legacy selections remain stable until the user
      // explicitly chooses a replacement.
      ModelProfileTransition.modelForSelecting(
          profile: .english,
          currentModel: retiredEnglish,
          installedModels: [retiredEnglish, apex, turbo],
          recommendedModelID: turbo.id
      ) == retiredEnglish,
      ModelProfileTransition.modelForSelecting(
          profile: .hinglish,
          currentModel: retiredEnglish,
          installedModels: [retiredEnglish, turbo],
          recommendedModelID: apex.id
      ) == nil,
      ModelProfileTransition.unavailableMessage(for: .hinglish)
        .contains("Hinglish Apex"),
      ModelProfileTransition.unavailableMessage(for: .english)
        .contains("English or multilingual"),
      ModelProfileTransition.incompatibilityBadge(
          model: apex,
          currentProfile: .english
      ) == "Hinglish only",
      ModelProfileTransition.incompatibilityBadge(
          model: turbo,
          currentProfile: .hinglish
      ) == "Not for Hinglish",
      ModelProfileTransition.incompatibilityBadge(
          model: retiredEnglish,
          currentProfile: LanguageProfile(
              inputLanguageCode: "hi",
              outputMode: .spokenLanguage
          )
      ) == "English only" else {
    FileHandle.standardError.write(
        Data("FAIL: atomic model/profile transition policy is wrong\n".utf8)
    )
    exit(1)
}

enum TransitionFixtureError: Error {
    case preparationFailed
}

let transitionSuite = "ZenVoiceTransition.\(UUID().uuidString)"
guard let transitionDefaults = UserDefaults(suiteName: transitionSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create transition preference fixture\n".utf8)
    )
    exit(1)
}
defer {
    transitionDefaults.removePersistentDomain(forName: transitionSuite)
}
ModelSelectionPreferences.save(
    retiredEnglish,
    defaults: transitionDefaults
)
LanguagePreferences.save(.english, defaults: transitionDefaults)
do {
    let _: String = try ModelProfileTransition.prepareAndCommit(
        model: apex,
        profile: .hinglish,
        defaults: transitionDefaults
    ) {
        throw TransitionFixtureError.preparationFailed
    }
    FileHandle.standardError.write(
        Data("FAIL: failed transition unexpectedly committed\n".utf8)
    )
    exit(1)
} catch TransitionFixtureError.preparationFailed {
    // Expected: the old pair must remain intact.
}
guard ModelSelectionPreferences.load(defaults: transitionDefaults)
        == retiredEnglish,
      LanguagePreferences.load(defaults: transitionDefaults) == .english else {
    FileHandle.standardError.write(
        Data("FAIL: failed transition changed preferences\n".utf8)
    )
    exit(1)
}
let preparedMarker = ModelProfileTransition.prepareAndCommit(
    model: apex,
    profile: .hinglish,
    defaults: transitionDefaults
) {
    "prepared"
}
guard preparedMarker == "prepared",
      ModelSelectionPreferences.load(defaults: transitionDefaults) == apex,
      LanguagePreferences.load(defaults: transitionDefaults) == .hinglish else {
    FileHandle.standardError.write(
        Data("FAIL: prepared transition did not commit atomically\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: atomic model/profile transitions passed")

// Paragraph structure from the speaker's pauses.
//
// The silences are supplied rather than measured here, because the point
// under test is the decision, not the energy detection.
let structureSegments = [
    TranscriptSegment(
        text: "Please refactor the middleware.",
        startSeconds: 0,
        endSeconds: 3
    ),
    TranscriptSegment(
        text: "It validates the token.",
        startSeconds: 4.5,
        endSeconds: 7
    ),
    TranscriptSegment(
        text: "And returns unauthorized.",
        startSeconds: 7.1,
        endSeconds: 9
    )
]
// A long pause after a finished sentence, and a short one after the next.
let structured = SpokenStructure.text(
    from: structureSegments,
    silences: [
        (0.2, 0.3), (1.1, 1.2), (3.0, 4.5), (5.4, 5.5), (7.0, 7.1)
    ]
)
guard structured == """
Please refactor the middleware.

It validates the token. And returns unauthorized.
""" else {
    FileHandle.standardError.write(
        Data("FAIL: paragraph structure is wrong: \(structured)\n".utf8)
    )
    exit(1)
}

// Without the audio there are no pauses to read, so no break may be invented.
guard SpokenStructure.text(from: structureSegments, silences: [])
        == "Please refactor the middleware. It validates the token. "
            + "And returns unauthorized." else {
    FileHandle.standardError.write(
        Data("FAIL: a break was taken without any measured pause\n".utf8)
    )
    exit(1)
}

// A pause mid-sentence is hesitation, not a new thought. The previous segment
// has to have come to a close before its pause can end a paragraph.
let unfinished = SpokenStructure.text(
    from: [
        TranscriptSegment(
            text: "Please refactor the",
            startSeconds: 0,
            endSeconds: 3
        ),
        TranscriptSegment(
            text: "middleware today.",
            startSeconds: 4.5,
            endSeconds: 6
        )
    ],
    silences: [(0.2, 0.3), (3.0, 4.5)]
)
guard unfinished == "Please refactor the middleware today." else {
    FileHandle.standardError.write(
        Data(
            ("FAIL: a paragraph broke mid-sentence: \(unfinished)\n").utf8
        )
    )
    exit(1)
}

print("ZenVoiceCoreChecks: spoken structure passed")

let applicationSuite =
    "ZenVoiceCoreChecks.ApplicationProfiles.\(UUID().uuidString)"
guard let applicationDefaults =
    UserDefaults(suiteName: applicationSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create application profile fixture\n".utf8)
    )
    exit(1)
}
defer {
    applicationDefaults.removePersistentDomain(
        forName: applicationSuite
    )
}
let mailProfile = ApplicationProfile(
    bundleIdentifier: "com.example.mail",
    applicationName: "Example Mail",
    languageProfile: LanguageProfile(
        inputLanguageCode: "es",
        outputMode: .spokenLanguage
    ),
    formattingMode: .clean,
    voiceCommandsEnabled: true,
    preferredEngineID: EngineIdentifiers.appleSpeech,
    preferredOutputMode: .englishTranslation
)
ApplicationProfilePreferences.save(
    mailProfile,
    defaults: applicationDefaults
)
guard ApplicationProfilePreferences.profile(
    for: mailProfile.bundleIdentifier,
    defaults: applicationDefaults
) == mailProfile else {
    FileHandle.standardError.write(
        Data("FAIL: application profile did not persist\n".utf8)
    )
    exit(1)
}
guard let loadedProfile = ApplicationProfilePreferences.profile(
    for: mailProfile.bundleIdentifier,
    defaults: applicationDefaults
),
      loadedProfile.preferredEngineID == EngineIdentifiers.appleSpeech,
      loadedProfile.preferredOutputMode == .englishTranslation else {
    FileHandle.standardError.write(
        Data(
            "FAIL: per-app engine or output mode did not persist\n".utf8
        )
    )
    exit(1)
}
let encodedProfiles = try JSONEncoder().encode([mailProfile])
guard var legacyProfiles = try JSONSerialization.jsonObject(
    with: encodedProfiles
) as? [[String: Any]] else {
    FileHandle.standardError.write(
        Data("FAIL: could not create legacy application profile\n".utf8)
    )
    exit(1)
}
legacyProfiles[0].removeValue(forKey: "customPromptHints")
applicationDefaults.set(
    try JSONSerialization.data(withJSONObject: legacyProfiles),
    forKey: ApplicationProfilePreferences.preferenceKey
)
guard let migratedProfile = ApplicationProfilePreferences.profile(
    for: mailProfile.bundleIdentifier,
    defaults: applicationDefaults
), migratedProfile.customPromptHints.isEmpty else {
    FileHandle.standardError.write(
        Data("FAIL: legacy application profile did not migrate\n".utf8)
    )
    exit(1)
}
ApplicationProfilePreferences.remove(
    bundleIdentifier: mailProfile.bundleIdentifier,
    defaults: applicationDefaults
)
guard ApplicationProfilePreferences.load(
    defaults: applicationDefaults
).isEmpty else {
    FileHandle.standardError.write(
        Data("FAIL: application profile was not removed\n".utf8)
    )
    exit(1)
}
guard !LocalVoiceCommandPreferences.isEnabled(
    defaults: applicationDefaults
) else {
    FileHandle.standardError.write(
        Data("FAIL: voice commands did not default off\n".utf8)
    )
    exit(1)
}
LocalVoiceCommandPreferences.setEnabled(
    true,
    defaults: applicationDefaults
)
guard LocalVoiceCommandPreferences.isEnabled(
    defaults: applicationDefaults
) else {
    FileHandle.standardError.write(
        Data("FAIL: voice command preference did not persist\n".utf8)
    )
    exit(1)
}

let commandEngine = LocalVoiceCommandEngine()
guard commandEngine.apply(
    to: "Hello new line world full stop",
    languageCode: "en",
    isEnabled: true
).text == "Hello\nworld.",
      commandEngine.apply(
        to: "Hola nueva línea mundo punto",
        languageCode: "es",
        isEnabled: true
      ).text == "Hola\nmundo.",
      commandEngine.apply(
        to: "你好换行世界句号",
        languageCode: "zh",
        isEnabled: true
      ).text == "你好\n世界。",
      commandEngine.apply(
        to: "Keep new line literal",
        languageCode: "en",
        isEnabled: false
      ).text == "Keep new line literal" else {
    FileHandle.standardError.write(
        Data("FAIL: local voice commands are incorrect\n".utf8)
    )
    exit(1)
}

let unsafeContext =
    String(repeating: "ZenVoice ", count: 100) + "<|im_end|>\nSwiftUI"
let safeContext = NextDictationContext.sanitized(unsafeContext)
let vocabularyContext = NextDictationContext.combined(
    context: unsafeContext,
    preferredVocabulary: [
        "Chaudhary",
        "ZenPense",
        "build",
        "ZenPense",
        "<|bad|>"
    ]
)
let defaultVocabularyContext = NextDictationContext.combined(
    context: "",
    preferredVocabulary: []
)
guard safeContext.count <= NextDictationContext.maximumCharacterCount,
      !safeContext.contains("<|"),
      !safeContext.contains("\n"),
      vocabularyContext.count
        <= NextDictationContext.maximumCharacterCount,
      vocabularyContext.hasPrefix(
          "Preferred vocabulary: Chaudhary, ZenPense, build, bad."
      ),
      defaultVocabularyContext
        == "Preferred vocabulary: PR, repo, deploy, k8s, LLM, API, "
            + "theek, matlab, acha, bhai, jugaad, pakka.",
      !vocabularyContext.contains("<|"),
      vocabularyContext.components(separatedBy: "ZenPense").count == 2 else {
    FileHandle.standardError.write(
        Data(
            "FAIL: next-dictation context or vocabulary was not bounded\n"
                .utf8
        )
    )
    exit(1)
}

print("ZenVoiceCoreChecks: application context and commands passed")

let onboardingSuite =
    "ZenVoiceCoreChecks.Onboarding.\(UUID().uuidString)"
guard let onboardingDefaults =
    UserDefaults(suiteName: onboardingSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create onboarding fixture\n".utf8)
    )
    exit(1)
}
defer {
    onboardingDefaults.removePersistentDomain(
        forName: onboardingSuite
    )
}
guard OnboardingPreferences.shouldPresent(
    defaults: onboardingDefaults
) else {
    FileHandle.standardError.write(
        Data("FAIL: fresh install skipped onboarding\n".utf8)
    )
    exit(1)
}
OnboardingPreferences.complete(defaults: onboardingDefaults)
guard !OnboardingPreferences.shouldPresent(
    defaults: onboardingDefaults
) else {
    FileHandle.standardError.write(
        Data("FAIL: completed onboarding returned\n".utf8)
    )
    exit(1)
}
OnboardingPreferences.reset(defaults: onboardingDefaults)
guard OnboardingPreferences.shouldPresent(
    defaults: onboardingDefaults
) else {
    FileHandle.standardError.write(
        Data("FAIL: onboarding reset was ignored\n".utf8)
    )
    exit(1)
}
onboardingDefaults.removePersistentDomain(
    forName: onboardingSuite
)
LanguagePreferences.save(.english, defaults: onboardingDefaults)
guard !OnboardingPreferences.shouldPresent(
    defaults: onboardingDefaults
),
      onboardingDefaults.bool(
        forKey: OnboardingPreferences.completionKey
      ) else {
    FileHandle.standardError.write(
        Data("FAIL: existing install was forced into onboarding\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: onboarding lifecycle passed")

var quietMeter = AudioLevelMeter()
let quietLevel = quietMeter.update(
    averageDecibels: -42,
    peakDecibels: -34
)

var loudMeter = AudioLevelMeter()
let loudLevel = loudMeter.update(
    averageDecibels: -14,
    peakDecibels: -7
)

guard quietLevel > 0, loudLevel > quietLevel else {
    FileHandle.standardError.write(
        Data("FAIL: loud speech must produce taller waveform levels\n".utf8)
    )
    exit(1)
}

guard AudioLevelMeter.normalize(decibels: -70) == 0,
      AudioLevelMeter.normalize(decibels: -3) == 1 else {
    FileHandle.standardError.write(
        Data("FAIL: audio meter must clamp silence and loud input\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: audio level response passed")

let defaultHotKey = HotKeyConfiguration.dictationDefault
guard defaultHotKey.isValid,
      defaultHotKey.displayName == "⌃ ⌥ Space" else {
    FileHandle.standardError.write(
        Data("FAIL: default hotkey configuration is invalid\n".utf8)
    )
    exit(1)
}

let encodedHotKey = try JSONEncoder().encode(defaultHotKey)
let decodedHotKey = try JSONDecoder().decode(
    HotKeyConfiguration.self,
    from: encodedHotKey
)
guard decodedHotKey == defaultHotKey else {
    FileHandle.standardError.write(
        Data("FAIL: hotkey configuration did not persist correctly\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: hotkey configuration passed")

let pasteLastHotKey = HotKeyConfiguration.pasteLastDefault
guard pasteLastHotKey.isValid,
      pasteLastHotKey.displayName == "⌃ ⌥ V",
      pasteLastHotKey != defaultHotKey else {
    FileHandle.standardError.write(
        Data("FAIL: paste-last hotkey configuration is invalid\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: recovery hotkey configuration passed")

let privateHotKey = HotKeyConfiguration.privateModeDefault
guard privateHotKey.isValid,
      privateHotKey.displayName == "⌃ ⌥ P",
      privateHotKey != defaultHotKey,
      privateHotKey != pasteLastHotKey else {
    FileHandle.standardError.write(
        Data("FAIL: private-mode hotkey configuration is invalid\n".utf8)
    )
    exit(1)
}

let unknownModifier = HotKeyConfiguration(
    keyCode: 49,
    modifiers: HotKeyModifiers(rawValue: 1 << 10),
    keyLabel: "Space"
)
guard !unknownModifier.isValid else {
    FileHandle.standardError.write(
        Data("FAIL: unknown persisted modifier was accepted\n".utf8)
    )
    exit(1)
}

// Option-only shortcuts must stay valid. A previous revision rejected them,
// believing the text input system swallowed them in apps with a focused text
// field; a registered ⌥Space hot key was measured being delivered in both a
// browser and a terminal. Rejecting them invalidated shortcuts already in use,
// which were then silently swapped for the default. Guard against a
// reintroduction.
for optionOnly in [
    HotKeyConfiguration(keyCode: 49, modifiers: [.option], keyLabel: "Space"),
    HotKeyConfiguration(keyCode: 46, modifiers: [.option], keyLabel: "M"),
    HotKeyConfiguration(
        keyCode: 35,
        modifiers: [.option, .shift],
        keyLabel: "P"
    ),
    HotKeyConfiguration(keyCode: 49, modifiers: [.shift], keyLabel: "Space")
] {
    guard optionOnly.isValid else {
        FileHandle.standardError.write(
            Data(
                "FAIL: shortcut \(optionOnly.displayName) must remain valid\n".utf8
            )
        )
        exit(1)
    }
}

print("ZenVoiceCoreChecks: option-only shortcuts remain valid")

let mismatchedLabel = HotKeyConfiguration(
    keyCode: 49,
    modifiers: [.control],
    keyLabel: "P"
)
guard !mismatchedLabel.isValid,
      HotKeyConfiguration.canonicalLabel(forKeyCode: 35) == "P",
      HotKeyConfiguration.canonicalLabel(forKeyCode: 127) == nil else {
    FileHandle.standardError.write(
        Data("FAIL: hotkey labels are not bound to key codes\n".utf8)
    )
    exit(1)
}

for choice in HoldKeyChoice.allCases {
    let encoded = try JSONEncoder().encode(choice)
    guard try JSONDecoder().decode(HoldKeyChoice.self, from: encoded) == choice,
          HoldKeyChoice(keyCode: choice.keyCode) == choice,
          !choice.displayName.isEmpty else {
        FileHandle.standardError.write(
            Data("FAIL: hold-to-dictate choice is invalid\n".utf8)
        )
        exit(1)
    }
}
guard Set(HoldKeyChoice.allCases.map(\.keyCode)).count
        == HoldKeyChoice.allCases.count else {
    FileHandle.standardError.write(
        Data("FAIL: hold-to-dictate key codes are not unique\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: private and hold controls passed")

// Metadata is checked across offered *and* retired models, because a retired
// entry is still resolved and verified for anyone who already installed it.
let verifiedModels = VerifiedModelCatalog.allModels
// Four offered, seven retired. Parakeet was retired because it depends on the
// closed-source FluidAudio runtime; Whisper is now the only transcription
// engine — see ``VerifiedModelCatalog.models``.
guard VerifiedModelCatalog.models.count == 4,
      verifiedModels.count == 11,
      // Nothing retired may still be offered, and everything retired must
      // still resolve — by identifier and by filename — so that a model
      // already on disk does not become "no model installed".
      VerifiedModelCatalog.retiredModels.allSatisfy({ retired in
          VerifiedModelCatalog.models.allSatisfy { $0.id != retired.id }
              && VerifiedModelCatalog.model(id: retired.id) != nil
              && VerifiedModelCatalog.model(
                  filename: retired.filename
              )?.id == retired.id
      }),
      Set(verifiedModels.map(\.id)).count == verifiedModels.count,
      Set(verifiedModels.map(\.filename)).count == verifiedModels.count,
      Set(verifiedModels.map(\.tier))
        == Set(ModelPerformanceTier.allCases),
      Set(verifiedModels.map(\.languageCapability))
        == Set(ModelLanguageCapability.allCases),
      verifiedModels.allSatisfy({
          $0.downloadURL.scheme == "https"
              && $0.downloadURL.host == "huggingface.co"
              && $0.downloadURL.path.contains($0.sourceRevision)
              && $0.sha256.count == 64
              && $0.fileSizeBytes > 0
              // Every allowed licence permits redistribution with its required
              // notice or attribution, which `attribution` carries. The NVIDIA
              // Open Model License permits commercial use, redistribution and
              // derivative works, and requires the notice line that the
              // Parakeet entry's attribution now begins with.
              && [
                  "MIT",
                  "Apache-2.0",
                  "CC-BY-4.0",
                  "NVIDIA Open Model License"
              ].contains($0.license)
              && !$0.attribution.isEmpty
              && URL(string: $0.licenseURL)?.scheme == "https"
              && ["github.com", "huggingface.co"].contains(
                  URL(string: $0.upstreamRepository)?.host
              )
      }) else {
    FileHandle.standardError.write(
        Data("FAIL: verified model catalogue metadata is invalid\n".utf8)
    )
    exit(1)
}

let verifierDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(
    at: verifierDirectory,
    withIntermediateDirectories: true
)
defer {
    try? FileManager.default.removeItem(at: verifierDirectory)
}
let verifierURL = verifierDirectory.appendingPathComponent("fixture.bin")
try Data("ZenVoice".utf8).write(to: verifierURL)
let verifierModel = VerifiedModel(
    id: "fixture",
    displayName: "Fixture",
    filename: "fixture.bin",
    tier: .fast,
    languageCapability: .english,
    publisher: "Test",
    sourceRepository: VerifiedModelCatalog.sourceRepository,
    upstreamRepository: "https://github.com/openai/whisper",
    sourceRevision: VerifiedModelCatalog.sourceRevision,
    sha256:
        "954be634e5f577bc940ed27375984b9eb15d137455b6ea8086f4f2b76c526596",
    fileSizeBytes: 8,
    format: "fixture",
    license: "MIT",
    licenseURL:
        "https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE",
    attribution: "Test fixture"
)
guard try VerifiedModelCatalog.verify(verifierURL, for: verifierModel) else {
    FileHandle.standardError.write(
        Data("FAIL: SHA-256 model verification rejected valid data\n".utf8)
    )
    exit(1)
}
try Data("ZenVoicf".utf8).write(to: verifierURL)
guard try !VerifiedModelCatalog.verify(verifierURL, for: verifierModel) else {
    FileHandle.standardError.write(
        Data("FAIL: SHA-256 model verification accepted tampered data\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: bundle manifest verification skipped — no multi-file bundles")

let selectionSuite = "ZenVoiceCoreChecks.\(UUID().uuidString)"
guard let selectionDefaults = UserDefaults(suiteName: selectionSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create model preference fixture\n".utf8)
    )
    exit(1)
}
defer {
    selectionDefaults.removePersistentDomain(forName: selectionSuite)
}
let selectedFixture = verifiedModels[2]
ModelSelectionPreferences.save(
    selectedFixture,
    defaults: selectionDefaults
)
guard ModelSelectionPreferences.load(defaults: selectionDefaults)
        == selectedFixture else {
    FileHandle.standardError.write(
        Data("FAIL: selected model preference did not round-trip\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: verified model catalogue passed")

let eightGigabyteProfile = HardwareProfile(
    physicalMemoryBytes: 8 * 1_073_741_824,
    logicalCoreCount: 8,
    architecture: "Apple Silicon",
    availableModelStorageBytes: 10_000_000_000
)
let sixteenGigabyteProfile = HardwareProfile(
    physicalMemoryBytes: 16 * 1_073_741_824,
    logicalCoreCount: 10,
    architecture: "Apple Silicon",
    availableModelStorageBytes: 10_000_000_000
)
let twentyFourGigabyteProfile = HardwareProfile(
    physicalMemoryBytes: 24 * 1_073_741_824,
    logicalCoreCount: 12,
    architecture: "Apple Silicon",
    availableModelStorageBytes: 10_000_000_000
)
// Apple Silicon transcribes on the GPU, so no Metal-capable Mac should be
// downgraded on memory alone — recommending by memory sent 16 GB Macs to
// Whisper Base, which loses roughly one word in three at speed.
//
// English now resolves to Whisper Turbo on all of them. Anything beyond English
// still goes to Turbo: every smaller multilingual build is a cliff, not a
// cheaper option, with Small at 35.5% word error rate against Turbo's 13.2%.
let spanishProfile = LanguageProfile(
    inputLanguageCode: "es",
    outputMode: .spokenLanguage
)
guard ModelRecommendationEngine.recommendedModelID(
    for: eightGigabyteProfile
) == "whisper-large-v3-turbo",
ModelRecommendationEngine.recommendedModelID(
    for: sixteenGigabyteProfile
) == "whisper-large-v3-turbo",
ModelRecommendationEngine.recommendedModelID(
    for: twentyFourGigabyteProfile
) == "whisper-large-v3-turbo",
ModelRecommendationEngine.recommendedModelID(
    for: eightGigabyteProfile,
    language: spanishProfile
) == "whisper-large-v3-turbo",
ModelRecommendationEngine.recommendedModelID(
    for: twentyFourGigabyteProfile,
    language: spanishProfile
) == "whisper-large-v3-turbo",
ModelRecommendationEngine.recommendedTier(
    for: sixteenGigabyteProfile,
    language: spanishProfile
) == .highAccuracy else {
    FileHandle.standardError.write(
        Data("FAIL: hardware model recommendation is incorrect\n".utf8)
    )
    exit(1)
}

// Without a Metal path, model size turns straight into waiting, so the
// recommendation has to come down.
let intelProfile = HardwareProfile(
    physicalMemoryBytes: 16 * 1_073_741_824,
    logicalCoreCount: 8,
    architecture: "Intel",
    availableModelStorageBytes: 10_000_000_000
)
let smallIntelProfile = HardwareProfile(
    physicalMemoryBytes: 8 * 1_073_741_824,
    logicalCoreCount: 4,
    architecture: "Intel",
    availableModelStorageBytes: 10_000_000_000
)
// Both land on Small, including the 8 GB machine that used to be sent to Tiny.
// Tiny multilingual is not a lighter option, it is a broken one — 64.5% word
// error rate against Small's 35.5% — and recommending a model that cannot do
// the job is worse than recommending one that is merely slow.
guard ModelRecommendationEngine.recommendedModelID(
    for: intelProfile
) == "whisper-small-multilingual",
ModelRecommendationEngine.recommendedModelID(
    for: smallIntelProfile
) == "whisper-small-multilingual",
ModelRecommendationEngine.recommendedModelID(
    for: intelProfile,
    language: spanishProfile
) == "whisper-small-multilingual",
!intelProfile.hasGPUAcceleratedTranscription,
twentyFourGigabyteProfile.hasGPUAcceleratedTranscription else {
    FileHandle.standardError.write(
        Data("FAIL: non-Metal model recommendation is incorrect\n".utf8)
    )
    exit(1)
}

// Speech detection has to work relative to the room, not against a fixed level.
// A quiet microphone puts ordinary speech below the old absolute threshold, and
// the symptom was silent: live preview simply never appeared.
var quietRoom = SpeechActivityDetector()
for _ in 0..<200 {
    // Room tone at -62 dBFS, well below the old -38 dBFS cutoff.
    _ = quietRoom.isSpeech(averageDecibels: -62, peakDecibels: -55)
}
guard quietRoom.noiseFloor < -55,
      // Speech 17 dB above that floor must register even though it would have
      // failed the old fixed threshold outright.
      quietRoom.isSpeech(averageDecibels: -45, peakDecibels: -35),
      // Room tone itself must not.
      !quietRoom.isSpeech(averageDecibels: -61, peakDecibels: -54) else {
    FileHandle.standardError.write(
        Data("FAIL: quiet-room speech detection is incorrect\n".utf8)
    )
    exit(1)
}

// The floor must not run away upward in a loud room, or nothing registers.
var loudRoom = SpeechActivityDetector()
for _ in 0..<500 {
    _ = loudRoom.isSpeech(averageDecibels: -20, peakDecibels: -10)
}
guard loudRoom.noiseFloor <= NoiseFloorEstimator.maximumFloorDecibels,
      loudRoom.isSpeech(averageDecibels: -5, peakDecibels: 0) else {
    FileHandle.standardError.write(
        Data("FAIL: loud-room speech detection is incorrect\n".utf8)
    )
    exit(1)
}

// Beam search is worth its extra decode time on the small, uncertain models and
// measured as pure cost on the large ones, so the gate must fall between Base
// and Small.
guard WhisperDecoding.usesBeamSearch(modelFileSizeBytes: 77_704_715),
WhisperDecoding.usesBeamSearch(modelFileSizeBytes: 147_964_211),
!WhisperDecoding.usesBeamSearch(modelFileSizeBytes: 487_614_201),
!WhisperDecoding.usesBeamSearch(modelFileSizeBytes: 574_041_195),
!WhisperDecoding.usesBeamSearch(modelFileSizeBytes: 1_533_774_781),
!WhisperDecoding.usesBeamSearch(modelFileSizeBytes: 0) else {
    FileHandle.standardError.write(
        Data("FAIL: beam search gating is incorrect\n".utf8)
    )
    exit(1)
}

// English/European Apple Silicon defaults to Parakeet TDT v3, so no Whisper
// model carries the Recommended badge for that profile.
let recommendedCount = VerifiedModelCatalog.models.filter {
    ModelRecommendationEngine.recommendation(
        for: $0,
        profile: twentyFourGigabyteProfile
    ).level == .recommended
}.count
guard recommendedCount == 0 else {
    FileHandle.standardError.write(
        Data(
            "FAIL: \(recommendedCount) models marked recommended, expected 0\n"
                .utf8
        )
    )
    exit(1)
}

let autoDetectProfile = LanguageProfile(
    inputLanguageCode: LanguageProfile.automaticCode,
    outputMode: .spokenLanguage
)
let autoRecommendedCount = VerifiedModelCatalog.models.filter {
    ModelRecommendationEngine.recommendation(
        for: $0,
        profile: twentyFourGigabyteProfile,
        language: autoDetectProfile
    ).level == .recommended
}.count
guard autoRecommendedCount == 1 else {
    FileHandle.standardError.write(
        Data(
            "FAIL: \(autoRecommendedCount) auto-detect models marked recommended, expected 1\n"
                .utf8
        )
    )
    exit(1)
}

let noStorageProfile = HardwareProfile(
    physicalMemoryBytes: 24 * 1_073_741_824,
    logicalCoreCount: 12,
    architecture: "Apple Silicon",
    availableModelStorageBytes: 1
)
guard ModelRecommendationEngine.recommendation(
    for: verifiedModels[4],
    profile: noStorageProfile
).level == .insufficientStorage else {
    FileHandle.standardError.write(
        Data("FAIL: model recommendation ignored storage headroom\n".utf8)
    )
    exit(1)
}

let benchmarkSuite = "ZenVoiceBenchmarks.\(UUID().uuidString)"
guard let benchmarkDefaults = UserDefaults(suiteName: benchmarkSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create benchmark preference fixture\n".utf8)
    )
    exit(1)
}
defer {
    benchmarkDefaults.removePersistentDomain(forName: benchmarkSuite)
}
ModelBenchmarkStore.record(
    modelID: verifiedModels[0].id,
    audioDurationSeconds: 10,
    processingDurationSeconds: 2,
    defaults: benchmarkDefaults
)
ModelBenchmarkStore.record(
    modelID: verifiedModels[0].id,
    audioDurationSeconds: 20,
    processingDurationSeconds: 6,
    defaults: benchmarkDefaults
)
guard let benchmark = ModelBenchmarkStore.summary(
    for: verifiedModels[0].id,
    defaults: benchmarkDefaults
),
benchmark.sampleCount == 2,
abs(benchmark.averageRealtimeFactor - (8.0 / 30.0)) < 0.0001,
benchmark.averageProcessingDurationSeconds == 4 else {
    FileHandle.standardError.write(
        Data("FAIL: local model benchmark summary is incorrect\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: hardware recommendations and benchmarks passed")

let shareSummary = ShareCardSummary(
    totalWordCount: 12_345,
    weightedWordsPerMinute: 154,
    currentStreakDays: 7,
    distinctApplicationCount: 9
)
guard shareSummary.totalWordCount == 12_345,
      shareSummary.weightedWordsPerMinute == 154,
      shareSummary.currentStreakDays == 7,
      shareSummary.distinctApplicationCount == 9,
      ShareCardSummary(
        totalWordCount: -1,
        weightedWordsPerMinute: -1,
        currentStreakDays: -1,
        distinctApplicationCount: -1
      ) == ShareCardSummary(
        totalWordCount: 0,
        weightedWordsPerMinute: 0,
        currentStreakDays: 0,
        distinctApplicationCount: 0
      ) else {
    FileHandle.standardError.write(
        Data("FAIL: privacy-safe share summary is incorrect\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: privacy-safe share summary passed")

let supportedLanguages = LanguageCatalog.languages
guard supportedLanguages.count >= 50,
      Set(supportedLanguages.map(\.code)).count
        == supportedLanguages.count,
      supportedLanguages.first == LanguageCatalog.language(code: "en"),
      LanguageCatalog.language(code: "es")?.displayName == "Spanish",
      LanguageCatalog.language(code: "fr")?.displayName == "French",
      LanguageCatalog.language(code: "zh")?.displayName
        == "Mandarin Chinese",
      LanguageCatalog.language(code: "hi")?.supportLevel
        == .recommended else {
    FileHandle.standardError.write(
        Data("FAIL: supported language catalogue is invalid\n".utf8)
    )
    exit(1)
}

let languageSuite = "ZenVoiceLanguages.\(UUID().uuidString)"
guard let languageDefaults = UserDefaults(suiteName: languageSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create language preference fixture\n".utf8)
    )
    exit(1)
}
defer {
    languageDefaults.removePersistentDomain(forName: languageSuite)
}
guard LanguagePreferences.load(defaults: languageDefaults) == .english else {
    FileHandle.standardError.write(
        Data("FAIL: language profile did not default to English\n".utf8)
    )
    exit(1)
}
LanguagePreferences.save(.hinglish, defaults: languageDefaults)
guard LanguagePreferences.load(defaults: languageDefaults) == .hinglish,
      LanguageProfile.english.isCompatible(with: .english),
      !LanguageProfile.hinglish.isCompatible(with: .english),
      // A general multilingual model is no longer offered for Hinglish. It
      // used to be, on the theory that it worked badly rather than not at
      // all; measured on 30 real code-switched recordings it preserves 0 of
      // 31 English words against the specialist's 82 of 96.
      !LanguageProfile.hinglish.isCompatible(with: .multilingual),
      // A Hinglish model is a specialist. It serves the Hinglish profile and
      // nothing else — measured at 20.9% word error rate on English dictation
      // against Whisper Medium's 2.0%, so letting it near another profile
      // would be a tenfold regression.
      LanguageProfile.hinglish.isCompatible(with: .hinglish),
      !LanguageProfile.english.isCompatible(with: .hinglish),
      !LanguageProfile(inputLanguageCode: "fr", outputMode: .spokenLanguage)
        .isCompatible(with: .hinglish),
      // The language token is part of the contract: Oriserve's model reaches
      // Latin script under `en`, and asking it for `hi` undoes the feature.
      LanguageProfile.hinglish.whisperLanguageArgument(for: .hinglish) == "en",
      LanguageProfile.hinglish.whisperLanguageArgument(for: .multilingual)
        == "hi",
      LanguageProfile.historyRetryProfile(
          languageCode: "hi",
          modelID: "hindi2hinglish-apex"
      ) == .hinglish,
      LanguageProfile.historyRetryProfile(
          languageCode: "hi",
          modelID: "whisper-large-v3-turbo"
      ) == LanguageProfile(
          inputLanguageCode: "hi",
          outputMode: .spokenLanguage
      ) else {
    FileHandle.standardError.write(
        Data("FAIL: language profile persistence or compatibility failed\n".utf8)
    )
    exit(1)
}

let englishConfiguration = ZenVoiceConfiguration(
    modelURL: URL(fileURLWithPath: "/tmp/ggml-base.en.bin")
)
let translatedSpanish = LanguageProfile(
    inputLanguageCode: "es",
    outputMode: .englishTranslation
)
let translationConfiguration = ZenVoiceConfiguration(
    modelURL: URL(fileURLWithPath: "/tmp/ggml-base.bin"),
    languageProfile: translatedSpanish
)
guard englishConfiguration.language == "en",
      !englishConfiguration.shouldTranslateToEnglish,
      translationConfiguration.language == "es",
      translationConfiguration.shouldTranslateToEnglish,
      !translationConfiguration.shouldTransliterateToLatin else {
    FileHandle.standardError.write(
        Data("FAIL: language runtime configuration is incorrect\n".utf8)
    )
    exit(1)
}

let configurationFixtureDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("ZenVoiceConfiguration.\(UUID().uuidString)")
try FileManager.default.createDirectory(
    at: configurationFixtureDirectory,
    withIntermediateDirectories: true
)
defer {
    try? FileManager.default.removeItem(at: configurationFixtureDirectory)
}
let apexFixtureURL = configurationFixtureDirectory
    .appendingPathComponent("ggml-hindi2hinglish-apex-q8_0.bin")
_ = FileManager.default.createFile(
    atPath: apexFixtureURL.path(percentEncoded: false),
    contents: Data()
)
let apexOverrideConfiguration = try? ZenVoiceConfiguration.discover(
    languageProfile: .hinglish,
    environment: ["ZENVOICE_MODEL_PATH": apexFixtureURL.path],
    homeDirectory: configurationFixtureDirectory
)
guard apexOverrideConfiguration?.modelLanguageCapability == .hinglish,
      apexOverrideConfiguration?.language == "en" else {
    FileHandle.standardError.write(
        Data("FAIL: Apex path override lost its Hinglish capability\n".utf8)
    )
    exit(1)
}

let romanized = LocalTransliterator.latinScript(
    "नमस्ते दुनिया, build the API"
)
guard romanized == "namaste duniya, build the API",
      LocalTransliterator.latinScript("Keep SwiftUI as-is.")
        == "Keep SwiftUI as-is.",
      LocalTransliterator.latinScript("¿Qué página?")
        == "¿Qué página?" else {
    FileHandle.standardError.write(
        Data("FAIL: local transliteration changed the wrong text\n".utf8)
    )
    exit(1)
}

print(
    "ZenVoiceCoreChecks: \(supportedLanguages.count) language profiles passed"
)

let microphoneSuite = "ZenVoiceMicrophone.\(UUID().uuidString)"
guard let microphoneDefaults = UserDefaults(suiteName: microphoneSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create microphone preference fixture\n".utf8)
    )
    exit(1)
}
defer {
    microphoneDefaults.removePersistentDomain(forName: microphoneSuite)
}
guard MicrophonePreferences.selectedDeviceUID(
    defaults: microphoneDefaults
) == nil else {
    FileHandle.standardError.write(
        Data("FAIL: microphone preference did not default to macOS\n".utf8)
    )
    exit(1)
}
MicrophonePreferences.save(
    deviceUID: "test-microphone",
    defaults: microphoneDefaults
)
guard MicrophonePreferences.selectedDeviceUID(
    defaults: microphoneDefaults
) == "test-microphone" else {
    FileHandle.standardError.write(
        Data("FAIL: selected microphone did not persist\n".utf8)
    )
    exit(1)
}
MicrophonePreferences.save(deviceUID: nil, defaults: microphoneDefaults)
guard MicrophonePreferences.selectedDeviceUID(
    defaults: microphoneDefaults
) == nil else {
    FileHandle.standardError.write(
        Data("FAIL: system-default microphone did not restore\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: microphone preferences passed")

let liveSuite = "ZenVoiceLive.\(UUID().uuidString)"
guard let liveDefaults = UserDefaults(suiteName: liveSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create live dictation fixture\n".utf8)
    )
    exit(1)
}
defer {
    liveDefaults.removePersistentDomain(forName: liveSuite)
}
// Preview is opt-in. Measured on whisper-large-v3-turbo, decoding the same
// twelve clips as pause-delimited fragments took 28.39s against 11.13s for the
// whole recording — 2.55x the work — and scored worse doing it (3.4% against
// 3.0% word error rate). A default that costs more to be less accurate is not a
// default, so the absent key must read as off.
guard !LiveDictationPreferences.isPreviewEnabled(
    defaults: liveDefaults
),
!LiveDictationPreferences.isCommitOnPauseEnabled(
    defaults: liveDefaults
),
StableTranscriptComposer.appending(
    "  build the page ",
    to: "Please"
) == "Please build the page" else {
    FileHandle.standardError.write(
        Data("FAIL: live dictation defaults are invalid\n".utf8)
    )
    exit(1)
}
guard StablePauseDetector.isStable(
    segmentStart: 0,
    totalSamples: 32_000,
    lastSpeechSample: 16_000
),
!StablePauseDetector.isStable(
    segmentStart: 0,
    totalSamples: 20_000,
    lastSpeechSample: 16_000
),
!StablePauseDetector.isStable(
    segmentStart: 0,
    totalSamples: 13_000,
    lastSpeechSample: 4_000
) else {
    FileHandle.standardError.write(
        Data("FAIL: stable pause thresholds are incorrect\n".utf8)
    )
    exit(1)
}

// The encoder window stays at the model default. Scaling it to the audio was
// measured at 41% faster and 8x worse; see ``WhisperDecoding`` for the numbers.
guard WhisperDecoding.audioContextIsModelDefault else {
    FileHandle.standardError.write(
        Data("FAIL: encoder window must stay at the model default\n".utf8)
    )
    exit(1)
}

// A finished dictation must be decoded from the whole recording. Preview
// fragments are only allowed to stand in when some of them have already been
// inserted into the target app, because at that point the text on screen is a
// fact that has to be reconciled rather than replaced.
guard DictationCompletionStrategy.resolve(
    usesLivePreview: false,
    hasInsertedPreviewText: false
) == .wholeRecording,
DictationCompletionStrategy.resolve(
    usesLivePreview: true,
    hasInsertedPreviewText: false
) == .wholeRecording,
DictationCompletionStrategy.resolve(
    usesLivePreview: true,
    hasInsertedPreviewText: true
) == .segments,
DictationCompletionStrategy.resolve(
    usesLivePreview: false,
    hasInsertedPreviewText: true
) == .wholeRecording else {
    FileHandle.standardError.write(
        Data("FAIL: dictation completion strategy is incorrect\n".utf8)
    )
    exit(1)
}
LiveDictationPreferences.setCommitOnPauseEnabled(
    true,
    defaults: liveDefaults
)
guard LiveDictationPreferences.isPreviewEnabled(
    defaults: liveDefaults
),
LiveDictationPreferences.isCommitOnPauseEnabled(
    defaults: liveDefaults
) else {
    FileHandle.standardError.write(
        Data("FAIL: commit-on-pause did not enable preview\n".utf8)
    )
    exit(1)
}
LiveDictationPreferences.setPreviewEnabled(
    false,
    defaults: liveDefaults
)
guard !LiveDictationPreferences.isPreviewEnabled(
    defaults: liveDefaults
),
!LiveDictationPreferences.isCommitOnPauseEnabled(
    defaults: liveDefaults
) else {
    FileHandle.standardError.write(
        Data("FAIL: disabling preview did not disable streaming\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: live dictation preferences passed")

let zenBarSuite = "ZenVoiceZenBar.\(UUID().uuidString)"
guard let zenBarDefaults = UserDefaults(suiteName: zenBarSuite) else {
    FileHandle.standardError.write(
        Data("FAIL: could not create ZenVoice bar preference fixture\n".utf8)
    )
    exit(1)
}
defer {
    zenBarDefaults.removePersistentDomain(forName: zenBarSuite)
}
guard ZenBarPreferences.showsAtAllTimes(defaults: zenBarDefaults) else {
    FileHandle.standardError.write(
        Data("FAIL: ZenVoice bar did not default to always visible\n".utf8)
    )
    exit(1)
}
ZenBarPreferences.setShowsAtAllTimes(false, defaults: zenBarDefaults)
guard !ZenBarPreferences.showsAtAllTimes(defaults: zenBarDefaults) else {
    FileHandle.standardError.write(
        Data("FAIL: ZenVoice bar preference did not persist\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: ZenVoice bar preference passed")

// Secure input is usually active because a password field has focus. The
// fallback may write only to a positively identified non-secure text control;
// ambiguous text fields fail closed instead of risking a password insertion.
guard !TextInserter.allowsAccessibilityInsertion(
          role: kAXTextFieldRole as String,
          subrole: kAXSecureTextFieldSubrole as String
      ),
      !TextInserter.allowsAccessibilityInsertion(
          role: kAXTextFieldRole as String,
          subrole: nil
      ),
      TextInserter.allowsAccessibilityInsertion(
          role: kAXTextFieldRole as String,
          subrole: "AXSearchField"
      ),
      TextInserter.allowsAccessibilityInsertion(
          role: kAXTextAreaRole as String,
          subrole: nil
      ),
      !TextInserter.allowsAccessibilityInsertion(
          role: kAXButtonRole as String,
          subrole: nil
      ),
      // A combo box wraps a text field, so an unidentified one is as ambiguous
      // as a bare text field and must fail closed the same way.
      !TextInserter.allowsAccessibilityInsertion(
          role: kAXComboBoxRole as String,
          subrole: nil
      ),
      !TextInserter.allowsAccessibilityInsertion(
          role: kAXComboBoxRole as String,
          subrole: kAXSecureTextFieldSubrole as String
      ),
      TextInserter.allowsAccessibilityInsertion(
          role: kAXComboBoxRole as String,
          subrole: "AXSearchField"
      ) else {
    FileHandle.standardError.write(
        Data("FAIL: secure-input accessibility policy is unsafe\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: secure-input insertion policy passed")

// Runaway repetition — Whisper's failure on audio it cannot handle. Measured:
// one clip made Whisper Tiny emit "We are in India," about a hundred times.
let runaway = TranscriptRepetition.collapsingRunaway(
    "We are in India, India, India, India, India, India, India."
)
guard runaway == "We are in India," else {
    FileHandle.standardError.write(
        Data("FAIL: runaway repetition was not collapsed: \(runaway)\n".utf8)
    )
    exit(1)
}

// A repeated phrase, not just a repeated word.
let phraseLoop = TranscriptRepetition.collapsingRunaway(
    "Open the file open the file open the file open the file and save it"
)
guard phraseLoop == "Open the file and save it" else {
    FileHandle.standardError.write(
        Data("FAIL: phrase loop was not collapsed: \(phraseLoop)\n".utf8)
    )
    exit(1)
}

// Ordinary speech must survive. Three repeats is emphasis; the threshold is
// four, so this is left exactly as spoken.
let emphasis = TranscriptRepetition.collapsingRunaway(
    "It was very very good and I said no no no"
)
guard emphasis == "It was very very good and I said no no no" else {
    FileHandle.standardError.write(
        Data("FAIL: ordinary emphasis was collapsed: \(emphasis)\n".utf8)
    )
    exit(1)
}

// The collapse reports what it cut, and the distrust floor separates a
// decoder that looped from a speaker repeating themselves: a fourfold "no"
// cuts three words and stays trusted, a twenty-fold loop does not.
let reported = TranscriptRepetition.collapsingRunawayReporting(
    "We are in India, India, India, India, India, India, India."
)
guard reported.text == "We are in India,", reported.wordsCut == 6 else {
    FileHandle.standardError.write(
        Data("FAIL: collapse cut count is wrong: \(reported.wordsCut)\n".utf8)
    )
    exit(1)
}
let loopCut = TranscriptRepetition.collapsingRunawayReporting(
    Array(repeating: "we are in India", count: 20).joined(separator: " ")
).wordsCut
let emphasisCut = TranscriptRepetition.collapsingRunawayReporting(
    "I said no no no no"
).wordsCut
guard loopCut >= TranscriptRepetition.wordsCutBeforeDistrust,
      emphasisCut < TranscriptRepetition.wordsCutBeforeDistrust else {
    FileHandle.standardError.write(
        Data("FAIL: distrust floor misclassifies \(loopCut)/\(emphasisCut)\n"
            .utf8)
    )
    exit(1)
}

// The cut count travels on the result and defaults to a trusted zero.
guard TranscriptionResult(
    rawTranscript: "x",
    finalTranscript: "x",
    correctionCount: 0
).runawayWordsCut == 0 else {
    FileHandle.standardError.write(
        Data("FAIL: runawayWordsCut default is not zero\n".utf8)
    )
    exit(1)
}

// The decode deadline scales with the recording but never drops below its
// floor, so a two-second utterance still has room for model load.
guard WhisperDecoding.decodeDeadline(audioSeconds: 2) == 15,
      WhisperDecoding.decodeDeadline(audioSeconds: 60) == 120 else {
    FileHandle.standardError.write(
        Data("FAIL: decode deadline is wrong\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: runaway repetition defence passed")

// MARK: - Engine registry checks

struct FakeSpeechEngine: SpeechEngine {
    let descriptor: EngineDescriptor
    let languageCapability: ModelLanguageCapability
    let isAvailable: Bool

    func prepare() async throws {}

    func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        TranscriptionResult(
            rawTranscript: "",
            finalTranscript: "",
            correctionCount: 0,
            modelID: descriptor.id
        )
    }
}

struct CancellingSpeechEngine: SpeechEngine {
    let descriptor: EngineDescriptor
    let languageCapability: ModelLanguageCapability = .multilingual
    let isAvailable = true

    func prepare() async throws {
        throw CancellationError()
    }

    func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        throw CancellationError()
    }
}

private enum ExpectedEngineFailure: Error {
    case failed
}

struct FailingSpeechEngine: SpeechEngine {
    let descriptor: EngineDescriptor
    let languageCapability: ModelLanguageCapability = .multilingual
    let isAvailable = true

    func prepare() async throws {
        throw ExpectedEngineFailure.failed
    }

    func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        throw ExpectedEngineFailure.failed
    }
}

func fakeEngineDescriptor(
    id: String,
    capability: ModelLanguageCapability,
    supportedLanguages: [SupportedLanguage] = [],
    available: Bool = true
) -> EngineDescriptor {
    EngineDescriptor(
        id: id,
        displayName: id,
        family: .whisper,
        supportedLanguages: supportedLanguages,
        requiresDownload: false,
        requiresInternet: false,
        format: "fake",
        publisher: "checks",
        license: "MIT",
        licenseURL: "",
        attribution: "",
        privacyNote: ""
    )
}

func fakeEngine(
    id: String,
    capability: ModelLanguageCapability,
    supportedLanguages: [SupportedLanguage] = [],
    available: Bool = true
) -> FakeSpeechEngine {
    FakeSpeechEngine(
        descriptor: fakeEngineDescriptor(
            id: id,
            capability: capability,
            supportedLanguages: supportedLanguages,
            available: available
        ),
        languageCapability: capability,
        isAvailable: available
    )
}

func failEngineCheck(_ message: String) -> Never {
    FileHandle.standardError.write(
        Data("FAIL: \(message)\n".utf8)
    )
    exit(1)
}

let englishProfile = LanguageProfile.english
let hinglishProfile = LanguageProfile.hinglish
let autoProfile = LanguageProfile(
    inputLanguageCode: LanguageProfile.automaticCode,
    outputMode: .spokenLanguage
)
guard let englishLanguage = LanguageCatalog.language(code: "en"),
      let hindiLanguage = LanguageCatalog.language(code: "hi") else {
    failEngineCheck("missing test languages")
}

let englishOnlyEngine = fakeEngine(
    id: "english-only",
    capability: .english,
    supportedLanguages: [englishLanguage]
)
let multilingualEngine = fakeEngine(
    id: "multilingual",
    capability: .multilingual
)
let hindiOnlyEngine = fakeEngine(
    id: "hindi-only",
    capability: .multilingual,
    supportedLanguages: [hindiLanguage]
)
let unavailableEngine = fakeEngine(
    id: "unavailable-multilingual",
    capability: .multilingual,
    available: false
)
let engineRegistry = EngineRegistry(
    engines: [englishOnlyEngine, hindiOnlyEngine, multilingualEngine, unavailableEngine],
    fallbackOrder: [englishOnlyEngine.descriptor.id, hindiOnlyEngine.descriptor.id, multilingualEngine.descriptor.id]
)

// Saved preference is honored when it is compatible with the profile.
guard engineRegistry.resolve(
    for: englishProfile,
    selectedID: englishOnlyEngine.descriptor.id
)?.descriptor.id == englishOnlyEngine.descriptor.id else {
    failEngineCheck("preferred compatible engine was not selected")
}

// Saved preference is ignored when it is incompatible; fallback wins.
guard engineRegistry.resolve(
    for: englishProfile,
    selectedID: hindiOnlyEngine.descriptor.id
)?.descriptor.id == englishOnlyEngine.descriptor.id else {
    failEngineCheck("incompatible preferred engine did not fall back")
}

// Automatic language profile resolves to the first engine that supports English.
guard engineRegistry.resolve(
    for: autoProfile,
    selectedID: nil
)?.descriptor.id == englishOnlyEngine.descriptor.id else {
    failEngineCheck("automatic profile did not resolve to English-capable engine")
}

// A built-in engine whose supportedLanguages includes English is available for
// English and unavailable for Hinglish, matching the Apple Speech mapping rule.
let englishAvailability = engineRegistry.availability(for: englishProfile)
guard let englishOnlyAvailability = englishAvailability.first(
    where: { $0.engine.id == englishOnlyEngine.descriptor.id }
), englishOnlyAvailability.isAvailable else {
    failEngineCheck("English-only engine should be available for English")
}
let hinglishAvailability = engineRegistry.availability(for: hinglishProfile)
guard let englishOnlyHinglishAvailability = hinglishAvailability.first(
    where: { $0.engine.id == englishOnlyEngine.descriptor.id }
), !englishOnlyHinglishAvailability.isAvailable,
      case .unsupportedLanguage? = englishOnlyHinglishAvailability.reason else {
    failEngineCheck("English-only engine should be unavailable for Hinglish")
}

// Fallback ordering is respected even when other engines are available later.
let firstChoice = fakeEngine(
    id: "first-choice",
    capability: .multilingual,
    available: false
)
let secondChoice = fakeEngine(
    id: "second-choice",
    capability: .multilingual,
    available: true
)
let thirdChoice = fakeEngine(
    id: "third-choice",
    capability: .multilingual,
    available: true
)
let fallbackRegistry = EngineRegistry(
    engines: [firstChoice, secondChoice, thirdChoice],
    fallbackOrder: [firstChoice.descriptor.id, secondChoice.descriptor.id]
)
guard fallbackRegistry.resolve(
    for: englishProfile,
    selectedID: nil
)?.descriptor.id == secondChoice.descriptor.id else {
    failEngineCheck("fallback ordering did not skip unavailable first choice")
}

let failingPreferred = FailingSpeechEngine(
    descriptor: fakeEngineDescriptor(
        id: "failing-preferred",
        capability: .multilingual
    )
)
let workingFallback = fakeEngine(
    id: "working-fallback",
    capability: .multilingual
)
let failureFallbackRegistry = EngineRegistry(
    engines: [failingPreferred, workingFallback],
    fallbackOrder: [workingFallback.descriptor.id]
)
do {
    try await failureFallbackRegistry.prepare(
        for: englishProfile,
        selectedID: failingPreferred.descriptor.id
    )
} catch {
    failEngineCheck("engine preparation did not use its working fallback")
}
do {
    let result = try await failureFallbackRegistry.transcribe(
        audioURL: URL(fileURLWithPath: "/tmp/fallback.wav"),
        profile: englishProfile,
        selectedID: failingPreferred.descriptor.id
    )
    guard result.modelID == workingFallback.descriptor.id else {
        failEngineCheck("transcription returned the wrong fallback engine")
    }
} catch {
    failEngineCheck("transcription did not use its working fallback: \(error)")
}
let failingFallback = FailingSpeechEngine(
    descriptor: fakeEngineDescriptor(
        id: "failing-fallback",
        capability: .multilingual
    )
)
let allFailRegistry = EngineRegistry(
    engines: [failingPreferred, failingFallback],
    fallbackOrder: [failingFallback.descriptor.id]
)
do {
    _ = try await allFailRegistry.transcribe(
        audioURL: URL(fileURLWithPath: "/tmp/all-fail.wav"),
        profile: englishProfile,
        selectedID: failingPreferred.descriptor.id
    )
    failEngineCheck("an all-failed engine chain unexpectedly succeeded")
} catch EngineError.transcriptionFailed(let id, _) {
    guard id == failingFallback.descriptor.id else {
        failEngineCheck("all-failed chain reported the wrong final engine")
    }
} catch {
    failEngineCheck("all-failed chain returned the wrong error: \(error)")
}

// User cancellation is lifecycle control, not an engine failure. Keeping the
// concrete cancellation prevents an intentional stop from being presented as
// a failed decode or retained as recovery audio.
let cancellingEngine = CancellingSpeechEngine(
    descriptor: fakeEngineDescriptor(
        id: "cancelling",
        capability: .multilingual
    )
)
let cancellingRegistry = EngineRegistry(engines: [cancellingEngine])
do {
    try await cancellingRegistry.prepare(
        for: englishProfile,
        selectedID: cancellingEngine.descriptor.id
    )
    failEngineCheck("cancelled engine preparation unexpectedly succeeded")
} catch is CancellationError {
    // Expected.
} catch {
    failEngineCheck("engine preparation hid CancellationError: \(error)")
}
do {
    _ = try await cancellingRegistry.transcribe(
        audioURL: URL(fileURLWithPath: "/tmp/cancelled.wav"),
        profile: englishProfile,
        selectedID: cancellingEngine.descriptor.id
    )
    failEngineCheck("cancelled transcription unexpectedly succeeded")
} catch is CancellationError {
    // Expected.
} catch {
    failEngineCheck("transcription hid CancellationError: \(error)")
}
let cancellationMustNotFallback = EngineRegistry(
    engines: [cancellingEngine, workingFallback],
    fallbackOrder: [workingFallback.descriptor.id]
)
do {
    _ = try await cancellationMustNotFallback.transcribe(
        audioURL: URL(fileURLWithPath: "/tmp/cancelled-before-fallback.wav"),
        profile: englishProfile,
        selectedID: cancellingEngine.descriptor.id
    )
    failEngineCheck("user cancellation incorrectly ran a fallback engine")
} catch is CancellationError {
    // Expected.
} catch {
    failEngineCheck("fallback path hid CancellationError: \(error)")
}

let migrationSuite = "ZenVoiceCoreChecks.engine-migration.\(UUID().uuidString)"
guard let migrationDefaults = UserDefaults(suiteName: migrationSuite),
      let migrationModel = VerifiedModelCatalog.models.first else {
    failEngineCheck("could not create engine-migration fixtures")
}
defer {
    migrationDefaults.removePersistentDomain(forName: migrationSuite)
}
ModelSelectionPreferences.save(migrationModel, defaults: migrationDefaults)
guard SelectedEnginePreferences.migrateLegacyWhisperSelectionIfNeeded(
    for: englishProfile,
    defaults: migrationDefaults
), SelectedEnginePreferences.load(
    for: englishProfile,
    defaults: migrationDefaults
) == EngineIdentifiers.whisper else {
    failEngineCheck("legacy Whisper selection was not migrated")
}
SelectedEnginePreferences.save(
    EngineIdentifiers.appleSpeech,
    for: englishProfile,
    defaults: migrationDefaults
)
guard !SelectedEnginePreferences.migrateLegacyWhisperSelectionIfNeeded(
    for: englishProfile,
    defaults: migrationDefaults
), SelectedEnginePreferences.load(
    for: englishProfile,
    defaults: migrationDefaults
) == EngineIdentifiers.appleSpeech else {
    failEngineCheck("engine migration overwrote an explicit preference")
}

print("ZenVoiceCoreChecks: engine registry passed")

// MARK: - Engine recommendation checks

private func fakeEngineWithID(
    id: String,
    capability: ModelLanguageCapability,
    available: Bool = true
) -> FakeSpeechEngine {
    FakeSpeechEngine(
        descriptor: fakeEngineDescriptor(
            id: id,
            capability: capability,
            available: available
        ),
        languageCapability: capability,
        isAvailable: available
    )
}

let fakeWhisper = fakeEngineWithID(
    id: EngineIdentifiers.whisper,
    capability: .multilingual
)
let fakeHinglishWhisper = fakeEngineWithID(
    id: EngineIdentifiers.whisper,
    capability: .hinglish
)
let fakeAppleSpeech = fakeEngineWithID(
    id: EngineIdentifiers.appleSpeech,
    capability: .multilingual
)
let recommendationRegistry = EngineRegistry(
    engines: [fakeWhisper, fakeAppleSpeech]
)

let englishRec = EngineRecommendationEngine.recommendation(
    for: .english,
    hardware: HardwareProfile.current(),
    registry: recommendationRegistry
)
guard let englishRec,
      englishRec.preferredEngineID == EngineIdentifiers.appleSpeech,
      englishRec.fallbackEngineIDs == [EngineIdentifiers.whisper] else {
    failEngineCheck("English recommendation should prefer Apple Speech then Whisper")
}

let hinglishRegistry = EngineRegistry(
    engines: [fakeHinglishWhisper, fakeAppleSpeech]
)
let hinglishRec = EngineRecommendationEngine.recommendation(
    for: .hinglish,
    hardware: HardwareProfile.current(),
    registry: hinglishRegistry
)
guard let hinglishRec,
      hinglishRec.preferredEngineID == EngineIdentifiers.whisper,
      hinglishRec.fallbackEngineIDs.isEmpty else {
    failEngineCheck("Hinglish recommendation should be Whisper only")
}

let unavailableApple = fakeEngineWithID(
    id: EngineIdentifiers.appleSpeech,
    capability: .multilingual,
    available: false
)
let noAppleRegistry = EngineRegistry(
    engines: [fakeWhisper, unavailableApple]
)
let noAppleRec = EngineRecommendationEngine.recommendation(
    for: .english,
    hardware: HardwareProfile.current(),
    registry: noAppleRegistry
)
guard let noAppleRec,
      noAppleRec.preferredEngineID == EngineIdentifiers.whisper else {
    failEngineCheck("Unavailable Apple Speech should fall back to Whisper")
}

let fakeTDTv3 = fakeEngineWithID(
    id: EngineIdentifiers.parakeetTDTv3,
    capability: .multilingual
)
let tdtRegistry = EngineRegistry(
    engines: [fakeWhisper, fakeAppleSpeech, fakeTDTv3]
)
let tdtEnglishRec = EngineRecommendationEngine.recommendation(
    for: .english,
    hardware: HardwareProfile.current(),
    registry: tdtRegistry
)
guard let tdtEnglishRec,
      tdtEnglishRec.preferredEngineID == EngineIdentifiers.parakeetTDTv3,
      tdtEnglishRec.fallbackEngineIDs
        == [EngineIdentifiers.appleSpeech, EngineIdentifiers.whisper] else {
    failEngineCheck("English with TDT v3 installed should prefer TDT v3")
}

let intelEngineRec = EngineRecommendationEngine.recommendation(
    for: .english,
    hardware: intelProfile,
    registry: tdtRegistry
)
guard let intelEngineRec,
      intelEngineRec.preferredEngineID == EngineIdentifiers.whisper else {
    failEngineCheck("Intel should prefer Whisper Small, not TDT v3")
}

let autoEngineRec = EngineRecommendationEngine.recommendation(
    for: autoDetectProfile,
    hardware: HardwareProfile.current(),
    registry: tdtRegistry
)
guard let autoEngineRec,
      autoEngineRec.preferredEngineID == EngineIdentifiers.whisper else {
    failEngineCheck("Auto-detect should prefer Whisper Turbo")
}

let fakeFlash = fakeEngineWithID(
    id: EngineIdentifiers.parakeetFlash,
    capability: .english
)
let previewRegistry = EngineRegistry(
    engines: [fakeWhisper, fakeFlash, fakeTDTv3],
    fallbackOrder: [
        EngineIdentifiers.parakeetTDTv3,
        EngineIdentifiers.whisper
    ]
)
guard previewRegistry.resolve(
        for: .english,
        selectedID: EngineIdentifiers.parakeetFlash
      )?.descriptor.id == EngineIdentifiers.parakeetTDTv3 else {
    failEngineCheck("Flash must not win final resolve")
}
guard previewRegistry.resolvePreview(for: .english)?.descriptor.id
        == EngineIdentifiers.parakeetFlash else {
    failEngineCheck("Flash should win live preview resolve")
}

let wrappedModels: [(String, String)] = [
    (EngineIdentifiers.parakeetTDTv2, "nvidia/parakeet-tdt-0.6b-v2"),
    (EngineIdentifiers.parakeetTDTv3, "nvidia/parakeet-tdt-0.6b-v3"),
    (
        EngineIdentifiers.parakeetFlash,
        "nvidia/parakeet_realtime_eou_120m-v1"
    ),
    (
        EngineIdentifiers.nemotronSpeechUltraFast,
        "nvidia/nemotron-3.5-asr-streaming-0.6b"
    ),
    (
        EngineIdentifiers.nemotronSpeechMultilingual,
        "nvidia/nemotron-3.5-asr-streaming-0.6b"
    )
]
for (engineID, expected) in wrappedModels {
    guard VerifiedEngineCatalog.engine(id: engineID)?.wrappedModelID
            == expected else {
        failEngineCheck("\(engineID) does not wrap \(expected)")
    }
}
guard VerifiedEngineCatalog.engine(
        id: EngineIdentifiers.appleSpeech
      )?.wrappedModelID == nil else {
    failEngineCheck("Apple Speech should not wrap a downloadable model")
}


print("ZenVoiceCoreChecks: engine recommendation passed")

// MARK: - Command mode checks

let commandModeEngine = CommandModeEngine()
let commandManifest = CommandModeEngine.defaultManifest

guard commandModeEngine.parse(
    transcript: "open safari",
    manifest: commandManifest
) == .launchApp(bundleID: "com.apple.Safari") else {
    failEngineCheck("'open safari' did not parse to launch Safari")
}

guard commandModeEngine.parse(
    transcript: "please open safari now",
    manifest: commandManifest
) == .launchApp(bundleID: "com.apple.Safari") else {
    failEngineCheck("'please open safari now' did not parse")
}

guard commandModeEngine.parse(
    transcript: "copy last transcript",
    manifest: commandManifest
) == .systemAction(.copyLastTranscript) else {
    failEngineCheck("'copy last transcript' did not parse")
}

guard commandModeEngine.parse(
    transcript: "just normal dictation text",
    manifest: commandManifest
) == .none else {
    failEngineCheck("plain dictation was misclassified as a command")
}

guard commandModeEngine.parse(
    transcript: "open safari",
    manifest: nil
) == .none else {
    failEngineCheck("nil manifest should produce no action")
}

guard !CommandModePreferences.isEnabled() else {
    failEngineCheck("command mode should be disabled by default")
}
CommandModePreferences.setEnabled(true)
guard CommandModePreferences.isEnabled() else {
    failEngineCheck("command mode enable state did not persist")
}
CommandModePreferences.saveManifest(commandManifest)
guard let loadedManifest = CommandModePreferences.loadManifest(),
      loadedManifest == commandManifest else {
    failEngineCheck("command manifest did not round-trip through preferences")
}
CommandModePreferences.setEnabled(false)
CommandModePreferences.clearManifest()

print("ZenVoiceCoreChecks: command mode passed")

// MARK: - ZenIntelligence checks

let intelligenceEngine = ZenIntelligenceEngine()

let formatResult = intelligenceEngine.enhance(
    "hello world. this is a test.",
    mode: .format,
    languageCode: "en"
)
guard formatResult.text == "Hello world. This is a test.",
      formatResult.wasRejected == false else {
    failEngineCheck(
        "ZenIntelligence format did not capitalize: \(formatResult.text)"
    )
}

let numberResult = intelligenceEngine.enhance(
    "my pin is five five five five",
    mode: .format,
    languageCode: "en"
)
guard numberResult.text.contains("5"),
      !numberResult.wasRejected else {
    failEngineCheck(
        "ZenIntelligence did not format spoken digits: \(numberResult.text)"
    )
}

let contextResult = intelligenceEngine.enhance(
    "And then it crashed",
    mode: .contextAware,
    languageCode: "en",
    context: "I pressed the button"
)
guard contextResult.text == "and then it crashed",
      !contextResult.wasRejected else {
    failEngineCheck(
        "ZenIntelligence context-aware join failed: \(contextResult.text)"
    )
}

let guardResult = intelligenceEngine.enhance(
    "the quick brown fox",
    mode: .format,
    languageCode: "en"
)
// The deterministic formatter should not change this text, so the meaning
// guard passes without changes.
guard guardResult.text == "the quick brown fox",
      !guardResult.wasRejected else {
    failEngineCheck(
        "ZenIntelligence meaning guard rejected harmless text: \(guardResult.text)"
    )
}

let intelligenceSuite = "ZenVoiceCoreChecks.ZenIntelligence.\(UUID().uuidString)"
guard let intelligenceDefaults = UserDefaults(suiteName: intelligenceSuite) else {
    failEngineCheck("could not create ZenIntelligence preference fixture")
}
defer {
    intelligenceDefaults.removePersistentDomain(forName: intelligenceSuite)
}
guard ZenIntelligencePreferences.load(defaults: intelligenceDefaults) == .off else {
    failEngineCheck("ZenIntelligence should default to off")
}
ZenIntelligencePreferences.save(.contextAware, defaults: intelligenceDefaults)
guard ZenIntelligencePreferences.load(defaults: intelligenceDefaults) == .contextAware else {
    failEngineCheck("ZenIntelligence preference did not persist")
}

print("ZenVoiceCoreChecks: ZenIntelligence passed")

// MARK: - Write Mode checks

let writeEngine = WriteModeEngine()
let composeResult = writeEngine.compose(transcript: "draft email")
guard composeResult.text == "draft email",
      !composeResult.requiresPreview,
      !composeResult.wasRejected else {
    failEngineCheck("Write Mode compose did not pass transcript through")
}

let smallRewrite = writeEngine.rewrite(
    selectedText: "the cat sat",
    prompt: "make it formal",
    mode: .format,
    languageCode: "en"
)
guard !smallRewrite.wasRejected,
      !smallRewrite.requiresPreview else {
    failEngineCheck(
        "small rewrite should not require preview: \(smallRewrite.text)"
    )
}

let largeRewrite = writeEngine.rewrite(
    selectedText: String(repeating: "a", count: 250),
    prompt: "summarize",
    mode: .format,
    languageCode: "en"
)
guard largeRewrite.requiresPreview else {
    failEngineCheck("large rewrite should require preview")
}

let writeSuite = "ZenVoiceCoreChecks.WriteMode.\(UUID().uuidString)"
guard let writeDefaults = UserDefaults(suiteName: writeSuite) else {
    failEngineCheck("could not create Write Mode preference fixture")
}
defer {
    writeDefaults.removePersistentDomain(forName: writeSuite)
}
guard WriteModePreferences.loadSubMode(defaults: writeDefaults) == .compose else {
    failEngineCheck("Write Mode should default to compose")
}
WriteModePreferences.saveSubMode(.rewrite, defaults: writeDefaults)
guard WriteModePreferences.loadSubMode(defaults: writeDefaults) == .rewrite else {
    failEngineCheck("Write Mode sub-mode preference did not persist")
}

print("ZenVoiceCoreChecks: Write Mode passed")

// MARK: - Action serialization checks

let action = CommandAction.launchApp(bundleID: "com.zenvoice.ZenVoice")
let actionData = try! JSONEncoder().encode(action)
let decodedAction = try! JSONDecoder().decode(CommandAction.self, from: actionData)
guard action == decodedAction else {
    failEngineCheck("CommandAction did not round-trip through JSON")
}

print("ZenVoiceCoreChecks: action serialization passed")

// MARK: - Update feed verification checks

// A throwaway signing key stands in for the release key. The app only ever
// verifies; signing lives in release tooling.
let signingKey = Curve25519.Signing.PrivateKey()
let verifier = UpdateVerifier(publicKey: signingKey.publicKey)

let goodManifest = UpdateManifest(
    version: "1.4.0",
    channel: .stable,
    archiveURL: "https://example.com/ZenVoice-1.4.0.zip",
    sha256: String(repeating: "a", count: 64),
    publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
)
let goodFeed = try! SignedUpdateFeed.make(manifest: goodManifest) { payload in
    try signingKey.signature(for: payload)
}

// The happy path is the easy half; the rejections below are the point.
guard let accepted = try? verifier.acceptableUpdate(
    in: goodFeed,
    installedVersion: "1.3.2",
    channel: .stable
), accepted.version == "1.4.0" else {
    failEngineCheck("a valid signed update feed was rejected")
}

func expectUpdateRejection(
    _ label: String,
    _ body: () throws -> UpdateManifest
) {
    do {
        _ = try body()
        failEngineCheck("update verification accepted \(label)")
    } catch {
        // Expected.
    }
}

// Tampered payload: same signature, different bytes.
var tamperedManifest = goodManifest
tamperedManifest = UpdateManifest(
    version: "9.9.9",
    channel: goodManifest.channel,
    archiveURL: goodManifest.archiveURL,
    sha256: goodManifest.sha256,
    publishedAt: goodManifest.publishedAt
)
let tamperedFeed = SignedUpdateFeed(
    manifest: try! tamperedManifest.canonicalPayload().base64EncodedString(),
    signature: goodFeed.signature
)
expectUpdateRejection("a tampered manifest") {
    try verifier.acceptableUpdate(
        in: tamperedFeed,
        installedVersion: "1.3.2",
        channel: .stable
    )
}

// Correct signature, wrong key.
let attackerKey = Curve25519.Signing.PrivateKey()
let attackerFeed = try! SignedUpdateFeed.make(manifest: goodManifest) { payload in
    try attackerKey.signature(for: payload)
}
expectUpdateRejection("a feed signed with an unknown key") {
    try verifier.acceptableUpdate(
        in: attackerFeed,
        installedVersion: "1.3.2",
        channel: .stable
    )
}

expectUpdateRejection("a feed with no signature") {
    try verifier.acceptableUpdate(
        in: SignedUpdateFeed(manifest: goodFeed.manifest, signature: ""),
        installedVersion: "1.3.2",
        channel: .stable
    )
}

// Transport downgrade.
let insecureManifest = UpdateManifest(
    version: "1.4.0",
    channel: .stable,
    archiveURL: "http://example.com/ZenVoice-1.4.0.zip",
    sha256: goodManifest.sha256,
    publishedAt: goodManifest.publishedAt
)
let insecureFeed = try! SignedUpdateFeed.make(manifest: insecureManifest) { payload in
    try signingKey.signature(for: payload)
}
expectUpdateRejection("a validly signed feed pointing at http") {
    try verifier.acceptableUpdate(
        in: insecureFeed,
        installedVersion: "1.3.2",
        channel: .stable
    )
}

// Replayed older feed must not walk the user backwards.
expectUpdateRejection("a downgrade") {
    try verifier.acceptableUpdate(
        in: goodFeed,
        installedVersion: "1.4.0",
        channel: .stable
    )
}
expectUpdateRejection("a same-version reinstall") {
    try verifier.acceptableUpdate(
        in: goodFeed,
        installedVersion: "1.4.0.0",
        channel: .stable
    )
}

// A stable install must never be offered a beta build.
let betaManifest = UpdateManifest(
    version: "1.5.0",
    channel: .beta,
    archiveURL: "https://example.com/ZenVoice-1.5.0-beta.zip",
    sha256: goodManifest.sha256,
    publishedAt: goodManifest.publishedAt
)
let betaFeed = try! SignedUpdateFeed.make(manifest: betaManifest) { payload in
    try signingKey.signature(for: payload)
}
expectUpdateRejection("a beta build on the stable channel") {
    try verifier.acceptableUpdate(
        in: betaFeed,
        installedVersion: "1.3.2",
        channel: .stable
    )
}
guard (try? verifier.acceptableUpdate(
    in: betaFeed,
    installedVersion: "1.3.2",
    channel: .beta
)) != nil else {
    failEngineCheck("a beta install could not receive a signed beta build")
}

// Disabled updates reject even a perfect feed.
expectUpdateRejection("an update while updates are disabled") {
    try verifier.acceptableUpdate(
        in: goodFeed,
        installedVersion: "1.3.2",
        channel: .stable,
        updatesEnabled: false
    )
}

// The archive hash binds the signed feed to the actual bytes.
let archiveBytes = Data("pretend this is ZenVoice.zip".utf8)
let archiveDigest = SHA256.hash(data: archiveBytes)
    .map { String(format: "%02x", $0) }.joined()
let boundManifest = UpdateManifest(
    version: "1.4.0",
    channel: .stable,
    archiveURL: goodManifest.archiveURL,
    sha256: archiveDigest,
    publishedAt: goodManifest.publishedAt
)
do {
    try verifier.verifyArchive(archiveBytes, matches: boundManifest)
} catch {
    failEngineCheck("a matching archive was rejected by its checksum")
}
do {
    try verifier.verifyArchive(
        Data("a different archive".utf8),
        matches: boundManifest
    )
    failEngineCheck("an archive with the wrong checksum was accepted")
} catch {
    // Expected.
}

// Version parsing must refuse anything it cannot compare exactly.
guard AppVersion("1.2.3") != nil, AppVersion("v1.2.3") != nil,
      AppVersion("1.2.3-beta") == nil, AppVersion("") == nil,
      AppVersion("1..3") == nil, AppVersion("latest") == nil else {
    failEngineCheck("AppVersion parsing accepted an uncomparable version")
}
guard AppVersion("1.10.0")! > AppVersion("1.9.9")! else {
    failEngineCheck("AppVersion compared components lexically, not numerically")
}

print("ZenVoiceCoreChecks: update feed verification passed")

// MARK: - Cloud AI enhancement checks

// Off by default, and inert until fully configured.
let defaultCloudConfiguration = CloudAIConfiguration()
guard !defaultCloudConfiguration.isEnabled else {
    failEngineCheck("Cloud AI Enhancement was enabled by default")
}

let cloudEngine = CloudAIEnhancementEngine(
    transport: URLSessionCloudAITransport()
)
do {
    _ = try cloudEngine.makeRequest(
        transcript: "hello there",
        configuration: defaultCloudConfiguration
    )
    failEngineCheck("a request was built while Cloud AI was disabled")
} catch {
    // Expected.
}

var cloudConfiguration = CloudAIConfiguration()
cloudConfiguration.isEnabled = true

// HTTPS is mandatory, including for custom endpoints.
cloudConfiguration.provider = .custom
cloudConfiguration.baseURL = "http://internal.example.com/v1"
cloudConfiguration.model = "local-model"
do {
    _ = try cloudConfiguration.resolvedEndpoint()
    failEngineCheck("a non-HTTPS cloud endpoint was accepted")
} catch {
    // Expected.
}

// Loopback HTTP is allowed so local Ollama can run without TLS.
cloudConfiguration.provider = .ollama
cloudConfiguration.baseURL = "http://127.0.0.1:11434/v1"
cloudConfiguration.model = "llama3.2"
guard let ollamaEndpoint = try? cloudConfiguration.resolvedEndpoint(),
      ollamaEndpoint.absoluteString
        == "http://127.0.0.1:11434/v1/chat/completions" else {
    failEngineCheck("a local Ollama endpoint was rejected")
}
guard CloudAIProvider.ollama.requiresAPIKey == false,
      CloudAIProvider.openRouter.displayName == "OpenRouter",
      CloudAIProvider.ollamaCloud.defaultBaseURL
        == "https://ollama.com/v1" else {
    failEngineCheck("new cloud providers are misconfigured")
}
cloudConfiguration.provider = .custom

cloudConfiguration.baseURL = "https://api.openai.com/v1/"
cloudConfiguration.model = "gpt-4o-mini"
guard let endpoint = try? cloudConfiguration.resolvedEndpoint(),
      endpoint.absoluteString
        == "https://api.openai.com/v1/chat/completions" else {
    failEngineCheck("the chat-completions endpoint was built incorrectly")
}

// The privacy rule from ADR 0011, asserted against the actual bytes: only the
// transcript and prompt may leave. If someone later attaches app identity or
// the next-dictation context to the body, this check fails.
let cloudRequest = try! cloudEngine.makeRequest(
    transcript: "  meeting notes for the design review  ",
    configuration: cloudConfiguration
)
let encodedBody = try! cloudRequest.encodedBody()
let bodyText = String(decoding: encodedBody, as: UTF8.self)
guard bodyText.contains("meeting notes for the design review") else {
    failEngineCheck("the transcript was not present in the request body")
}
let forbiddenInBody = [
    "bundleIdentifier", "bundle_id", "targetApp", "com.apple",
    "deviceID", "device_id", "installID", "install_id",
    "nextDictationContext", "audio", "insights", "voiceProfile"
]
for token in forbiddenInBody where bodyText.contains(token) {
    failEngineCheck("the cloud request body leaked \(token)")
}

var lectureConfiguration = cloudConfiguration
lectureConfiguration.prompt = CloudAIPromptTemplate.lecture.text
let lectureRequest = try! cloudEngine.makeRequest(
    transcript: "Topic one. What does gravity mean?",
    configuration: lectureConfiguration
)
let lectureBody = String(
    decoding: try! lectureRequest.encodedBody(),
    as: UTF8.self
)
for heading in ["Outline", "Key terms", "Questions asked"]
where !lectureBody.contains(heading) {
    failEngineCheck("lecture prompt omitted \(heading)")
}
guard lectureBody.contains("Do not label speakers as teacher or student"),
      lectureRequest.userContent == "Topic one. What does gravity mean?" else {
    failEngineCheck("lecture summary prompt or transcript changed")
}

// The API key must never be part of the request value itself.
let requestDescription = "\(cloudRequest)"
guard !requestDescription.contains("sk-") else {
    failEngineCheck("an API key appeared in the CloudAIRequest value")
}
let authorized = try! cloudRequest.urlRequest(apiKey: "sk-test-key")
guard authorized.value(forHTTPHeaderField: "Authorization")
        == "Bearer sk-test-key",
      authorized.httpShouldHandleCookies == false else {
    failEngineCheck("the authorised URLRequest was not built correctly")
}

// Empty transcripts never reach the network.
do {
    _ = try cloudEngine.makeRequest(
        transcript: "   ",
        configuration: cloudConfiguration
    )
    failEngineCheck("an empty transcript produced a cloud request")
} catch {
    // Expected.
}

// Response parsing.
let goodResponse = Data("""
{"choices":[{"message":{"role":"assistant","content":"Meeting notes."}}]}
""".utf8)
guard let parsed = try? CloudAIEnhancementEngine
        .firstMessageContent(from: goodResponse),
      parsed == "Meeting notes." else {
    failEngineCheck("a valid provider response was not parsed")
}
for malformed in [
    Data("{}".utf8),
    Data("{\"choices\":[]}".utf8),
    Data("{\"choices\":[{\"message\":{\"content\":\"\"}}]}".utf8),
    Data("not json".utf8)
] {
    do {
        _ = try CloudAIEnhancementEngine.firstMessageContent(from: malformed)
        failEngineCheck("a malformed provider response was accepted")
    } catch {
        // Expected.
    }
}

// The key store round-trips and clears.
let keyStore = InMemoryCloudAIKeyStore()
try! keyStore.saveKey("sk-example")
guard try! keyStore.loadKey() == "sk-example" else {
    failEngineCheck("the cloud API key did not round-trip")
}
try! keyStore.saveKey("   ")
guard try! keyStore.loadKey() == nil else {
    failEngineCheck("a blank cloud API key was stored instead of cleared")
}
try! keyStore.saveKey("sk-example")
try! keyStore.deleteKey()
guard try! keyStore.loadKey() == nil else {
    failEngineCheck("the cloud API key survived deletion")
}

// A configuration written before `autoApply` existed must still decode, and
// must decode as "keep asking". Falling back to a default configuration here
// would quietly disable the feature and discard the user's endpoint, model,
// and prompt.
let legacyCloudConfiguration = """
{
  "isEnabled": true,
  "provider": "anthropic",
  "baseURL": "https://api.anthropic.com/v1",
  "model": "claude-3-5-haiku-20241022",
  "prompt": "Legacy prompt."
}
"""
guard let legacyCloudData = legacyCloudConfiguration.data(using: .utf8),
      let decodedLegacyCloud = try? JSONDecoder().decode(
        CloudAIConfiguration.self,
        from: legacyCloudData
      ) else {
    failEngineCheck("a pre-autoApply cloud configuration failed to decode")
}
guard decodedLegacyCloud.isEnabled,
      decodedLegacyCloud.provider == .anthropic,
      decodedLegacyCloud.model == "claude-3-5-haiku-20241022",
      decodedLegacyCloud.prompt == "Legacy prompt." else {
    failEngineCheck("a pre-autoApply cloud configuration lost its settings")
}
guard decodedLegacyCloud.autoApply == false else {
    failEngineCheck(
        "a pre-autoApply cloud configuration opted into silent application"
    )
}

let localCloudTranscript = "Keep this local transcript exactly."
let dismissedCloudResolution = CloudTranscriptResolution.resolve(
    localTranscript: localCloudTranscript,
    acceptedTranscript: nil
)
let blankCloudResolution = CloudTranscriptResolution.resolve(
    localTranscript: localCloudTranscript,
    acceptedTranscript: "   \n"
)
let acceptedCloudResolution = CloudTranscriptResolution.resolve(
    localTranscript: localCloudTranscript,
    acceptedTranscript: "Accepted enhancement."
)
guard dismissedCloudResolution.transcript == localCloudTranscript,
      !dismissedCloudResolution.didApply,
      blankCloudResolution.transcript == localCloudTranscript,
      !blankCloudResolution.didApply,
      acceptedCloudResolution.transcript == "Accepted enhancement.",
      acceptedCloudResolution.didApply else {
    failEngineCheck("cloud review could lose the local transcript")
}

// autoApply survives a save/load round trip, so consent given once stays
// given.
let autoApplyConfiguration = CloudAIConfiguration(
    isEnabled: true,
    autoApply: true
)
guard let autoApplyData = try? JSONEncoder().encode(autoApplyConfiguration),
      let autoApplyDecoded = try? JSONDecoder().decode(
        CloudAIConfiguration.self,
        from: autoApplyData
      ),
      autoApplyDecoded.autoApply else {
    failEngineCheck("autoApply did not survive an encode/decode round trip")
}

print("ZenVoiceCoreChecks: cloud AI enhancement passed")

// MARK: - Anthropic request shape checks

var anthropicConfiguration = CloudAIConfiguration()
anthropicConfiguration.isEnabled = true
anthropicConfiguration.provider = .anthropic
anthropicConfiguration.baseURL = "https://api.anthropic.com/v1"
anthropicConfiguration.model = "claude-3-5-sonnet-20241022"

guard let anthropicEndpoint = try? anthropicConfiguration.resolvedEndpoint(),
      anthropicEndpoint.absoluteString
        == "https://api.anthropic.com/v1/messages" else {
    failEngineCheck("Anthropic endpoint was built incorrectly")
}

let anthropicRequest = try! cloudEngine.makeRequest(
    transcript: "anthropic test transcript",
    configuration: anthropicConfiguration
)
let anthropicBodyData = try! anthropicRequest.encodedBody()
let anthropicBody = try! JSONSerialization.jsonObject(
    with: anthropicBodyData
) as! [String: Any]
guard anthropicBody["model"] as? String
        == "claude-3-5-sonnet-20241022",
      anthropicBody["max_tokens"] as? Int == 4096,
      anthropicBody["system"] as? String
        == CloudAIPromptTemplate.cleanUp.text,
      let anthropicMessages = anthropicBody["messages"]
        as? [[String: Any]],
      anthropicMessages.first?["role"] as? String == "user",
      let anthropicContent = anthropicMessages.first?["content"]
        as? String,
      anthropicContent.contains("anthropic test transcript") else {
    failEngineCheck("Anthropic request body shape is wrong")
}

let anthropicURLRequest = try! anthropicRequest.urlRequest(
    apiKey: "sk-ant-test"
)
guard anthropicURLRequest.value(forHTTPHeaderField: "x-api-key")
        == "sk-ant-test",
      anthropicURLRequest.value(forHTTPHeaderField: "anthropic-version")
        == "2023-06-01" else {
    failEngineCheck("Anthropic auth/version headers are wrong")
}

let anthropicResponse = Data("""
{"content":[{"type":"text","text":"Anthropic notes."}]}
""".utf8)
guard let anthropicParsed = try? CloudAIEnhancementEngine
        .firstMessageContent(
            from: anthropicResponse,
            provider: .anthropic
        ),
      anthropicParsed == "Anthropic notes." else {
    failEngineCheck("Anthropic response was not parsed")
}

print("ZenVoiceCoreChecks: Anthropic request shape passed")

// MARK: - Formatting migration checks

let formattingSuite =
    "ZenVoiceCoreChecks.Formatting.\(UUID().uuidString)"
guard let formattingDefaults = UserDefaults(suiteName: formattingSuite) else {
    failEngineCheck("could not create formatting preference fixture")
}
defer {
    formattingDefaults.removePersistentDomain(forName: formattingSuite)
}

// Fresh defaults without old keys: should default to Clean.
guard TranscriptFormattingPreferences.load(defaults: formattingDefaults)
        == .clean else {
    failEngineCheck("formatting mode did not default to clean")
}

// Old keys present: Instant Refine Clean + ZenIntelligence Off -> Clean.
formattingDefaults.set(
    "clean",
    forKey: InstantRefinePreferences.preferenceKey
)
formattingDefaults.set(
    "off",
    forKey: ZenIntelligencePreferences.modeKey
)
formattingDefaults.set(
    false,
    forKey: TranscriptFormattingPreferences.migratedKey
)
guard TranscriptFormattingPreferences.load(defaults: formattingDefaults)
        == .clean else {
    failEngineCheck("formatting migration from clean/off failed")
}

// Old keys present: Instant Refine Off + ZenIntelligence Format -> Smart.
formattingDefaults.set(
    "off",
    forKey: InstantRefinePreferences.preferenceKey
)
formattingDefaults.set(
    "format",
    forKey: ZenIntelligencePreferences.modeKey
)
formattingDefaults.set(
    false,
    forKey: TranscriptFormattingPreferences.migratedKey
)
guard TranscriptFormattingPreferences.load(defaults: formattingDefaults)
        == .smart else {
    failEngineCheck("formatting migration from off/format failed")
}

// Old keys present: Instant Refine Agent Prompt + ZenIntelligence Off -> Clean.
// Agent-prompt layout commands moved to Commands; the rung collapses to Clean.
formattingDefaults.set(
    "agentPrompt",
    forKey: InstantRefinePreferences.preferenceKey
)
formattingDefaults.set(
    "off",
    forKey: ZenIntelligencePreferences.modeKey
)
formattingDefaults.set(
    false,
    forKey: TranscriptFormattingPreferences.migratedKey
)
guard TranscriptFormattingPreferences.load(defaults: formattingDefaults)
        == .clean else {
    failEngineCheck("formatting migration from agentPrompt/off failed")
}

// After migration, the new key is respected over any stale old keys.
TranscriptFormattingPreferences.save(.cloud, defaults: formattingDefaults)
guard TranscriptFormattingPreferences.load(defaults: formattingDefaults)
        == .cloud else {
    failEngineCheck("formatting save/load failed")
}

// Smart and Cloud must reach the context-aware enhancer, not plain `.format`.
// `.format` left `ZenIntelligenceEngine`'s context join unreachable: the
// `context:` argument threaded from AppDelegate through
// TranscriptFormattingEngine and WriteModeEngine was accepted and ignored at
// every call site, anyone migrated from ZenIntelligence = Context Aware lost
// sentence joining with no setting left to restore it, and ADR 0007's
// description of Smart stopped matching the code. Nothing about that failed to
// compile, so it is asserted here instead.
for rung in [TranscriptFormattingMode.smart, .cloud] {
    guard rung.zenIntelligenceMode == .contextAware else {
        failEngineCheck(
            "\(rung.rawValue) maps to \(rung.zenIntelligenceMode.rawValue); "
                + "the context join is unreachable again"
        )
    }
}
for rung in [TranscriptFormattingMode.off, .clean] {
    guard rung.zenIntelligenceMode == .off else {
        failEngineCheck("\(rung.rawValue) should not enhance")
    }
}

// The listing cache must never be able to answer for changed bytes on the
// integrity path. `verify` hashes every time; only `verifyForListing` may
// reuse an answer.
let listingDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(
    at: listingDirectory,
    withIntermediateDirectories: true
)
defer {
    try? FileManager.default.removeItem(at: listingDirectory)
}
let listingURL = listingDirectory.appendingPathComponent("fixture.bin")
try Data("ZenVoice".utf8).write(to: listingURL)
guard try VerifiedModelCatalog.verifyForListing(
    listingURL,
    for: verifierModel
) else {
    failEngineCheck("listing verification rejected valid data")
}
try Data("ZenVoicf".utf8).write(to: listingURL)
guard try !VerifiedModelCatalog.verify(listingURL, for: verifierModel) else {
    failEngineCheck(
        "verify() reused a cached answer for changed bytes"
    )
}

print("ZenVoiceCoreChecks: formatting migration passed")

// MARK: - Agentic planner and validator checks

let validatorRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("zenvoice-validator-checks-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: validatorRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: validatorRoot) }
let validator = PlanValidator(allowedRoot: validatorRoot)

func step(
    number: Int,
    agent: GoalAgent,
    command: String,
    dependsOn: [Int] = [],
    plannedRisk: RiskLevel = .low,
    computedRisk: RiskLevel = .low,
    workingDirectory: String? = nil
) -> GoalStep {
    GoalStep(
        number: number,
        agent: agent,
        command: command,
        description: "\(agent.displayName) step \(number)",
        workingDirectory: workingDirectory,
        dependsOn: dependsOn,
        plannedRisk: plannedRisk,
        computedRisk: computedRisk
    )
}

// 1. Valid plan passes and recomputes risk from the surface, ignoring
//    the planner's self-reported risk.
let validPlan = GoalPlan(
    title: "Run tests",
    transcript: "run the tests in bridgemind",
    steps: [
        step(number: 1, agent: .codex, command: "cd bridgemind && codex 'run tests'", plannedRisk: .low),
        step(number: 2, agent: .shell, command: "git status", plannedRisk: .high),
    ]
)
let validated = try validator.validate(validPlan)
guard validated.steps[0].computedRisk == .medium else {
    failEngineCheck("codex test step should recompute to medium, got \(validated.steps[0].computedRisk)")
}
guard validated.steps[1].computedRisk == .low else {
    failEngineCheck("git status shell step should recompute to low, got \(validated.steps[1].computedRisk)")
}

// 2. Empty plan rejected.
do {
    _ = try validator.validate(GoalPlan(title: "Empty", transcript: "", steps: []))
    failEngineCheck("empty plan should be rejected")
} catch PlanValidationError.emptyPlan { }

// 3. Missing title rejected.
do {
    _ = try validator.validate(GoalPlan(title: "   ", transcript: "", steps: [step(number: 1, agent: .notification, command: "hello")]))
    failEngineCheck("missing title should be rejected")
} catch PlanValidationError.missingTitle { }

// 4. Unsupported schema version rejected.
do {
    var bad = validPlan
    bad.schemaVersion = 99
    _ = try validator.validate(bad)
    failEngineCheck("unsupported schema version should be rejected")
} catch PlanValidationError.unsupportedSchemaVersion(let v) {
    guard v == 99 else { failEngineCheck("wrong schema version in error") }
}

// 5. Non-contiguous step numbers rejected.
do {
    let plan = GoalPlan(title: "Gaps", transcript: "", steps: [
        step(number: 1, agent: .notification, command: "a"),
        step(number: 3, agent: .notification, command: "b", dependsOn: [1])
    ])
    _ = try validator.validate(plan)
    failEngineCheck("non-contiguous step numbers should be rejected")
} catch PlanValidationError.nonContiguousStepNumbers { }

// 6. Duplicate step number rejected.
do {
    let plan = GoalPlan(title: "Dup", transcript: "", steps: [
        step(number: 1, agent: .notification, command: "a"),
        step(number: 1, agent: .notification, command: "b")
    ])
    _ = try validator.validate(plan)
    failEngineCheck("duplicate step number should be rejected")
} catch PlanValidationError.duplicateStepNumber(1) { }

// 7. Invalid dependency rejected.
do {
    let plan = GoalPlan(title: "Bad dep", transcript: "", steps: [
        step(number: 1, agent: .notification, command: "a", dependsOn: [2])
    ])
    _ = try validator.validate(plan)
    failEngineCheck("invalid dependency should be rejected")
} catch PlanValidationError.invalidDependency(1, 2) { }

// 8. Forward dependencies rejected. The orchestrator runs steps in order, so a
// dependency on a later step would silently skip the earlier one — and since a
// cycle needs a forward edge, this also makes circular plans impossible.
do {
    let plan = GoalPlan(title: "Forward", transcript: "", steps: [
        step(number: 1, agent: .notification, command: "a", dependsOn: [2]),
        step(number: 2, agent: .notification, command: "b", dependsOn: [1])
    ])
    _ = try validator.validate(plan)
    failEngineCheck("forward dependencies should be rejected")
} catch PlanValidationError.invalidDependency(1, 2) { }

// 9. Orphaned notification step rejected (unless it's the only step).
do {
    let plan = GoalPlan(title: "Orphan", transcript: "", steps: [
        step(number: 1, agent: .shell, command: "git status"),
        step(number: 2, agent: .notification, command: "done")
    ])
    _ = try validator.validate(plan)
    failEngineCheck("orphaned notification step should be rejected")
} catch PlanValidationError.orphanedNotificationStep(2) { }

// 10. Secret-shaped value rejected.
do {
    let plan = GoalPlan(title: "Secret", transcript: "", steps: [
        step(number: 1, agent: .shell, command: "sk-test12345678901234567890")
    ])
    _ = try validator.validate(plan)
    failEngineCheck("secret-shaped command should be rejected")
} catch PlanValidationError.secretDetected { }

// 11. Working directory outside allowed root rejected.
do {
    let plan = GoalPlan(title: "Path", transcript: "", steps: [
        step(number: 1, agent: .shell, command: "ls", workingDirectory: "/tmp")
    ])
    _ = try validator.validate(plan)
    failEngineCheck("working directory outside root should be rejected")
} catch PlanValidationError.workingDirectoryNotAllowed { }

// 12. Empty command rejected.
do {
    let plan = GoalPlan(title: "Empty cmd", transcript: "", steps: [
        step(number: 1, agent: .shell, command: "  ")
    ])
    _ = try validator.validate(plan)
    failEngineCheck("empty command should be rejected")
} catch PlanValidationError.emptyCommand(1) { }

// 13. open -a classified low.
let openPlan = GoalPlan(title: "Open", transcript: "", steps: [
    step(number: 1, agent: .shell, command: "open -a Safari")
])
let openValidated = try validator.validate(openPlan)
guard openValidated.steps[0].computedRisk == .low else {
    failEngineCheck("open -a should be low risk")
}

// 14. git push classified high.
let pushPlan = GoalPlan(title: "Push", transcript: "", steps: [
    step(number: 1, agent: .shell, command: "git push origin main")
])
let pushValidated = try validator.validate(pushPlan)
guard pushValidated.steps[0].computedRisk == .high else {
    failEngineCheck("git push should be high risk, got \(pushValidated.steps[0].computedRisk)")
}

// 15. Dangerous codex command classified high.
let deployPlan = GoalPlan(title: "Deploy", transcript: "", steps: [
    step(number: 1, agent: .codex, command: "codex 'deploy to production'")
])
let deployValidated = try validator.validate(deployPlan)
guard deployValidated.steps[0].computedRisk == .high else {
    failEngineCheck("codex deploy command should be high risk, got \(deployValidated.steps[0].computedRisk)")
}

// 16. Notification with a dependency is allowed.
let notifyPlan = GoalPlan(title: "Notify", transcript: "", steps: [
    step(number: 1, agent: .shell, command: "git status"),
    step(number: 2, agent: .notification, command: "done", dependsOn: [1])
])
_ = try validator.validate(notifyPlan)

print("ZenVoiceCoreChecks: agentic planner and validator passed")

// MARK: - Smart local formatting checks

enum LocalModelStubBehavior: Sendable {
    case output(String)
    case failure
    case slow(String)
}

struct LocalModelStub: LocalLanguageModel {
    let availability: LocalIntelligenceAvailability
    let behavior: LocalModelStubBehavior

    func generate(
        prompt: String,
        maximumResponseTokens: Int
    ) async throws -> String {
        guard availability == .available else {
            throw LocalIntelligenceError.unavailable(availability)
        }
        switch behavior {
        case .output(let text):
            return text
        case .failure:
            throw LocalIntelligenceError.emptyResponse
        case .slow(let text):
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return text
        }
    }
}

guard TranscriptSemanticGuard.preservesLexicalContent(
    original: "hello world this is five",
    candidate: "Hello, world. This is five."
) else {
    failEngineCheck("lexical guard rejected punctuation-only formatting")
}
guard !TranscriptSemanticGuard.preservesLexicalContent(
    original: "hello world",
    candidate: "hello helpful world"
) else {
    failEngineCheck("lexical guard accepted an invented word")
}
guard !TranscriptSemanticGuard.preservesLexicalContent(
    original: "deploy version two",
    candidate: "deploy version three"
) else {
    failEngineCheck("lexical guard accepted a changed number word")
}

let modelFormatted = await SmartFormattingEngine(
    model: LocalModelStub(
        availability: .available,
        behavior: .output("Hello, world. This is five.")
    )
).format("hello world this is five")
guard modelFormatted.text == "Hello, world. This is five.",
      modelFormatted.modelUsed,
      modelFormatted.fallback == nil else {
    failEngineCheck("safe local model formatting was not accepted")
}

let unsafeModelOutput = await SmartFormattingEngine(
    model: LocalModelStub(
        availability: .available,
        behavior: .output("Hello, helpful world.")
    )
).format("hello world")
guard unsafeModelOutput.text == "hello world",
      !unsafeModelOutput.modelUsed,
      unsafeModelOutput.fallback == .unsafeOutput else {
    failEngineCheck("unsafe model output fallback was \(unsafeModelOutput.text) / \(String(describing: unsafeModelOutput.fallback))")
}

let unavailableModel = await SmartFormattingEngine(
    model: LocalModelStub(
        availability: .modelNotReady,
        behavior: .failure
    )
).format("hello world")
guard unavailableModel.text == "hello world",
      !unavailableModel.modelUsed,
      unavailableModel.fallback == .modelUnavailable(.modelNotReady) else {
    failEngineCheck("unavailable local model did not fall back")
}

let failedModel = await SmartFormattingEngine(
    model: LocalModelStub(
        availability: .available,
        behavior: .failure
    )
).format("hello world")
guard failedModel.text == "hello world",
      failedModel.fallback == .generationFailed else {
    failEngineCheck("failed local generation did not fall back")
}

let timedOutModel = await SmartFormattingEngine(
    model: LocalModelStub(
        availability: .available,
        behavior: .slow("Hello, world.")
    ),
    timeoutSeconds: 0.01
).format("hello world")
guard timedOutModel.text == "hello world",
      timedOutModel.fallback == .generationFailed else {
    failEngineCheck("timed-out local generation did not fall back")
}

let unifiedSmart = await TranscriptFormattingEngine(
    localModel: LocalModelStub(
        availability: .available,
        behavior: .output("Hello, world.")
    )
).format("hello world", mode: .smart)
guard unifiedSmart.text == "Hello, world.",
      unifiedSmart.localModelUsed,
      unifiedSmart.smartFallback == nil else {
    failEngineCheck("unified formatting engine did not use the local model")
}

print("ZenVoiceCoreChecks: Smart local formatting passed")


await runAgenticChecks()
