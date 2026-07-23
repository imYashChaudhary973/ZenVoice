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
- [x] Verified local model catalogue, downloader, selection, and removal
- [x] Hardware-aware model recommendations and local speed benchmarks
- [x] Bundled persistent `whisper.cpp` runtime
- [x] Private local insights, streaks, app usage, and editable categories
- [x] Local voice profile and encrypted explicit correction rules
- [x] Privacy-safe local highlight cards with preview and explicit export
- [x] macOS CI and Semgrep Community Edition security scanning
- [x] Third-party notices and fail-closed release-readiness checks
- [x] Deterministic Instant Refine with Clean and Agent Prompt modes
- [x] Visible model-download progress and cancellation isolation
- [x] Explicit English-safe language selection with 64 local languages
- [x] Hinglish Latin-script, native-script, and English-translation outputs

## Next: quality and daily reliability

- [x] Keep the Whisper model loaded to reduce transcription latency
- [ ] Add microphone selection and disconnection handling
- [x] Add a local personal dictionary for names and technical terms
- [x] Add cancel and recover-last-dictation actions
- [ ] Improve automated and manual lifecycle coverage
- [ ] Add stable partial-transcript preview and commit-on-pause insertion

## Later: multilingual and distribution readiness

- [x] Add local model selection for English and multilingual Whisper models
- [x] Add explicit language selection and optional local detection
- [x] Add local snippets and conservative voice corrections
- [ ] Evaluate optional local-only rewriting through Ollama
- [ ] Curate downloadable local text-refinement models with meaning guards
- [ ] Add first-run onboarding and expanded permission recovery
- [ ] Add Developer ID signing, notarization, and update delivery
- [x] Complete the M9 engineering security review
- [ ] Complete release-candidate accessibility and clean-device QA

## Product decisions intentionally deferred

- Public versus private-source distribution
- Free versus paid pricing
- License choice
- Supported macOS hardware and minimum version
- Whether non-macOS platforms belong in scope

These decisions should be made only after the local English workflow is stable
and tested through regular personal use.
