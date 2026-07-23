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
guard verifiedModels.count == 6,
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
guard ModelRecommendationEngine.recommendedTier(
    for: eightGigabyteProfile
) == .fast,
ModelRecommendationEngine.recommendedTier(
    for: sixteenGigabyteProfile
) == .balanced,
ModelRecommendationEngine.recommendedTier(
    for: twentyFourGigabyteProfile
) == .highAccuracy else {
    FileHandle.standardError.write(
        Data("FAIL: hardware model tiers are incorrect\n".utf8)
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
