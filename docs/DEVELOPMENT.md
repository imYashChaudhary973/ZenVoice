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
swift run ZenVoiceStorageChecks
```

The checks cover:

- transcript whitespace normalization;
- Whisper metadata removal;
- conservative leading-filler cleanup;
- microphone dB clamping;
- louder input producing taller waveform levels;
- valid default-hotkey display and serialization.
- encrypted transcript storage without plaintext leakage;
- weighted words-per-minute calculation;
- interruption recovery and 24-hour audio expiry;
- cancellation cleanup and cryptographic Delete All;
- explicit history-consent defaults.

## Manual QA

1. Launch `build/ZenVoice.app`.
2. Confirm the settings window opens and the Zen logo appears in the menu bar
   and ZenBar.
3. Open **History** and verify the one-time local-history choice appears before
   any history database is created.
4. Enable local history and confirm the empty encrypted-history state appears.
5. Open **Shortcuts**, select the current shortcut, and record a temporary
   two-modifier combination.
6. Repeat for **Paste last dictation**.
7. Quit and relaunch ZenVoice. Confirm both custom shortcuts persisted, then use
   **Reset Default**.
8. Open **Privacy** and confirm Microphone, Accessibility, local-history, and local-model
   status match System Settings and the local installation.
9. Close the settings window and reopen it from **Open ZenVoice…** in the
   menu-bar menu.
10. Open TextEdit and place the cursor in a document.
11. Press the configured shortcut.
12. Speak quietly and confirm ZenBar shows shorter waveform bars.
13. Speak loudly and confirm ZenBar shows taller waveform bars.
14. Select the checkmark and confirm the transcript is inserted into TextEdit
    and appears under **Today** in History.
15. Copy and paste the saved record, then test the paste-last shortcut.
16. Start again, select cancel, and confirm no history record remains.
17. Toggle **Show Status Message** from the menu-bar app and confirm the
   dictation message follows the preference.
18. Press the shortcut again to confirm hotkey stop-and-insert still works.
19. Disable Accessibility permission and repeat.
20. Confirm the transcript remains available on the clipboard.

Also test:

- denied microphone permission;
- a shortcut without a modifier;
- a shortcut already reserved by macOS or another application;
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
