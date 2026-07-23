# Development

## Prerequisites

- macOS 14 or newer on Apple Silicon
- Swift 5.10 or newer
- Internet access on the first build so Swift Package Manager can fetch the
  pinned `whisper.cpp` XCFramework
- A verified GGML model downloaded from ZenVoice's **Models** screen

## Configuration

ZenVoice searches for:

1. the model selected in ZenVoice's verified catalogue;
2. `ZENVOICE_MODEL_PATH` as a developer override; then
   `~/Library/Application Support/ZenVoice/Models/ggml-base.en.bin`.

The runtime is the checksum-pinned `whisper.cpp` v1.9.1 XCFramework declared
in `Package.swift`. `ZENVOICE_MODEL_PATH` is most useful when launching the
executable directly from a configured shell. The verified catalogue is
recommended for the packaged app.

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
4. embeds and signs the pinned `whisper.framework`;
5. embeds the required Hardened Runtime audio-input entitlement;
6. signs with the first available Apple Development identity.

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
swift run ZenVoiceRuntimeChecks
swift build
./Scripts/build-app.sh
codesign --verify --deep --strict build/ZenVoice.app
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
- local insight totals, streaks, seven-day activity, distinct applications,
  conservative category classification, and category correction;
- whole-phrase correction boundaries, encrypted correction rules, usage
  counts, recurring phrases, and Delete All cleanup;
- interruption recovery and capture-bounded 24-hour audio expiry;
- cancellation cleanup and cryptographic Delete All;
- default-on history with an explicit pause;
- partial transcript persistence and ciphertext field binding;
- recovery-path confinement and deletion with corrupt ciphertext;
- durable Private Dictation suppression, recovery-disable cleanup, strict
  hotkey labels, and hold-key configuration.
- in-process runtime model loading and two sequential transcription passes
  through one persistent transcriber instance. This check skips only when no
  local model is installed.
- privacy-safe numeric share-card payload validation.
- Instant Refine fillers, repeated words, punctuation-marked restarts, agent
  prompt layout commands, persisted mode, disabled behavior, and destructive
  edit rejection.
- application-profile persistence and removal, bounded context sanitization,
  default-off voice commands, English and multilingual command aliases, and
  per-call Whisper language/context arguments.
- correction-rule pause and pattern-analysis preferences, independent rule
  deletion, before/after review selection, and failed/partial Recovery Inbox
  filtering.
- fresh-install versus upgrade onboarding state, privacy-inventory counts,
  confirmed recovery-audio deletion, and Reduce Motion-aware ZenBar state.

GitHub Actions runs the same checks on macOS for each pull request and `main`
push. Semgrep Community Edition runs independently on an Ubuntu runner. The
Semgrep job uses the public rule registry, does not require an account token,
and has read-only repository permission.

## Release readiness

Development packaging is intentionally different from public distribution.
After building, inspect the current gate:

```bash
./Scripts/check-release-readiness.sh
```

The command is expected to report blockers for private development builds. See
[Release Readiness](RELEASE_READINESS.md),
[M9 Security Review](SECURITY_REVIEW.md), and the root
[Third-Party Notices](../THIRD_PARTY_NOTICES.md) before preparing any
distributable artifact.

## Manual QA

1. Launch `build/ZenVoice.app`.
2. Confirm the settings window opens and the Zen logo appears in the menu bar
   and ZenBar.
3. Open **History** and confirm the encrypted-history state is available by
   default.
4. Pause history in **Privacy**, dictate once, and confirm no record is added.
5. Open **Shortcuts**, select the current shortcut, and record a temporary
   two-modifier combination.
6. Repeat for **Paste last dictation** and **Private Dictation**.
7. Enable hold-to-dictate, hold Fn, speak, and release. Confirm release stops
   recording and inserts the result.
8. Quit and relaunch ZenVoice. Confirm all shortcut choices persisted.
9. Open **Privacy** and confirm Microphone, Accessibility, local-history, and local-model
   status match System Settings and the local installation.
10. Open **Insights** and confirm totals match History. Change one record's
    category from its History menu, return to Insights, and confirm the
    category breakdown updates.
11. Open **Voice Profile**, add a temporary correction such as `zen pens` →
    `ZenPense`, dictate that phrase, and confirm the corrected result and usage
    count. Delete the temporary rule.
12. Enable Private Dictation, use the same phrase, and confirm the correction
    can still apply but its saved usage count does not change.
13. Open **Models**, select an installed model, dictate twice, and confirm the
    second transcription does not reload the model.
14. Open **Insights**, select **Share Highlights**, and verify the preview
    contains only words, WPM, streak, and app count. Confirm no transcript or
    application name appears.
15. Select **Save PNG**, cancel the save panel, then select **Share…** and
    cancel the macOS Share menu. Confirm neither action happens automatically.
16. Close the settings window and reopen it from **Open ZenVoice…** in the
   menu-bar menu.
17. Open TextEdit and place the cursor in a document.
18. Press the configured shortcut.
19. Speak quietly and confirm ZenBar shows shorter waveform bars.
20. Speak loudly and confirm ZenBar shows taller waveform bars.
21. Select the checkmark and confirm the transcript is inserted into TextEdit
    and appears under **Today** in History.
22. Confirm History offers Copy but no Paste, then test the paste-last shortcut.
23. Start again, select cancel, and confirm no history record remains.
24. Toggle **Show Status Message** from the menu-bar app and confirm the
   dictation message follows the preference.
25. Press the shortcut again to confirm hotkey stop-and-insert still works.
26. Disable Accessibility permission and repeat.
27. Confirm the transcript remains available on the clipboard.
28. Open **Instant Refine**, choose **Clean**, dictate “Create a login page,
    no wait, a sign-up page,” and confirm only the corrected sentence is pasted.
29. Choose **Agent Prompt**, explicitly say “new paragraph,” and confirm the
    pasted prompt contains the requested paragraph break.
30. Choose **Off**, repeat a filler or word, and confirm Instant Refine makes no
    additional change beyond Whisper's base cleanup.
31. Start a model download and confirm percentage progress appears. Cancel,
    immediately start another download, and confirm the cancelled task does not
    clear the new progress state.
32. Open **Instant Refine**, download the Fast refinement model, and confirm
    progress changes to a separate verification state before the model becomes
    selectable.
33. Select **Local Model**, dictate one English, Spanish, and Hinglish example,
    and confirm output keeps the spoken language and introduces no new content
    words.
34. Remove the selected refinement model and confirm Local Model mode visibly
    falls back to Clean without blocking dictation.
35. For a real runtime gate, set `ZENVOICE_REFINEMENT_MODEL_PATH` to the
    verified Qwen GGUF and run `swift run ZenVoiceRuntimeChecks`.

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
