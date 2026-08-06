# Changelog

All notable ZenVoice changes are recorded here.

## [Unreleased]

### Project direction

- ZenVoice is now internal-use-first. Public shipping is deferred until the
  product has matured through regular personal use and a deliberate future
  shipping decision is made. The release checklist and signing pipeline remain
  prepared but inactive.

### Changed

- Re-licensed ZenVoice under the Apache License, Version 2.0.
- Removed the closed-source FluidAudio dependency and the Parakeet CoreML
  runtime. ZenVoice now uses `whisper.cpp` as its only local speech engine.
- Retired the Parakeet Unified EN CoreML model from the active catalogue; it
  remains resolvable so existing installations do not break.
- Updated English model recommendations on Apple Silicon to Whisper Large v3
  Turbo.

### Removed

- FluidAudio package dependency and all Parakeet/CoreML runtime code.
- Multi-file bundle download, manifest digest, and bundle verification logic.

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
