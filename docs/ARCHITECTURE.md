# Architecture

## Purpose

ZenVoice is a local-first macOS dictation application. Its first responsibility
is dependable English transcription without sending microphone audio or
transcripts to an external service.

## Runtime flow

```text
GlobalHotKey
    │
    ▼
AppDelegate ────────────────► AppState ─► ZenBarView
    │                            ▲
    ▼                            │ microphone levels
AudioRecorder ─► local WAV ─► WhisperTranscriber
                                  │
                                  ▼
                           TranscriptCleaner
                                  │
                                  ▼
                            TextInserter
                                  │
                                  ├─► NSPasteboard
                                  └─► Command + V event
```

## Modules

### `ZenVoice`

The native application target owns macOS-specific behavior:

- `AppDelegate` coordinates the dictation lifecycle.
- `GlobalHotKey` registers `Control + Option + Space` with Carbon.
- `AudioRecorder` captures 16 kHz mono PCM audio using AVFoundation.
- `WhisperTranscriber` runs the local `whisper-cli` process.
- `TextInserter` copies and pastes the final transcript.
- `ZenBarPanelController` presents ZenBar across desktop spaces.
- `ZenBarView` renders state and microphone-responsive waveform history.
- `BrandAssets` loads packaged Zen branding.

### `ZenVoiceCore`

The platform-independent core contains logic that can be checked without
launching the application:

- `AudioLevelMeter` maps microphone dB readings into smoothed waveform levels.
- `TranscriptCleaner` performs conservative whitespace and filler cleanup.
- `ZenVoiceConfiguration` discovers the local runtime and model.

### `ZenVoiceCoreChecks`

This executable provides fast deterministic checks for transcript cleanup and
quiet-versus-loud waveform behavior. It avoids microphone and Accessibility
dependencies.

## State model

ZenBar exposes the actual dictation lifecycle:

1. `idle`
2. `listening`
3. `transcribing`
4. `inserting`
5. `success` or `error`

Busy states reject a second recording request. Success and error messages return
to idle after a short visible delay.

## Concurrency

UI and application state remain on the main actor. Whisper transcription runs
on a dedicated user-initiated serial queue so model processing does not block
ZenBar.

## Current trade-offs

- `whisper-cli` starts a new process for every dictation. This keeps the first
  version simple but reloads the model and adds latency.
- English uses `ggml-base.en.bin`. Multilingual support requires model and
  language-selection changes.
- Automatic paste uses the system clipboard and a synthetic `Command + V`
  event, which requires Accessibility permission.
- The project uses ad-hoc signing for local builds. Public distribution will
  require Developer ID signing and notarization.
