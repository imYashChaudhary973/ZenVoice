# Changelog

All notable ZenVoice changes are recorded here.

## [Unreleased]

## [0.4.2] - 2026-08-27

### Added

- Engine downloads in Models now show a determinate progress bar and a
  percentage/verifying caption, matching the existing Whisper model download
  experience.
- Models engine rows show a "Recommended" badge for the engine that best fits
  this Mac and the selected language.
- The onboarding model step now surfaces the recommended engine with its
  rationale and offers a one-tap "Use recommended engine" action.

### Changed

- "Browse all 64 languages" on the Languages screen is now a full-width tappable
  card; the whole row expands or collapses the list, not just the disclosure
  arrow.
- Onboarding is now strict: the "Skip setup" button is gone, and Continue is
  disabled until each step's requirement is met. Permissions must be granted,
  and the recommended model must be downloaded and verified before the user
  can finish setup.
- Onboarding cards, rows, and buttons now use the same shared components and
  design tokens as the rest of the app (`ZenPanel`, `ZenRow`, `ZenIconChip`,
  `ZenBadge`, `ZenPrimaryButtonStyle`, etc.).


## [0.4.1] - 2026-08-27


## [0.4.0] - 2026-08-27



### Added

- Offline lecture capture (Phase 1): start / pause / resume / stop in
  History → Lectures. Writes a local 16 kHz mono WAV, shows elapsed time,
  stops at 90 minutes, and keeps a partial file as incomplete on quit.
- Lecture Stop transcribes the whole file with the selected local engine.
  The original transcript is encrypted and copyable. Failed decode keeps
  the audio and shows Retry. Nothing is pasted into another app.
- History → Lectures lists each lecture with title, duration, engine, and
  status. Open, copy original, retry transcribe, and hold-to-delete. Separate
  from dictation History. Audio stays on disk, not in SQLite.
- Optional lecture summaries use the existing BYO-key Cloud path and a fixed
  outline / key terms / questions prompt. Original and encrypted summary are
  shown side by side; provider failures leave the original untouched.
- Lecture controls retain 44pt targets and shared Reduce Motion behavior.
  Privacy & Data now reports lecture count and audio disk usage. Lifecycle
  checks cover capacity refusal, encrypted original / summary isolation, and
  deletion of both WAV and sidecar.

### Changed

- Painted buttons, icon buttons, and menu-picker triggers use Opensource UI
  3D keycaps (lift + sheen, press sinks). Native menus, switches, and fields
  stay native.
- History, recordings, privacy, and vocabulary bulk deletes now use
  hold-to-delete. Transcript rows use the copy-confirm button and a 3D kebab.
- Personalisation copy is shorter. Cloud prompt uses the labelled textarea.
  Stored API keys expose Replace. Tab strips slide. Toolbar search is a
  field on the right. Dictation has a square reset control.
- Row icons, shortcut chips, and history status marks use 3D keycaps.
- Models lists every engine-linked checkpoint. A mismatched Use stays put
  and shows a red 3D system alert. Only Whisper can pick among four files.
- Models names the official NVIDIA checkpoint each engine wraps.
- History delete is a normal button beside search. Replay setup is gone
  after first launch.

## [0.3.1] - 2026-08-21

Re-cut of the public GitHub beta with Command Mode / Agentic Mode removed from
the shipped product surface. It remains compiled behind the scenes but is
force-disabled on launch and not exposed in settings.

### Project direction

- First public download: GitHub Releases. File bugs there. This is a beta, not
  a 1.0. Agentic Mode, Command Mode, and Cloud formatting stay off unless you
  turn them on; the first two are not reachable in this build.

### Changed


- Removed a one-second settings poll that SHA-256 hashed the selected model on
  the main actor. Model verification now stays on the load/download boundary,
  engine discovery runs off the main actor, and short deterministic dictation
  has a 1.5-second stop-to-complete gate.
- Serialized Whisper warm-up, preview, final decode, and release; obsolete
  preview work is cancellation-aware so final insertion is not queued behind
  it. Local text is inserted before optional cloud enhancement.
- Unified engine and Whisper-model selection. The Home screen reports the
  resolved engine, legacy model selections migrate to Whisper, and all verified
  engines are visible without an “Advanced” disclosure.
- Reworked the app shell into seven flat destinations with separate Language
  and Models screens, restored system light/dark appearance and 900-point
  window support, and added versioned Liquid Glass to toolbar and floating
  dictation controls on macOS 26 and newer.
- Aligned shortcut, toolbar, search, and destructive controls; added a hold-key
  icon; made preview overlays display-responsive; and introduced shared glass
  tabs, menu selectors, and text inputs across Personalisation, Language,
  providers, History, and Settings inventory.
- Fixed fast process-exit status races and Link transport handshake, replay
  ordering, timeout, and subscriber teardown failures. Core, Link, runtime, UI,
  and deterministic app checks now form the behavioral release gate.
- Re-licensed ZenVoice under the Apache License, Version 2.0.
- Removed the closed-source FluidAudio dependency and the Parakeet Unified
  CoreML runtime. NVIDIA engines now run on open `parakeet.cpp` v0.5.0.
  Active local engines: Whisper (`whisper.cpp` v1.9.1), Apple Speech,
  Parakeet TDT v2/v3, Parakeet Flash, Nemotron 3.5, and Cohere Transcribe
  (on-device ONNX). Do not re-add FluidAudio or Fluid Intelligence.
- Retired the Parakeet Unified EN CoreML model from the active catalogue; it
  remains resolvable so existing installations do not break.
- Whisper Tiny and Base stay retired. The multilingual size ladder is a cliff
  (Tiny 64.5% WER, Base 55.1%), not a speed tier.
- One recommender, from the 2026-08-18 Common Voice Spontaneous table:
  English/European → Parakeet TDT v3; 99-language/auto-detect → Whisper Turbo;
  Hinglish → Apex; zero-download fallback → Apple Speech; Intel → Whisper Small
  (compromise). Cohere is local, off by default, and labeled as a slower 3 GB
  option. Flash and Nemotron Ultra Fast are live-preview only; final insert
  stays TDT v3 or Turbo. Nemotron is one row with a Streaming/Offline toggle.
- Adopted the apple-design visual system as the product theme: ink canvas,
  one jade accent, vibrancy materials, and springs. The accent is reserved
  for three jobs — selected navigation, the primary action, and live state —
  and nowhere else. Surfaces are separated by a lit top edge plus a shadow;
  hairlines are the fallback, not the structure. Type spans 11 to 34 with
  per-size tracking. The settings window and all twenty-six screens compose
  from `ZenDesignTokens`, `ZenChrome`, and `ZenV2Components`, so this is the
  vocabulary new UI must use.
- Selected navigation is a quiet `accentMuted` row with an accent icon rather
  than a filled green pill. The filled pill was the loudest mark in a window
  that stays open all day, and it shouted its own state louder than the
  setting the user opened it to change.
- ZenBar at rest is a 108×36 capsule (brand mark + flat level meter). Controls
  reveal on hover. The bar follows the display of the focused app.

- First-run setup is six steps instead of seven, and every one of them either
  asks for something or hands something back: the promise page and the privacy
  page were two consecutive pages of reading before the user could do anything,
  and are now one. The header names the current step and counts them, so the
  length of the flow is visible from the first screen.
- History retention is now enforced. `HistoryPreferences.retentionDays` was
  stored and read by nothing: no code path purged old dictations, so an
  encrypted vault grew for as long as the app was used. Launch now discards
  records older than the retention window.
- Agentic shell steps classify risk from the whole command surface. A
  read-only prefix no longer buys a `low` rating when the command also
  contains a separator, substitution, or redirection, so `ls; rm -rf x` and
  `cat a > b` are no longer eligible for blanket plan approval. Working
  directories resolve symlinks before the `~/Developer` containment check.
- Plan dependencies must reference earlier steps. The orchestrator runs steps
  in order, so a forward dependency silently skipped the earlier step; cycles
  are now impossible by construction rather than detected separately.
- Whisper live-preview fragments decode on the engine's own serial queue.
  They previously ran on a second queue, which could put two `whisper_full`
  calls on one context at the same time.

### Removed

- FluidAudio package dependency and all Parakeet/CoreML runtime code.
- Multi-file bundle download, manifest digest, and bundle verification logic.
- Command Mode's unreachable action branch: `runShortcut`, `appleScript`,
  `shellScript`, and `openURL` were never produced by the parser and their
  first-run approval could never be granted, so the actions, the approval
  store, and their executor methods are gone. Multi-step and script execution
  belongs to Agentic Mode's plan-approval pipeline.
- Unused declarations: `EmptyWriteModeTextReader`,
  `RecordingCommandModeExecutor`, `ZenSegmentedControl`,
  `GoalOrchestrator.currentRecord`, `SecretRedactor.containsSecret`,
  `LinkClient.stopObserving`, and `LinkServer.setPolicy`.
- Superseded documentation: dated QA records, benchmark and fine-tuning
  experiment write-ups, finished remediation and implementation plans, the
  open-source strategic plan, the orphaned `docs/hinglish/` workstream, and
  stale PDF/HTML exports. Git history keeps them; `docs/` describes the
  product as it is now.

## [0.2.0] - 2026-08-03

First build distributed outside the author's machine, as an invitation-only
private beta. Free to its users for an initial one to three month period. There
is no trial timer, licence key, or account system in the application.

Certified on macOS 27 on Apple Silicon. The build targets macOS 14 or newer,
but no earlier version has been tested; see
[Release Readiness](docs/RELEASE_READINESS.md).

### Added

- Added a native ZenVoice window with Overview, Shortcuts, and Privacy screens
- Added a recorder for choosing a custom global dictation shortcut
- Persisted the chosen shortcut locally and applied it without an app restart
- Added live Microphone, Accessibility, and local-model status
- Added an **Open ZenVoice…** command to the menu-bar menu
- Added explicit opt-in encrypted transcript history backed by native SQLite,
  AES-GCM, and a Keychain-protected key
- Added crash and failed-transcription recovery with optional 24-hour audio
  retention
- Added History search, copy, paste, retry, per-record deletion, and
  cryptographic Delete All
- Added Private Dictation mode and local-history privacy controls
- Added a configurable paste-last shortcut, defaulting to
  `Control + Option + V`
- Added a verified English and multilingual model catalogue with checksum
  validation, hardware recommendations, and local speed benchmarks
- Added a checksum-pinned `whisper.cpp` v1.9.1 runtime inside the app
- Added on-device insights for total words, weighted WPM, streaks, recent
  activity, distinct apps, and work categories
- Added conservative app-category detection and user correction from History
- Added a local language-usage profile with frequent words, recurring phrases,
  and the most active hour
- Added encrypted explicit correction rules with whole-phrase matching and
  history-bound usage counts
- Added locally rendered 1200×630 highlight cards with an exact preview,
  numeric-only payload, Save PNG, and explicit macOS sharing
- Added macOS CI for core, storage, runtime, package, and nested-signature
  verification
- Added token-free Semgrep Community Edition scanning for pull requests and
  `main`
- Added third-party notices, an M9 security review, and a fail-closed public
  release checklist
- Added local Instant Refine modes for conservative cleanup and explicit
  agent-prompt layout commands
- Added a meaning guard that rejects destructive or vocabulary-expanding
  automatic refinement
- Added visible model-download percentage and isolated cancellation state
- Added M11 explicit language profiles with 64 supported Whisper language codes
- Added an English-safe default, a Hinglish Latin-script preset, local English
  translation, and native-script output modes
- Added language/model compatibility guards and menu-bar quick profiles
- Added selectable microphone routing with a System Default option
- Added a three-second local Audio Doctor with signal and file-format checks
- Added safe active-device disconnection handling with existing recovery rules
- Added stable phrase detection and local in-memory Whisper previews
- Added opt-in commit-on-pause insertion locked to the original target app
- Added encrypted partial transcript checkpoints during active dictation
- Added application profiles that select language, refinement mode, and local
  voice-command behavior from the original target app
- Added a bounded memory-only context box for the next dictation
- Added deterministic layout and punctuation commands with English controls
  plus Hindi, Spanish, French, Mandarin, and Arabic aliases
- Added controls to pause correction rules, pause history pattern analysis,
  and delete all correction rules without deleting transcripts
- Added a Recovery Inbox filter for failed and usable partial dictations
- Added first-run onboarding that existing ZenVoice installs can reopen from
  Overview without being forced through setup again
- Added a local privacy inventory with confirmed recovery-audio deletion
- Added Reduce Motion support and explicit success announcements to ZenBar
- Added the NVIDIA Parakeet CoreML runtime through the revision-pinned
  FluidAudio dependency, and made it the recommended English path
  _(removed in a later release; see Unreleased)_
- Added a ZenBar warning when the decoder repeats itself, so a looped
  transcript is visible rather than silently pasted
- Added the Developer ID pipeline: secure-timestamped signing, a notarization
  and stapling script, and a distribution archive with a printed SHA-256
- Added `LICENSE` as proprietary, source-visible software
  _(later re-licensed as Apache-2.0; see Unreleased)_

### Removed

- Removed Correction Review and stopped Voice Profile from loading raw and
  final transcript pairs solely for comparison.
- Removed the downloadable local refinement path before it ever shipped. The
  Qwen2.5 refinement models, the `llama.cpp` runtime, and grammar-constrained
  JSON refinement were measured against deterministic Clean, scored the same
  word error rate while being rejected by the meaning guard roughly half the
  time, and were withdrawn rather than kept for their inference cost. Instant
  Refine keeps its deterministic Off, Clean, and Agent Prompt modes, and no
  refinement weights are downloaded or loaded.

### Changed

- Redesigned Overview around actionable readiness, private local activity, and
  direct navigation to the setting that needs attention.
- Made model rows adapt at compact window widths while keeping Use, Remove,
  Download, and status controls aligned.
- Clarified custom-shortcut capture with explicit Change and Cancel states,
  including shortcut personalization during setup.
- Corrected hold-to-dictate modifier press and release detection and added
  actionable Accessibility feedback for global use.
- Kept the setup guide automatic for fresh installs, dismissible once, and
  manually reopenable without forcing returning users through it again.
- Standardized the native SF Pro hierarchy and removed inconsistent rounded
  text variants.
- Displayed the active dictation shortcut in the menu-bar action
- Reduced ZenBar to a compact bottom-edge control strip
- Added cancel and finish controls during dictation
- Added an optional “Dictating with ZenVoice” message
- Refined the microphone-responsive waveform
- Positioned ZenBar on the display containing the active application
- Signed local builds with a stable Apple Development identity so macOS privacy
  permissions survive normal rebuilds
- Opened the correct macOS microphone settings page when permission is denied
- Added the required Hardened Runtime audio-input entitlement
- Reused the loaded model between dictations instead of launching
  `whisper-cli` for every recording
- Applied Instant Refine before encrypted personal correction rules, history,
  and paste

### Fixed

- Fixed retained recovery audio outliving the stated 24-hour window. Two
  failure paths never armed the expiry timer, and the fallback was measured
  from the failure rather than from the start of capture.
- Fixed Insights counting dictations that never completed. A force-quit
  dictation kept its live-preview partial and was later marked failed with zero
  duration, inflating word totals, streak days, and weighted words per minute.
- Fixed the Parakeet bundle being fetched from a moving branch while the
  catalogue recorded a pinned revision. Each file is now downloaded from that
  revision, checked against an exact manifest, and installed atomically.
  _(the Parakeet path was later removed entirely; see Unreleased)_
- Fixed third-party notices omitting components compiled into the shipped
  binary, including fastcluster, whose licence requires its notice in binary
  redistributions.
  _(those components left with the FluidAudio removal; see Unreleased)_
- Fixed a signing-identity check that rejected a valid Developer ID signature,
  and a matching one that could sign a release without a secure timestamp.

## [0.1.0] - 2026-07-23

### Added

- Native macOS menu-bar application
- Global `Control + Option + Space` dictation shortcut
- Local English transcription through `whisper.cpp`
- ZenBar with lifecycle and error feedback
- Microphone-responsive waveform metering
- Zen logo in ZenBar, the menu bar, and the application icon
- Clipboard fallback when automatic paste permission is unavailable
- Local transcript cleanup and deterministic core checks
