# Changelog

All notable ZenVoice changes are recorded here.

## [Unreleased]

### Changed

- Reduced ZenBar to a compact bottom-edge control strip
- Added cancel and finish controls during dictation
- Added an optional “Dictating with ZenVoice” message
- Refined the microphone-responsive waveform
- Positioned ZenBar on the display containing the active application
- Signed local builds with a stable Apple Development identity so macOS privacy
  permissions survive normal rebuilds

### Planned

- Lower-latency persistent local transcription
- Configurable shortcuts and microphone selection
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
