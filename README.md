<p align="center">
  <img src="Resources/Brand/ZenLogo.png" width="120" alt="ZenVoice logo">
</p>

<h1 align="center">ZenVoice</h1>

<p align="center">
  Private, local-first voice dictation for macOS.
  Speak naturally, transcribe on-device, and paste into any app.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111">
  <img alt="Swift 5.10" src="https://img.shields.io/badge/Swift-5.10-F05138">
  <img alt="Local-first" src="https://img.shields.io/badge/Privacy-Local--first-C5A36A">
  <img alt="Apache-2.0" src="https://img.shields.io/badge/License-Apache--2.0-1abc9c.svg">
</p>

ZenVoice is a native macOS app inspired by the speed of modern voice dictation
tools while keeping transcription, temporary audio, and configuration on your
Mac. Its ZenBar stays close at hand, while a dedicated settings window provides
clear controls and live system status. There are no accounts, subscriptions,
analytics, or cloud transcription services in the current application.

> [!IMPORTANT]
> ZenVoice is open-source software licensed under the Apache License, Version
> 2.0 (see [LICENSE](LICENSE)). The project welcomes contributions; see
> [Contributing](CONTRIBUTING.md). ZenVoice builds for macOS 14 or newer.
> There is no account system, subscription, or cloud transcription service.

## What works today

- A native settings window with Overview, Models, History, Insights,
  Shortcuts, and Privacy screens.
- A configurable global dictation shortcut, defaulting to
  `Control + Option + Space`.
- Encrypted local history by default, including usable partial transcriptions.
- Private local insights for words, weighted WPM, streaks, apps, and work
  categories.
- A local language-usage profile with recurring phrases and encrypted explicit
  correction rules.
- Previewed, locally rendered highlight cards with explicit Save and macOS
  Share actions.
- Copy, retry, search, and delete controls for saved dictations.
- A configurable `Control + Option + V` shortcut for pasting the latest
  dictation.
- Configurable Private Dictation (`Control + Option + P`) and hold-to-dictate
  controls.
- Verified English, multilingual, and Hinglish-specialist model downloads with
  pinned revisions and SHA-256 validation.
- Explicit English-safe language profiles with 64 selectable languages.
- Hinglish Latin-script output plus native-script and local English-translation
  modes for multilingual dictation.
- Selectable microphones, safe disconnection handling, and a three-second
  on-device Audio Doctor.
- Stable local phrase preview in ZenBar and optional guarded commit-on-pause
  insertion.
- Hardware-aware Fast, Balanced, and High Accuracy recommendations backed by
  private local timing samples.
- Unified Formatting ladder: Off, deterministic Clean, guarded on-device Smart,
  and explicit BYO-key Cloud.
- Per-application language, refinement, and voice-command profiles.
- A memory-only context box for names and topic hints that clears when the
  next recording starts.
- Local layout and punctuation commands with English controls plus Hindi,
  Spanish, French, Mandarin, and Arabic aliases.
- Optional Agentic Mode, off by default: a spoken multi-step goal becomes a
  reviewable plan that runs only after you approve those exact steps, with
  local planning, recomputed per-step risk, live ZenBar progress, and a Stop
  control.
- Explicit controls to pause personal rules or local pattern analysis and to
  delete correction rules independently from History.
- A Recovery Inbox for failed and usable partial dictations with Copy, Retry,
  and Delete actions.
- Upgrade-safe first-run onboarding with plain-language privacy, permission,
  shortcut, language, and model guidance.
- A live privacy inventory for encrypted transcripts, recovery audio,
  correction rules, and installed local models.
- Reduce Motion-aware ZenBar animation and clearer assistive-technology status
  labels.
- Meaning-preserving cleanup for fillers, repeated words, spoken restarts, and
  explicit prompt layout commands.
- Visible model-download percentage with reliable cancellation.
- Local transcription through `whisper.cpp`.
- Compact ZenBar feedback for ready, listening, processing, success, and error
  states.
- A live waveform driven by real microphone loudness.
- Listening controls to cancel or finish dictation without the hotkey.
- An optional “Dictating with ZenVoice” status message.
- Automatic paste into the active app with clipboard fallback.
- Temporary audio cleanup after each transcription attempt.
- Native Zen branding in ZenBar, the menu bar, and the application icon.

## How it works

```text
Hotkey
  → local microphone recording
  → app profile + optional one-shot context
  → selected local whisper.cpp model
  → conservative transcript cleanup
  → deterministic local refinement
  → macOS clipboard and active-app paste
```

The settings interface, ZenBar, and permission handling run natively with
Swift, SwiftUI, AppKit, AVFoundation, and macOS Accessibility APIs. See
[Architecture](docs/ARCHITECTURE.md) for the component-level design.

## Requirements

- macOS 14 or newer — the build target. Which versions are actually certified
  for the private beta is recorded per release candidate; see
  [Release Readiness](docs/RELEASE_READINESS.md).
- Apple Silicon Mac
- Swift 5.10 or newer
- Internet access on the first build for the pinned `whisper.cpp` XCFramework
- A verified, compatible model downloaded from ZenVoice's Models screen

## Install

A signed, notarized release will be available from GitHub Releases once the
release checklist is complete. After the first release you can install with:

```bash
brew install --cask zenvoice/tap/zenvoice
```

Or download the latest `ZenVoice-distribution.zip` from the
[Releases](https://github.com/zenvoice/ZenVoice/releases) page, unzip it, and
move `ZenVoice.app` to `/Applications`.

## Build from source

```bash
./Scripts/build-app.sh
open build/ZenVoice.app
```

On first use, macOS requests:

- **Microphone**, to capture speech for local transcription.
- **Accessibility**, to paste the result into the focused application.

Without Accessibility permission, ZenVoice still copies the transcript to the
clipboard.

Open **Models** to download a checksum-verified English, multilingual, or
Hinglish-specialist `whisper.cpp` GGML model. The pinned `whisper.cpp`
XCFramework is bundled in the app; Homebrew is not required.

Open **Languages** to choose English, Hinglish, automatic detection, or another
spoken language. Non-English profiles require a compatible multilingual or
Hinglish-specialist model.

Open **Audio** to follow the macOS default input, pin a connected microphone,
or run a local signal and format test.

Open **Formatting** to choose Off, Clean, Smart, or Cloud. Smart uses Apple's
on-device system model on supported macOS 26+ systems and falls back locally;
Cloud remains a separate opt-in BYO-key path. Stable live preview and guarded
commit-on-pause insertion stay controlled from **Dictation**.

## Use ZenVoice

1. Open the **Shortcuts** screen to keep the default shortcut or record your
   own.
2. Open **Privacy** if you want to pause local history or enable Private
   Dictation.
3. Place the cursor in any editable text field.
4. Press your shortcut.
5. Speak while ZenBar displays the live waveform.
6. Press the shortcut again to stop, transcribe, and insert.

Alternatively, enable **Hold to dictate** in Shortcuts. Hold the selected
modifier key, speak, and release it to stop and transcribe.

Closing the settings window keeps ZenVoice running in the menu bar. Select
**Open ZenVoice…** from the menu-bar menu whenever you want it back.

## Verify

```bash
swift run ZenVoiceCoreChecks
swift run ZenVoiceStorageChecks
swift run ZenVoiceRuntimeChecks
swift build
./Scripts/build-app.sh
codesign --verify --deep --strict build/ZenVoice.app
```

The complete development and manual QA procedure is in
[Development](docs/DEVELOPMENT.md).

Model provenance, licences, revisions, and checksums are documented in
[Verified Model Catalogue](docs/MODEL_CATALOG.md).

## Repository guide

```text
.
├── Resources/           Brand assets and application metadata
├── Scripts/             Repeatable packaging utilities
  ├── Sources/
  │   ├── ZenVoice/        macOS application and ZenBar
  │   ├── ZenVoiceCore/    reusable local processing logic
  │   ├── ZenVoiceRuntime/ persistent local whisper.cpp integration
  │   ├── ZenVoiceStorage/ encrypted history and recovery storage
│   ├── ZenVoiceRuntimeChecks/
│   ├── ZenVoiceStorageChecks/
│   └── ZenVoiceCoreChecks/
├── docs/                architecture, privacy, development, and roadmap
└── Package.swift        Swift Package Manager definition
```

## Documentation

Start at the [documentation index](docs/README.md). Everything under `docs/`
describes ZenVoice as it is now; finished delivery plans and superseded R&D are
removed rather than archived, and the reasoning behind each decision lives in
[`docs/decisions/`](docs/decisions/).

- [Architecture](docs/ARCHITECTURE.md)
- [Design](docs/DESIGN.md)
- [Development](docs/DEVELOPMENT.md)
- [Privacy](docs/PRIVACY.md)
- [Verified Model Catalogue](docs/MODEL_CATALOG.md)
- [Voice Profile and Corrections](docs/VOICE_PROFILE.md)
- [Private Highlight Cards](docs/SHARING.md)
- [Instant Refine](docs/INSTANT_REFINE.md)
- [Language Profiles](docs/LANGUAGES.md)
- [Microphones and Audio Doctor](docs/AUDIO.md)
- [Live Dictation](docs/LIVE_DICTATION.md)
- [Release Readiness](docs/RELEASE_READINESS.md)
- [Phased Development Plan](docs/PHASED_PLAN.md)
- [M9 Security Review](docs/SECURITY_REVIEW.md)
- [Third-Party Notices](THIRD_PARTY_NOTICES.md)
- [Roadmap](docs/ROADMAP.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Project direction

ZenVoice is being built first for our own daily use. The immediate goal is to
make it the best possible personal dictation tool: reliable, low-latency,
multilingual, and respectful of privacy.

Public shipping is explicitly deferred. ZenVoice is open-source under the Apache
License, Version 2.0, and the distribution path (Developer-ID-signed direct
download via GitHub Releases, with an optional Homebrew cask) is already
prepared. That path will only be activated once the product has matured through
regular personal use and a deliberate future shipping decision is made.

Until then, passing CI and completing the manual release gates are not
claims of public availability. The current release checklist is retained in
[Release Readiness](docs/RELEASE_READINESS.md) for when shipping is reconsidered.
