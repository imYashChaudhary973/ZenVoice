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
  <img alt="Private alpha" src="https://img.shields.io/badge/Status-Private_Alpha-5865F2">
</p>

ZenVoice is a native macOS app inspired by the speed of modern voice dictation
tools while keeping transcription, temporary audio, and configuration on your
Mac. Its ZenBar stays close at hand, while a dedicated settings window provides
clear controls and live system status. There are no accounts, subscriptions,
analytics, or cloud transcription services in the current application.

> [!IMPORTANT]
> ZenVoice is currently a private personal project. Public distribution,
> licensing, and pricing have not been decided.

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
- Verified English and multilingual model downloads with pinned revisions and
  SHA-256 validation.
- Explicit English-safe language profiles with 64 selectable languages.
- Hinglish Latin-script output plus native-script and local English-translation
  modes for multilingual dictation.
- Hardware-aware Fast, Balanced, and High Accuracy recommendations backed by
  private local timing samples.
- Local Instant Refine with Off, Clean, and Agent Prompt modes.
- Meaning-preserving cleanup for fillers, repeated words, spoken restarts, and
  explicit prompt layout commands.
- Visible model-download percentage with reliable cancellation.
- Local English transcription through `whisper.cpp`.
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
  → local Whisper transcription
  → conservative transcript cleanup
  → macOS clipboard and active-app paste
```

The settings interface, ZenBar, and permission handling run natively with
Swift, SwiftUI, AppKit, AVFoundation, and macOS Accessibility APIs. See
[Architecture](docs/ARCHITECTURE.md) for the component-level design.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Swift 5.10 or newer
- Internet access on the first build for the pinned `whisper.cpp` framework
- A verified model downloaded from ZenVoice's Models screen

## Quick start

Build and launch:

```bash
./Scripts/build-app.sh
open build/ZenVoice.app
```

On first use, macOS requests:

- **Microphone**, to capture speech for local transcription.
- **Accessibility**, to paste the result into the focused application.

Without Accessibility permission, ZenVoice still copies the transcript to the
clipboard.

Open **Models** to download a checksum-verified English or multilingual model.
The pinned `whisper.cpp` runtime is bundled in the app; Homebrew is not
required.

Open **Languages** to choose English, Hinglish, automatic detection, or another
spoken language. Any non-English profile requires a Multilingual model.

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
│   ├── ZenVoiceRuntime/ persistent in-process whisper.cpp integration
│   ├── ZenVoiceStorage/ encrypted history and recovery storage
│   ├── ZenVoiceRuntimeChecks/
│   ├── ZenVoiceStorageChecks/
│   └── ZenVoiceCoreChecks/
├── docs/                architecture, privacy, development, and roadmap
└── Package.swift        Swift Package Manager definition
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Development](docs/DEVELOPMENT.md)
- [Privacy](docs/PRIVACY.md)
- [Verified Model Catalogue](docs/MODEL_CATALOG.md)
- [Voice Profile and Corrections](docs/VOICE_PROFILE.md)
- [Private Highlight Cards](docs/SHARING.md)
- [Instant Refine](docs/INSTANT_REFINE.md)
- [Language Profiles](docs/LANGUAGES.md)
- [Release Readiness](docs/RELEASE_READINESS.md)
- [M9 Security Review](docs/SECURITY_REVIEW.md)
- [Third-Party Notices](THIRD_PARTY_NOTICES.md)
- [Roadmap](docs/ROADMAP.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Project direction

The immediate goal is a dependable personal dictation tool. Multilingual
models, local vocabulary, lower transcription latency, expanded settings, and
distribution readiness come after the English macOS workflow is stable.

ZenVoice intentionally has no license while its future distribution model is
undecided. All rights are reserved by the repository owner. Passing CI does
not make a build publicly releasable; the manual release gates must also be
completed.
