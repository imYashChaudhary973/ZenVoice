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
InstantRefinePreferences.save(.localModel, defaults: refineDefaults)
guard InstantRefinePreferences.load(defaults: refineDefaults)
        == .localModel else {
    FileHandle.standardError.write(
        Data("FAIL: local model mode did not persist\n".utf8)
    )
    exit(1)
}

let refinementModels = VerifiedRefinementModelCatalog.models
guard refinementModels.count == 2,
      Set(refinementModels.map(\.tier)) == [.fast, .balanced],
      refinementModels.allSatisfy({
          $0.publisher == "Qwen"
              && $0.license == "Apache-2.0"
              && $0.downloadURL.scheme == "https"
              && $0.downloadURL.host == "huggingface.co"
              && $0.sourceRevision.count == 40
              && $0.sha256.count == 64
              && $0.fileSizeBytes > 0
      }),
      !refinementModels.contains(where: {
          $0.id.contains("3b")
      }) else {
    FileHandle.standardError.write(
        Data("FAIL: refinement allowlist is not legally pinned\n".utf8)
    )
    exit(1)
}

let safeLocalCandidate =
    LocalRefinementGuard.validatedCandidate(
        output: #"{"text":"Create the local app."}"#,
        original: "create the local app"
    )
guard safeLocalCandidate == "Create the local app.",
      LocalRefinementGuard.validatedCandidate(
        output: #"{"text":"Create the cloud app."}"#,
        original: "Create the local app."
      ) == nil,
      LocalRefinementGuard.validatedCandidate(
        output: #"{"text":"Keep"}"#,
        original: "Please keep every important word here"
      ) == nil,
      LocalRefinementGuard.validatedCandidate(
        output: #"{"text":"Do share this file."}"#,
        original: "Do not share this file."
      ) == nil,
      LocalRefinementGuard.validatedCandidate(
        output: #"{"text":"The file deletes the app."}"#,
        original: "The app deletes the file."
      ) == nil,
      LocalRefinementGuard.validatedCandidate(
        output: #"{"text":"Keep keep this local."}"#,
        original: "Keep this local."
      ) == nil,
      LocalRefinementGuard.validatedCandidate(
        output: "```json\n{\"text\":\"Keep this\"}\n```",
        original: "Keep this"
      ) == nil,
      LocalRefinementPrompt.make(transcript: "Hola mundo")
        .contains("Hola mundo") else {
    FileHandle.standardError.write(
        Data("FAIL: local refinement meaning guard is unsafe\n".utf8)
    )
    exit(1)
}

let refinementSuite =
    "ZenVoiceCoreChecks.RefinementModel.\(UUID().uuidString)"
guard let refinementDefaults =
    UserDefaults(suiteName: refinementSuite),
      let fastRefinementModel = refinementModels.first else {
    FileHandle.standardError.write(
        Data("FAIL: could not create refinement model fixture\n".utf8)
    )
    exit(1)
}
defer {
    refinementDefaults.removePersistentDomain(
        forName: refinementSuite
    )
}
RefinementModelSelectionPreferences.save(
    fastRefinementModel,
    defaults: refinementDefaults
)
guard RefinementModelSelectionPreferences.load(
    defaults: refinementDefaults
) == fastRefinementModel else {
    FileHandle.standardError.write(
        Data("FAIL: refinement model selection did not persist\n".utf8)
    )
    exit(1)
}

print("ZenVoiceCoreChecks: Instant Refine passed")

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
    refinementMode: .localModel,
    voiceCommandsEnabled: true
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
guard safeContext.count <= NextDictationContext.maximumCharacterCount,
      !safeContext.contains("<|"),
      !safeContext.contains("\n") else {
    FileHandle.standardError.write(
        Data("FAIL: next-dictation context was not bounded\n".utf8)
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
          !choice.displayName.isEmpty else {
        FileHandle.standardError.write(
            Data("FAIL: hold-to-dictate choice is invalid\n".utf8)
        )
        exit(1)
    }
}

print("ZenVoiceCoreChecks: private and hold controls passed")

let verifiedModels = VerifiedModelCatalog.models
guard verifiedModels.count == 9,
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
              && $0.license == "MIT"
              && URL(string: $0.licenseURL)?.scheme == "https"
              && URL(string: $0.upstreamRepository)?.host == "github.com"
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
// Apple Silicon transcribes on the GPU, so every Metal-capable Mac should be
// steered to Turbo rather than being downgraded on memory alone. Recommending
// by memory sent 16 GB Macs to Whisper Base, which loses roughly one word in
// three at speed.
guard ModelRecommendationEngine.recommendedModelID(
    for: eightGigabyteProfile
) == "whisper-large-v3-turbo",
ModelRecommendationEngine.recommendedModelID(
    for: sixteenGigabyteProfile
) == "whisper-large-v3-turbo",
ModelRecommendationEngine.recommendedModelID(
    for: twentyFourGigabyteProfile
) == "whisper-large-v3-turbo",
ModelRecommendationEngine.recommendedTier(
    for: sixteenGigabyteProfile
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
guard ModelRecommendationEngine.recommendedModelID(
    for: intelProfile
) == "whisper-small-multilingual",
ModelRecommendationEngine.recommendedModelID(
    for: smallIntelProfile
) == "whisper-tiny-multilingual",
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

// Exactly one model may carry the recommendation badge, otherwise the UI is
// telling the user two different things at once.
let recommendedCount = VerifiedModelCatalog.models.filter {
    ModelRecommendationEngine.recommendation(
        for: $0,
        profile: twentyFourGigabyteProfile
    ).level == .recommended
}.count
guard recommendedCount == 1 else {
    FileHandle.standardError.write(
        Data(
            "FAIL: \(recommendedCount) models marked recommended, expected 1\n"
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
      LanguageProfile.hinglish.isCompatible(with: .multilingual) else {
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
guard LiveDictationPreferences.isPreviewEnabled(
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
