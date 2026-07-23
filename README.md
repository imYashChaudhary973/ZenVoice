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

ZenVoice is a native macOS menu-bar app inspired by the speed of modern voice
dictation tools while keeping transcription, temporary audio, and configuration
on your Mac. There are no accounts, subscriptions, analytics, or cloud
transcription services in the current application.

> [!IMPORTANT]
> ZenVoice is currently a private personal project. Public distribution,
> licensing, and pricing have not been decided.

## What works today

- Global `Control + Option + Space` dictation shortcut.
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

The interface and permissions run natively with Swift, SwiftUI, AppKit,
AVFoundation, and macOS Accessibility APIs. See
[Architecture](docs/ARCHITECTURE.md) for the component-level design.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Swift 5.10 or newer
- [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp)
- A local `ggml-base.en.bin` model

## Quick start

Install the local transcription runtime:

```bash
brew install whisper-cpp
```

Place the English model at:

```text
~/Library/Application Support/ZenVoice/Models/ggml-base.en.bin
```

Then build and launch:

```bash
./Scripts/build-app.sh
open build/ZenVoice.app
```

On first use, macOS requests:

- **Microphone**, to capture speech for local transcription.
- **Accessibility**, to paste the result into the focused application.

Without Accessibility permission, ZenVoice still copies the transcript to the
clipboard.

## Use ZenVoice

1. Place the cursor in any editable text field.
2. Press `Control + Option + Space`.
3. Speak while ZenBar displays the live waveform.
4. Press the shortcut again to stop, transcribe, and insert.

## Verify

```bash
swift run ZenVoiceCoreChecks
swift build
./Scripts/build-app.sh
```

The complete development and manual QA procedure is in
[Development](docs/DEVELOPMENT.md).

## Repository guide

```text
.
├── Resources/           Brand assets and application metadata
├── Scripts/             Repeatable packaging utilities
├── Sources/
│   ├── ZenVoice/        macOS application and ZenBar
│   ├── ZenVoiceCore/    reusable local processing logic
│   └── ZenVoiceCoreChecks/
├── docs/                architecture, privacy, development, and roadmap
└── Package.swift        Swift Package Manager definition
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Development](docs/DEVELOPMENT.md)
- [Privacy](docs/PRIVACY.md)
- [Roadmap](docs/ROADMAP.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Project direction

The immediate goal is a dependable personal dictation tool. Multilingual
models, local vocabulary, lower transcription latency, settings, and
distribution readiness come after the English macOS workflow is stable.

ZenVoice intentionally has no license while its future distribution model is
undecided. All rights are reserved by the repository owner.
