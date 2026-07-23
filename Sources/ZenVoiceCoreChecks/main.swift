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
