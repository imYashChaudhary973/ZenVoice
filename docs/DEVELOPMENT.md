# Development

## Prerequisites

- macOS 14 or newer on Apple Silicon
- Swift 5.10 or newer
- Homebrew
- `whisper.cpp`
- A local GGML English Whisper model

Install the runtime:

```bash
brew install whisper-cpp
```

Create ZenVoice's model directory and place `ggml-base.en.bin` inside it:

```bash
mkdir -p "$HOME/Library/Application Support/ZenVoice/Models"
cp /absolute/path/to/ggml-base.en.bin \
  "$HOME/Library/Application Support/ZenVoice/Models/ggml-base.en.bin"
```

The model is intentionally excluded from Git because it is large and has its
own upstream distribution terms.

## Configuration

ZenVoice searches for:

1. `ZENVOICE_WHISPER_PATH`, then standard Homebrew `whisper-cli` locations.
2. `ZENVOICE_MODEL_PATH`, then
   `~/Library/Application Support/ZenVoice/Models/ggml-base.en.bin`.

Environment overrides are most useful when launching the executable directly
from a configured shell. The standard application-support path is recommended
for the packaged app.

## Build

Compile the debug target:

```bash
swift build
```

Build the local `.app` bundle:

```bash
./Scripts/build-app.sh
```

The script:

1. produces a release Swift build;
2. generates the macOS icon from the source Zen logo;
3. assembles `build/ZenVoice.app`;
4. embeds the required Hardened Runtime audio-input entitlement;
5. signs with the first available Apple Development identity.

Set `ZENVOICE_SIGNING_IDENTITY` to a certificate hash or full identity name to
choose a specific signing identity:

```bash
ZENVOICE_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" \
  ./Scripts/build-app.sh
```

If no Apple Development identity is available, the script falls back to ad-hoc
signing and prints a warning.

## Stable macOS permissions

Microphone and Accessibility approvals are associated with the app's code
signing requirement. Ad-hoc signing ties that requirement to one specific build
hash, so a rebuilt executable looks like a new app to macOS.

Apple Development signing gives local builds a stable requirement based on the
Apple-issued signer, team, and `dev.yashchaudhary.ZenVoice` bundle identifier.
Because the build enables Hardened Runtime, the signature also embeds
`com.apple.security.device.audio-input` so AVFoundation may request microphone
access.
After switching from an ad-hoc build:

1. Remove the old ZenVoice entry from **System Settings → Privacy & Security →
   Accessibility** if it remains listed.
2. Launch the newly built `build/ZenVoice.app`.
3. Start and finish one dictation.
4. Approve Microphone and Accessibility when macOS asks.

That approval should survive normal code changes and rebuilds as long as the
bundle identifier and Apple Development team remain unchanged. A replaced or
expired signing certificate, a different team, or a different bundle identifier
can require approval again.

## Automated checks

```bash
swift run ZenVoiceCoreChecks
```

The checks cover:

- transcript whitespace normalization;
- Whisper metadata removal;
- conservative leading-filler cleanup;
- microphone dB clamping;
- louder input producing taller waveform levels.

## Manual QA

1. Launch `build/ZenVoice.app`.
2. Confirm the Zen logo appears in the menu bar and ZenBar.
3. Open TextEdit and place the cursor in a document.
4. Press `Control + Option + Space`.
5. Speak quietly and confirm ZenBar shows shorter waveform bars.
6. Speak loudly and confirm ZenBar shows taller waveform bars.
7. Select the checkmark and confirm the transcript is inserted into TextEdit.
8. Start again, select cancel, and confirm no transcript is inserted.
9. Toggle **Show Status Message** from the menu-bar app and confirm the
   dictation message follows the preference.
10. Press the shortcut again to confirm hotkey stop-and-insert still works.
11. Disable Accessibility permission and repeat.
12. Confirm the transcript remains available on the clipboard.

Also test:

- denied microphone permission;
- silence-only recording;
- repeated hotkey presses during transcription;
- app relaunch;
- multiple displays and full-screen spaces.

## Commit style

Use focused Conventional Commit messages:

```text
feat: add configurable dictation shortcut
fix: release microphone after cancelled recording
docs: explain multilingual model setup
chore: update local packaging script
```

Do not commit model files, recordings, transcripts, credentials, `.build/`, or
the generated `build/` directory.
