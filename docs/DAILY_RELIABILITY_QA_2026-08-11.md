# Daily Reliability QA — 2026-08-11

**Status:** In progress. This is development QA, not release certification.

This record tracks the open daily-reliability work in
[`ROADMAP.md`](ROADMAP.md) and the complete manual list in
[`DEVELOPMENT.md`](DEVELOPMENT.md). It contains no transcript text, API keys,
or private application content.

Use only `Pass`, `Fail`, `Blocked`, `Not run`, or `Not applicable` in result
columns. A narrow automated check does not convert a broader manual scenario
to `Pass`.

## Tested build and Mac

| Field | Evidence |
|---|---|
| Source branch | `feature/phase-6-product-and-interface` |
| Source commit | `5393814a0b3f7ff72fa486ae44671a91e8c0ecd2` plus the recorded dirty worktree |
| App | `build/ZenVoice.app` |
| Executable SHA-256 | `e27b2614fe7dfb2539dcfd37c751e0eab4619f3a77355a500e800954d64d69d4` |
| Bundle identity | `dev.yashchaudhary.ZenVoice`, team `8QSM298XJ2`, Hardened Runtime |
| Build result | `Scripts/build-app.sh` passed with Apple Development signing |
| Independent signature verification | Fail: `codesign --verify --deep --strict` returns `CSSMERR_TP_NOT_TRUSTED` for arm64; local launch still succeeds |
| Mac | MacBook Pro `Mac17,2`, Apple M5, 10 cores, 24 GB |
| macOS | 27.0 build `26A5388g` |
| Displays | Built-in 3024×1964 plus two online 1920×1080 displays |
| Inputs | Built-in MacBook Pro microphone and one USB audio input |
| Installed speech model exercised | Whisper Turbo, `whisper-large-v3-turbo` |

The source tree is intentionally dirty because this phase is still under
development. This artifact must not be described as a release candidate.

## Automated lifecycle evidence

| Check | Result | Evidence |
|---|---|---|
| Core policies | Pass | `swift run ZenVoiceCoreChecks`; includes live-preview strategy, secure-input policy, engine selection, command/Write Mode policies, and cloud request handling |
| Cancellation propagation | Pass | New prepare/transcribe checks prove `CancellationError` is not converted into a generic engine failure |
| Runtime engine fallback | Pass | New checks prove prepare/transcribe advance from a failing selected engine to the ordered fallback, report the final failure when all candidates fail, and never fallback after user cancellation |
| Cloud local-transcript retention | Pass | New policy checks prove dismiss, timeout-equivalent `nil`, and blank output retain the exact local transcript; only non-empty accepted text replaces it |
| Encrypted storage lifecycle | Pass | `swift run ZenVoiceStorageChecks`: 22 checks, including interruption recovery, expiry, cancellation cleanup, private suppression, scoped deletion, and archives |
| Real runtime lifecycle | Pass | `swift run ZenVoiceRuntimeChecks` with verified Whisper Turbo: two decodes, unload/reload, 598 MB reclaimed |
| Full compile | Pass | `swift build` passed; only pre-existing Apple locale deprecation warnings |
| Signed app build | Pass | `Scripts/build-app.sh` passed and rebuilt `build/ZenVoice.app` |

## Older milestone acceptance

| Requirement | Result | Evidence or remaining work |
|---|---|---|
| Whisper real-microphone English | Pass | Built-in microphone decoded non-sensitive English with Whisper Turbo and inserted it into a real BridgeSpace text field |
| Apple Speech on-device and fallback | Not run | Ordered failure fallback is now covered; live Apple on-device recognition and unavailable-locale fallback remain |
| Engine cancellation | Pass | Regression fixed and covered by Core checks |
| Recovery audio | Pass | Storage checks cover interruption, retention, expiry, confinement, and deletion; real force-quit retry remains in the manual matrix |
| Live preview lifecycle | Not run | Pure strategy/preferences pass; spoken preview and replacement behavior remain |
| Real-mic Hindi | Not run | Requires a spoken Hindi run |
| Real-mic Auto-Detect | Not run | Requires a spoken multilingual run |
| Real-mic Hinglish | Not run | Specialist model is not installed; compatible multilingual fallback still needs a spoken run |
| Physical microphone disconnection | Fail | macOS CoreAudio reports the connected `USBAudio1.0` input, but ZenVoice's `AVCaptureDevice` catalogue exposes only the built-in microphone; an external device cannot be pinned and unplugged through the current capture path |
| Audio Doctor | Pass | Pinned built-in microphone completed the three-second local check at 21% signal, reported “Microphone sounds good,” and left no temporary WAV in Application Support |
| Commit on pause | Not run | Preference/strategy checks pass; spoken insertion remains |
| Voice command across apps | Not run | Parser/executor policy passes; real app execution remains |
| Write Mode across apps | Not run | Rewrite policy passes; real selection/rewrite remains |
| Command/rewrite announcements | Not run | Requires VoiceOver observation |
| Recovery retries: English/Hindi/Hinglish | Not run | Storage lifecycle passes; three real force-quit/retry flows remain |
| Overlay sizes and positioning | Not run | Pill, medium, and large settings each selected and rendered the correct preview description; live notch/non-notch and multi-display positioning remain |
| Audio History budget/deletion/playback/ZIP | Not run | Storage/archive policies pass; UI playback, budgets, scoped deletion, and ZIP inspection remain |
| Today stats and Private Dictation exclusion | Pass | During the live private run, metadata stayed at 3 records and 11 words for that day; no suppressed placeholder row was written |
| VoiceOver/keyboard/motion/contrast | Not run | Overlay Reduce Motion toggled on/off and restored; OS Reduce Motion behavior plus VoiceOver, keyboard, and contrast sweeps remain |
| Full-screen/multiple displays | Not run | Three displays are online; placement and Space-following behavior remain |

## Development manual scenarios

| # | Result | Evidence, issue, or remaining work |
|---:|---|---|
| 1 | Pass | Rebuilt and launched `build/ZenVoice.app` |
| 2 | Not run | Settings window opened; menu-bar logo and ZenBar presence were not separately recorded |
| 3 | Pass | History UI reported encrypted local history; database contains encrypted transcript blobs |
| 4 | Not run | History pause/resume and no-record assertion remain |
| 5 | Not run | Temporary start/stop shortcut recording remains |
| 6 | Not run | Paste-last and Private Dictation shortcut recording remains |
| 7 | Not run | Hold-Fn start/release/insert remains |
| 8 | Not run | App relaunch passed, but scenarios 5–6 shortcut persistence was not established |
| 9 | Pass | Privacy showed Microphone and Accessibility allowed and one verified local model installed, matching observed state |
| 10 | Not run | History category change and Insights reconciliation remain |
| 11 | Not run | Temporary correction, real-mic use, and usage increment remain |
| 12 | Not run | Private Dictation exclusion passed; correction application and unchanged rule usage remain |
| 13 | Not run | Verified model was exercised repeatedly, but two consecutive ZenBar completions were not recorded as one controlled run |
| 14 | Not run | Privacy-safe payload passes Core checks; Share Highlights preview remains |
| 15 | Not run | Save PNG cancellation and Share cancellation remain |
| 16 | Not run | Relaunch passed; close then reopen from the status menu remains |
| 17 | Pass | TextEdit document and editable caret were opened |
| 18 | Blocked | Computer-control key injection inserts Option-Space as text instead of invoking the global hotkey; needs one physical keypress |
| 19 | Not run | Quiet-speech waveform comparison remains |
| 20 | Not run | Loud-speech waveform comparison remains |
| 21 | Not run | Cross-app insertion passed, but the ZenBar checkmark path and Today History assertion remain |
| 22 | Not run | History Copy/no-Paste inspection and paste-last shortcut remain |
| 23 | Not run | Cancel-with-no-record flow remains |
| 24 | Not run | Status Message preference toggle remains |
| 25 | Not run | Global hotkey stop-and-insert needs a physical keypress |
| 26 | Not run | Accessibility permission disable test requires an explicit security-setting change |
| 27 | Not run | Clipboard fallback and permission restoration remain |
| 28 | Not run | Clean mode spoken self-correction remains |
| 29 | Not run | Agent Prompt paragraph command remains |
| 30 | Not run | Off-mode spoken baseline comparison remains |
| 31 | Not run | Real download cancel/restart remains; do not spend bandwidth without an intentional test window |
| 32 | Not run | English, Hindi, and Hinglish force-quit/retry runs remain |
| 33 | Not run | Fail-closed policy passes; a real password-field run remains |
| 34 | Not run | Native full-screen active-Space following remains |

## Additional edge cases

| Scenario | Result | Evidence or remaining work |
|---|---|---|
| Denied microphone permission | Not run | Requires an explicit security-setting change |
| Shortcut without modifier | Not run | Validation policy passes; UI rejection remains |
| Shortcut reserved by macOS/another app | Not run | UI conflict handling remains |
| Silence-only recording | Not run | Runtime no-speech handling passes; app lifecycle remains |
| Repeated hotkeys during transcription | Not run | Requires physical global hotkey input |
| App relaunch | Pass | Idle app terminated, rebuilt, and relaunched with history/preferences intact |
| Multiple displays and full-screen spaces | Not run | Three online displays detected; behavior remains |

## Phase 6 interface acceptance

| Requirement | Result | Evidence or remaining work |
|---|---|---|
| Nine distinct destinations | Pass | Home, Dictation, Languages & Models, Formatting, Commands, Personal, History, Privacy & Data, and Help & About each selected and exposed distinct content |
| No dead/no-op controls | Pass | UI invariant check plus accessibility-tree sweep found no borrowed title actions or obvious dead controls |
| Consistent grid/alignment | Not run | Source invariant passes; resize and multi-screen visual sweep remains |
| Empty states | Not run | Empty-state source coverage exists; each empty dataset was not induced manually |
| Light/dark appearance | Pass | Dark → System → Light → Dark cycled successfully and original Dark preference was restored |
| Window lifecycle | Not run | Launch/relaunch passes; close and status-menu reopen remains |
| Cloud preview keeps local transcript | Pass | Fail-closed resolution is wired into AppDelegate and covered for dismiss/blank/accept; no provider request was made |
| Secure input fails closed | Pass | Core policy rejects secure and ambiguous fields; real password-field observation remains scenario 33 |

## Cleanup and remaining gates

- One non-sensitive QA history record remains because repeated UI invalidation
  prevented a reliably scoped Delete action. It is uniquely identifiable by
  its test time and 11-word metadata. Do not use Delete All.
- The isolated QA settings were restored and verified after relaunch: Private
  Dictation `off`, Formatting `Cloud`, and English engine Nemotron Speech 3.5
  Ultra Fast.
- Restore the original speech engine again after future Apple Speech/fallback
  testing.
- Do not check off `ROADMAP.md` lifecycle coverage until every applicable
  manual row above passes or has an approved, documented scope exclusion.
- Repair or replace the untrusted Apple Development certificate chain before
  treating a future artifact as signature-verified.
- Add a CoreAudio-compatible external-input capture path. The current
  `AVCaptureDevice` catalogue cannot see the connected USB input, so M12's
  selection/disconnection claim is incomplete on this Mac.

## Current conclusion

Automated lifecycle coverage improved and the first real-microphone,
real-application Whisper path passes. The phase exit condition is not yet met:
Apple Speech, three language profiles, hardware disconnection, Recovery Inbox,
commands/Write Mode, accessibility, Audio History, overlays, and most of the 34
manual scenarios still require live evidence.
