# Changelog

All notable ZenVoice changes are recorded here.

## [Unreleased]

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

### Changed

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

### Planned

- Microphone selection
- Personal dictionary and conservative local corrections

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
