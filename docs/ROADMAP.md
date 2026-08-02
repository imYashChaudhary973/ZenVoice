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
- [x] Local English transcription through Parakeet and Whisper
- [x] Active-app paste with clipboard fallback
- [x] ZenBar lifecycle feedback
- [x] Microphone-responsive waveform
- [x] Zen branding and packaged app icon
- [x] Verified local model catalogue, downloader, selection, and removal
- [x] Hardware-aware model recommendations and local speed benchmarks
- [x] Bundled persistent local Whisper and Parakeet runtimes
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

- [x] Keep the selected speech model loaded to reduce transcription latency
- [x] Add microphone selection, Audio Doctor, and safe disconnection handling
- [x] Add a local personal dictionary for names and technical terms
- [x] Add cancel and recover-last-dictation actions
- [ ] Improve automated and manual lifecycle coverage
- [x] Add stable partial-transcript preview and guarded commit-on-pause insertion

## Later: multilingual and distribution readiness

- [x] Add local model selection for English, multilingual, and Hinglish speech models
- [x] Add explicit language selection and optional local detection
- [x] Add local snippets and conservative voice corrections
- [x] Measure local generative refinement and remove it after it added no
  accuracy beyond deterministic rules
- [x] Add per-application language and refinement profiles
- [x] Add a memory-only next-dictation context box
- [x] Add deterministic multilingual layout and punctuation voice commands
- [x] Add explicit local learning controls without transcript comparison UI
- [x] Add a dedicated Recovery Inbox for failed and partial dictations
- [x] Add first-run onboarding and expanded permission recovery
- [ ] Add Developer ID signing, notarization, and update delivery
- [x] Complete the M9 engineering security review
- [ ] Complete release-candidate accessibility and clean-device QA

## Product decisions

Decided on 2026-08-01:

- License: proprietary, with the repository staying public as
  source-visible code under the terms in `LICENSE`.
- Distribution: direct download of a notarized build. The Mac App Store
  sandbox cannot host Accessibility-based insertion, which is the product.

Decided on 2026-08-02:

- Initial distribution: invitation-only private beta, not a paid or broad
  public launch.
- Supported baseline: Apple Silicon Macs running macOS 14 or newer.

Still deferred:

- Public pricing and launch terms after the private beta
- Whether non-macOS platforms belong in scope

The remaining decisions should be made only after the selected local speech
workflows are stable and tested through regular personal use.
