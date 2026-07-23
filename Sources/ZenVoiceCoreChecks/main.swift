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
