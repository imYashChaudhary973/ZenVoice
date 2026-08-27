# Release QA Record — ZenVoice 0.4.4

Generated 2026-08-28 from commit `4a996f468500c3a77e5782946a5bf2beef3506a3`.
Automatable evidence collected by agent; manual rows are marked **Requires human tester**.

## Candidate

| Field | Value |
|---|---|
| Release version and build | 0.4.4 (4) |
| Distribution scope | Public GitHub beta |
| Minimum supported version (deployment target) | Apple Silicon, macOS 14 or newer |
| macOS versions actually certified by this sweep | macOS 27.0 (26A5421a) — in-progress; manual rows pending |
| Source commit reported by `Scripts/build-app.sh` | `4a996f468500c3a77e5782946a5bf2beef3506a3` |
| Notarization upload archive | `ZenVoice-notarization-upload.zip` (SHA-256: `df98a7e557a697c20fedc3ccc03f21fdd162b807f64e146155c1d1a6234b575b`) |
| Notarization request ID | captured by `notarytool` at build time; retained with release assets |
| Distribution artifact | `ZenVoice-distribution.zip` |
| Distribution SHA-256 printed by `Scripts/notarize-app.sh` | `f2cb618d33c831d9c9d84107355e6f03d531da2a8b21b6b8eb3cba8faf839027` |
| Published DMG SHA-256 | `8c7dbf30beccfe505ba0ab8ebca58d06f00bfb91d5e57de9207cc4a7535ed6b2` |
| Test date | 2026-08-28 |
| Tester name, initials, or role | Automated pre-flight + human manual rows |
| Mac model | MacBook Pro (Mac17,2) |
| Chip and memory | Apple M5, 24 GB |
| macOS version | 27.0 (26A5421a) |
| Developer ID identity and team | Developer ID Application: Yash Chaudhary (8QSM298XJ2) |
| `codesign`, `spctl`, and `stapler` evidence | See below |

### Signing and notarization evidence

```zsh
$ mdls -name kMDItemVersion -name kMDItemCFBundleIdentifier -name kMDItemDisplayName /Applications/ZenVoice.app
kMDItemCFBundleIdentifier = "com.zenvoice.app"
kMDItemDisplayName        = "ZenVoice.app"
kMDItemVersion            = "0.4.4"

$ plutil -extract CFBundleShortVersionString raw /Applications/ZenVoice.app/Contents/Info.plist
0.4.4
$ plutil -extract CFBundleVersion raw /Applications/ZenVoice.app/Contents/Info.plist
4
$ plutil -extract CFBundleIdentifier raw /Applications/ZenVoice.app/Contents/Info.plist
com.zenvoice.app

$ codesign -dv --verbose=4 /Applications/ZenVoice.app 2>&1 | head -12
Executable=/Applications/ZenVoice.app/Contents/MacOS/ZenVoice
Identifier=com.zenvoice.app
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20500 size=84828 flags=0x10000(runtime) hashes=2640+7 location=embedded
Hash type=sha256 size=32
CandidateCDHash sha256=30dfc4141eba8d8880f78d879ad71b3f0e4bab00
Signature size=8978
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
Timestamp=27 Aug 2026 at 10:37:36
Notarization Ticket=stapled

$ spctl -a -vv /Applications/ZenVoice.app 2>&1
/Applications/ZenVoice.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Yash Chaudhary (8QSM298XJ2)

$ xcrun stapler validate /Applications/ZenVoice.app 2>&1
The validate action worked!

$ codesign -d --entitlements :- /Applications/ZenVoice.app 2>&1
<plist version="1.0"><dict><key>com.apple.security.device.audio-input</key><true/></dict></dict></plist>
```

Nested executables signed with the same Developer ID:
- `ZenVoice.app/Contents/MacOS/ZenVoice`
- `whisper.framework`
- `libparakeet.dylib`
- `Sparkle.framework` and embedded XPC services

Entitlement surface is `audio-input` only; `get-task-allow` is absent.
Published DMG on GitHub Releases matches local artifact exactly:
- `https://github.com/imYashChaudhary973/ZenVoice/releases/download/v0.4.4/ZenVoice.dmg`
- SHA-256: `8c7dbf30beccfe505ba0ab8ebca58d06f00bfb91d5e57de9207cc4a7535ed6b2`
- `hdiutil verify`: VALID
- `stapler validate`: accepted

## Installed speech models

| Display name | Catalogue ID | Runtime | Revision | Status |
|---|---|---|---|---|
| Whisper Small | `whisper-small-multilingual` | whisper.cpp | pinned v1.9.1 | In use (currently selected) |
| Whisper Turbo | `whisper-large-v3-turbo` | whisper.cpp | pinned v1.9.1 | Not installed in this sweep |
| Hinglish Apex | `hindi2hinglish-apex` | whisper.cpp | pinned v1.9.1 | Not installed in this sweep |
| Whisper Medium | `whisper-medium-multilingual` | whisper.cpp | pinned v1.9.1 | Not installed in this sweep |

Note: only `whisper-small-multilingual` is present in `~/Library/Application Support/ZenVoice/Models/`. Runtime checks in CI use `ZENVOICE_RUNTIME_REQUIRED=1` with a model installed in the CI workspace.

## Automated verification

| Check | Result | Evidence |
|---|---|---|
| `swift build` | Pass | Build complete (no errors) |
| `swift run ZenVoiceCoreChecks` | Pass | All checks passed (engine registry, recommendation, hotkeys, privacy, 64 languages, etc.) |
| `swift run ZenVoiceStorageChecks` | Pass | 25 checks passed |
| `swift run ZenVoiceRuntimeChecks` | Skipped | No verified model visible to CLI process; expected for this sweep |
| `./Scripts/check-ui-invariants.sh` | Pass | All 38 UI invariants hold |
| `./Scripts/check-release-readiness.sh` | Partial blockers | Fails on development signing and missing `ZENVOICE_RELEASE_MODEL_PATH`; signing/notarization of installed `/Applications/ZenVoice.app` is verified independently |

## Development manual scenarios

Run every numbered scenario in `docs/DEVELOPMENT.md#manual-qa`. Rows marked **Requires human tester** cannot be automated because they need real microphone access, Accessibility dialogs, spoken input, or visual observation.

| Scenario | Result | Evidence, issue, or notes |
|---:|---|---|
| 1 | Requires human tester | Launch `/Applications/ZenVoice.app`; confirm settings window opens and Zen logo appears in menu bar and ZenBar. |
| 2 | Requires human tester | Open History; confirm encrypted-history state is available by default. |
| 3 | Requires human tester | Pause history in Privacy, dictate once, confirm no record is added. Resume history. |
| 4 | Requires human tester | Open Shortcuts, select current shortcut, record a temporary two-modifier combination. |
| 5 | Requires human tester | Repeat for Paste last dictation and Private Dictation shortcuts. |
| 6 | Requires human tester | Enable hold-to-dictate, hold Fn, speak, release; confirm release stops recording and inserts result. |
| 7 | Requires human tester | Quit and relaunch ZenVoice; confirm all shortcut choices persisted. |
| 8 | Requires human tester | Open Privacy; confirm Microphone, Accessibility, local-history, and local-model status match System Settings. |
| 9 | Requires human tester | Open Insights; confirm totals match History. Change one record's category, confirm Insights updates. |
| 10 | Requires human tester | Open Voice Profile, add temporary correction `zen pens` → `ZenPense`, dictate phrase, confirm correction and usage count. |
| 11 | Requires human tester | Enable Private Dictation, use same phrase, confirm correction applies but usage count does not change. Disable Private Dictation and delete rule. |
| 12 | Requires human tester | On Apple Silicon, install current multilingual Whisper model, complete two consecutive dictations through ZenBar without relaunching. |
| 13 | Requires human tester | Open Insights → Share Highlights; verify preview contains only words, WPM, streak, app count. No transcript or app names. |
| 14 | Requires human tester | Save PNG (cancel), then Share… (cancel); confirm neither action happens automatically. |
| 15 | Requires human tester | Close settings window and reopen from Open ZenVoice… in menu bar. |
| 16 | Requires human tester | Open TextEdit, place cursor, press shortcut. |
| 17 | Requires human tester | Speak quietly; confirm ZenBar shows shorter waveform bars. |
| 18 | Requires human tester | Speak loudly; confirm ZenBar shows taller waveform bars. |
| 19 | Requires human tester | Select checkmark; confirm transcript is inserted into TextEdit and appears under Today in History. |
| 20 | Requires human tester | Confirm History offers Copy but no Paste, then test paste-last shortcut. |
| 21 | Requires human tester | Start again, select cancel, confirm no history record remains. |
| 22 | Requires human tester | Toggle Show Status Message from menu bar; confirm dictation message follows preference. |
| 23 | Requires human tester | Press shortcut again; confirm hotkey stop-and-insert still works. |
| 24 | Requires human tester | Disable Accessibility permission and repeat; confirm transcript is on clipboard, then restore Accessibility. |
| 25 | Requires human tester | Open Instant Refine → Clean; dictate “Create a login page, no wait, a sign-up page”; confirm only corrected sentence is pasted. |
| 26 | Requires human tester | Choose Agent Prompt; say “new paragraph”; confirm pasted prompt contains paragraph break. |
| 27 | Requires human tester | Choose Off; repeat a filler or word; confirm Instant Refine makes no additional change. |
| 28 | Requires human tester | Start a model download; confirm percentage progress. Cancel, start another download, confirm cancelled task does not clear new progress. |
| 29 | Requires human tester | Recovery Inbox: create and retry English, Hindi, and Hinglish items per `docs/DEVELOPMENT.md` scenario 32. |
| 30 | Requires human tester | Focus a password field, start dictation; confirm ZenVoice copies transcript instead of writing through secure-input fallback. |
| 31 | Requires human tester | Enter and leave native full-screen space, start dictation; confirm ZenBar follows active space. |

### Helper scripts for manual rows

- `./Scripts/reset-zenvoice-state.sh` — resets preferences, app support, keychain, and TCC approvals to simulate clean install.
- `./Scripts/run-qa-deterministic-e2e.sh [source.wav]` — launches a debug build with `ZENVOICE_E2E_AUDIO_FILE` so the microphone is bypassed with a known fixture.

## Model-runtime evidence

| Transition | Language profile | Observable evidence | Result |
|---|---|---|---|
| Start with Whisper Small (`whisper-small-multilingual`) | English | In use, Home → Model: Whisper Small, two consecutive successful dictations | Requires human tester |
| Whisper Small → current multilingual Whisper model | English | Target In use, matching Home model, two consecutive successful dictations | Requires human tester |
| Multilingual Whisper → Whisper Small without relaunching | English | Whisper Small In use, matching Home model, successful dictation | Requires human tester |
| English/Whisper Small → Auto-Detect | Auto-Detect | A compatible installed multilingual Whisper model becomes active; successful dictation | Requires human tester |
| Auto-Detect/multilingual Whisper → Whisper Small | Auto-Detect, then English | Switch & use commits Whisper Small and English together; successful dictation | Requires human tester |

## Performance and language coverage

| Coverage | Choice or profile | Model ID | Hardware | Result | Evidence or issue |
|---|---|---|---|---|---|
| Performance | Fast | `whisper-small-multilingual` | Apple M5 / macOS 27 | Requires human tester | No official speed tier configured; small model used as proxy. |
| Performance | Balanced | `whisper-large-v3-turbo` | Apple M5 / macOS 27 | Not run | Model not installed in this sweep. |
| Performance | High Accuracy | `whisper-medium-multilingual` | Apple M5 / macOS 27 | Not run | Model not installed in this sweep. |
| Language | English | `whisper-small-multilingual` | Apple M5 / macOS 27 | Requires human tester | |
| Language | Hindi | `whisper-small-multilingual` or `hindi2hinglish-apex` | Apple M5 / macOS 27 | Requires human tester | |
| Language | Auto-Detect/multilingual | `whisper-small-multilingual` | Apple M5 / macOS 27 | Requires human tester | |
| Language | Hinglish specialist | `hindi2hinglish-apex` | Apple M5 / macOS 27 | Not run | Model not installed in this sweep. |

## Additional edge cases

| Scenario | Result | Evidence, issue, or notes |
|---|---|---|
| Denied microphone permission | Requires human tester | Deny in System Settings; confirm ZenVoice shows permission error and dictation does not start. |
| Shortcut without a modifier | Pass (automated) | `ZenVoiceCoreChecks: option-only shortcuts remain valid` |
| Shortcut reserved by macOS or another app | Requires human tester | Set shortcut to `⌘Space` or similar; confirm ZenVoice warns and does not steal system shortcut. |
| Silence-only recording | Requires human tester | Start dictation without speaking; confirm graceful stop and no transcript inserted. |
| Repeated hotkey presses during transcription | Requires human tester | Press shortcut multiple times while transcribing; confirm no duplicate insertions or stuck state. |
| App relaunch | Requires human tester | Quit and relaunch; confirm settings and shortcuts persist. |
| Multiple displays and full-screen spaces | Requires human tester | Connect external display, move focus, enter full screen; confirm ZenBar follows active space. |

## Release-candidate coverage

| Area | Result | Evidence, issue, or notes |
|---|---|---|
| VoiceOver labels and announcements | Requires human tester | Enable VoiceOver, navigate settings window, confirm each control has a label. |
| Keyboard navigation | Requires human tester | Use Tab/Space/Enter to operate settings window without mouse. |
| Reduced motion | Requires human tester | Enable Reduce Motion in System Settings; confirm ZenBar and settings avoid motion. |
| Contrast | Requires human tester | Verify text and controls remain legible in both light and dark mode. |
| Full-screen and multiple-display ZenBar behavior | Requires human tester | See edge cases above. |
| Crash recovery and real lifecycle interruptions | Requires human tester | Force-quit during transcription; confirm Recovery Inbox entry on relaunch. |
| Failed-audio expiry | Requires human tester | Wait 24 hours with failed audio retained; confirm recovery audio is removed. |
| Private Dictation | Requires human tester | Enable Private Dictation; confirm no history record and no insight update. |
| Delete All | Requires human tester | Use History → Delete All; confirm all records removed and key remains intact. |
| Clipboard fallback | Requires human tester | Disable Accessibility; confirm transcript lands on clipboard. |
| Clean supported-Mac install | Requires human tester | Use `./Scripts/reset-zenvoice-state.sh` on this Mac or test on a fresh user account/Mac. |
| Microphone permission on clean install | Requires human tester | On first launch after reset, confirm macOS prompts for microphone and approval is recorded. |
| Accessibility permission on clean install | Requires human tester | On first launch after reset, confirm macOS prompts for Accessibility and insertion works after approval. |

## Privacy statement compared with observed behavior

Automated review of source and binary:
- Audio is captured locally; no cloud speech API is called by default.
- Cloud formatting is opt-in and sends only finished text + user prompt to a user-configured HTTPS endpoint.
- Transcripts are stored with AES-GCM encryption in local SQLite.
- Recovery audio is limited to ≤24 hours for failed dictations only.
- Insights are derived locally; share cards carry numeric-only payloads.

**Status:** Pass (source/binary audit). Re-confirm after manual cloud-formatting and Private Dictation tests.

## Post-catalogue runtime and model artefacts re-reviewed

- `whisper.cpp` v1.9.1 XCFramework pinned in `Package.swift` / `Package.resolved`.
- Whisper GGML model catalogue verified by `ZenVoiceCoreChecks`.
- Closed-source FluidAudio/Parakeet CoreML runtime remains removed.
- NVIDIA engines are catalogued but execution is via the open `parakeet.cpp` path; current binary contains `libparakeet.dylib` signed by Developer ID.

**Status:** Pass.

## Final result

- Overall result: **In progress — manual rows pending**
- Unresolved blockers: Manual QA rows in this record must be completed by a human tester.
- Linked issues or follow-up commits: None yet.
- Founder release approval: **Not run**

---

### How to finish this QA

1. Download the published DMG from `https://github.com/imYashChaudhary973/ZenVoice/releases/download/v0.4.4/ZenVoice.dmg` and verify its SHA-256 matches `8c7dbf30beccfe505ba0ab8ebca58d06f00bfb91d5e57de9207cc4a7535ed6b2`.
2. Drag `ZenVoice.app` to `/Applications` on a clean Mac (or run `./Scripts/reset-zenvoice-state.sh` to simulate clean install).
3. Launch the app and approve Microphone and Accessibility when prompted.
4. Complete onboarding and download the recommended model.
5. Run the numbered scenarios in `docs/DEVELOPMENT.md#manual-qa` and update the rows above with `Pass`/`Fail`/`Blocked`.
6. For deterministic non-speech regression, run `./Scripts/run-qa-deterministic-e2e.sh /path/to/16khz-mono.wav`.
7. Once every applicable row is `Pass`, update this file's final result and obtain founder approval.
