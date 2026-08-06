# Roadmap

This roadmap communicates direction, not a release promise.

The approved milestone sequence and delivery rules are tracked in
[Build Order](BUILD_ORDER.md). Accepted privacy and model constraints are
recorded in
[ADR 0001](decisions/0001-local-data-and-model-governance.md).
The strategic choice to build for internal use first and defer public shipping
is recorded in
[ADR 0004](decisions/0004-internal-use-first-defer-shipping.md).
The detailed implementation sequence for all requested features and models is
in [Phased Plan](PHASED_PLAN.md).

## Strategic direction

ZenVoice is being built first for our own daily use. Quality, reliability,
latency, and language accuracy are the current priorities. Public shipping is
deferred until the product has matured through regular personal use and a
deliberate future shipping decision is made. The release checklist and signing
pipeline remain prepared but inactive.

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
- [x] Local English transcription through Whisper
- [x] Active-app paste with clipboard fallback
- [x] ZenBar lifecycle feedback
- [x] Microphone-responsive waveform
- [x] Zen branding and packaged app icon
- [x] Verified local model catalogue, downloader, selection, and removal
- [x] Hardware-aware model recommendations and local speed benchmarks
- [x] Bundled persistent local Whisper runtime
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
- [x] Add a notch-aware, configurable live transcription overlay
- [x] Add optional local Audio History with size and age budgets and ZIP export
- [x] Add today-usage stats on Home and in the menu bar

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
- [x] Complete the M9 engineering security review
- [ ] Add Developer ID signing, notarization, and update delivery — deferred
      until a future shipping decision; see [ADR 0004](decisions/0004-internal-use-first-defer-shipping.md)
- [ ] Complete release-candidate accessibility and clean-device QA — kept as a
      quality goal for daily use; treated as a release gate only when shipping
      is reconsidered

## Product decisions

Decided on 2026-08-01:

- License: Apache License, Version 2.0, with the repository public and
  open to contributions under `LICENSE`.
- Distribution: direct download of a notarized build. The Mac App Store
  sandbox cannot host Accessibility-based insertion, which is the product.

Decided on 2026-08-05:

- Initial distribution: open-source direct download, free to users.
- Minimum supported version: Apple Silicon Macs running macOS 14 or newer.
  That is the deployment target in `Package.swift` and `LSMinimumSystemVersion`,
  so the build will launch there.
- Certified for release: macOS 27. The minimum supported version above is a
  build floor, not evidence. Only the version the release candidate was
  actually tested on may be described as certified, and macOS 14 through 26 have
  not been tested.
- The application contains no trial timer, licence key, entitlement check, or
  account system, and none is planned.

Still deferred:

- Whether non-macOS platforms belong in scope.
- When, if ever, ZenVoice resumes active public shipping. That decision
  requires a fresh review of [ADR 0004](decisions/0004-internal-use-first-defer-shipping.md),
  the state of personal-use evidence, and the release checklist in
  [Release Readiness](RELEASE_READINESS.md).
