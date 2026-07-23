# Roadmap

This roadmap communicates direction, not a release promise.

The approved milestone sequence and delivery rules are tracked in
[Build Order](BUILD_ORDER.md). Accepted privacy and model constraints are
recorded in
[ADR 0001](decisions/0001-local-data-and-model-governance.md).

## Current: dependable personal alpha

- [x] Native macOS menu-bar application
- [x] Global dictation hotkey
- [x] Native settings window
- [x] Configurable and persistent dictation shortcut
- [x] Live permission and local-model status
- [x] Encrypted local transcript history with a pause control
- [x] Interrupted-transcription recovery records
- [x] Search, copy, retry, and delete history actions
- [x] Configurable paste-last shortcut
- [x] Configurable Private Dictation shortcut
- [x] Hold-to-dictate with Fn or a right-side modifier
- [x] Local English Whisper transcription
- [x] Active-app paste with clipboard fallback
- [x] ZenBar lifecycle feedback
- [x] Microphone-responsive waveform
- [x] Zen branding and packaged app icon

## Next: quality and daily reliability

- [ ] Keep the Whisper model loaded to reduce transcription latency
- [ ] Add microphone selection and disconnection handling
- [ ] Add a local personal dictionary for names and technical terms
- [x] Add cancel and recover-last-dictation actions
- [ ] Improve automated and manual lifecycle coverage

## Later: multilingual and distribution readiness

- [ ] Add local model selection for English and multilingual Whisper models
- [ ] Add explicit language selection and optional local detection
- [ ] Add local snippets and conservative voice corrections
- [ ] Evaluate optional local-only rewriting through Ollama
- [ ] Add first-run onboarding and expanded permission recovery
- [ ] Add Developer ID signing, notarization, and update delivery
- [ ] Complete accessibility and security reviews

## Product decisions intentionally deferred

- Public versus private-source distribution
- Free versus paid pricing
- License choice
- Supported macOS hardware and minimum version
- Whether non-macOS platforms belong in scope

These decisions should be made only after the local English workflow is stable
and tested through regular personal use.
