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

### Planned

- Lower-latency persistent local transcription
- Microphone selection
- Personal dictionary and multilingual models

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
