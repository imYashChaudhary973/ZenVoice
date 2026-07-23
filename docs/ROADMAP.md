# Roadmap

This roadmap communicates direction, not a release promise.

## Current: dependable personal alpha

- [x] Native macOS menu-bar application
- [x] Global dictation hotkey
- [x] Native settings window
- [x] Configurable and persistent dictation shortcut
- [x] Live permission and local-model status
- [x] Local English Whisper transcription
- [x] Active-app paste with clipboard fallback
- [x] ZenBar lifecycle feedback
- [x] Microphone-responsive waveform
- [x] Zen branding and packaged app icon

## Next: quality and daily reliability

- [ ] Keep the Whisper model loaded to reduce transcription latency
- [ ] Add microphone selection and disconnection handling
- [ ] Add a local personal dictionary for names and technical terms
- [ ] Add cancel and recover-last-recording actions
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
