# Architecture

## Purpose

ZenVoice is a local-first macOS dictation application. Its first responsibility
is dependable English transcription without sending microphone audio or
transcripts to an external service.

## Runtime flow

```text
SettingsView ─► SettingsViewModel ─► HotKeyPreferences
                       │                    │
                       └──── re-register ───▼
                                      GlobalHotKey
                                           │
                                           ▼
AppDelegate ───────────────────────────► AppState ─► ZenBarView
    │                                      ▲
    ├─► DictationVault ─► SQLite + AES-GCM + Keychain
    │         ▲
    │         └──────── HistoryViewModel ─► HistoryView
    ▼                                      │ microphone levels
AudioRecorder ──────► local WAV ──────► WhisperTranscriber
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
- `GlobalHotKey` registers the chosen global shortcut with Carbon.
- `HotKeyPreferences` persists that shortcut in local user defaults.
- `SettingsWindowController` owns the reusable native settings window.
- `SettingsViewModel` captures shortcut combinations and reports live
  Microphone, Accessibility, and model status.
- `HistoryViewModel` manages local-history consent, search, recovery actions,
  privacy controls, and deletion.
- `ZenVoiceSettingsView` provides Overview, History, Shortcuts, and Privacy
  screens.
- `ZenDesignTokens` keeps the dark Zen visual language consistent.
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
- `HotKeyConfiguration` validates and serializes shortcut choices.
- `TranscriptCleaner` performs conservative whitespace and filler cleanup.
- `ZenVoiceConfiguration` discovers the local runtime and model.
- `TranscriptionResult` carries raw and cleaned text without deciding its
  storage lifecycle.

### `ZenVoiceStorage`

The storage target owns the sensitive local-data boundary:

- `DictationVault` stores lifecycle records in native SQLite.
- Transcript fields use AES-GCM encryption.
- `KeychainVaultKeyProvider` protects the 256-bit encryption key in the macOS
  Keychain.
- `HistoryPreferences` records explicit history consent, failed-audio recovery,
  retention, and Private Dictation mode.
- Recovery audio lives in private Application Support storage and expires after
  24 hours when a transcription fails.

### `ZenVoiceCoreChecks`

`ZenVoiceCoreChecks` provides deterministic checks for transcript cleanup,
quiet-versus-loud waveform behavior, and hotkey serialization.

`ZenVoiceStorageChecks` verifies encrypted-at-rest transcript storage, weighted
WPM, interruption recovery, recovery-audio expiry, cancellation cleanup,
cryptographic Delete All, and explicit history preferences.

## State model

ZenBar exposes the actual dictation lifecycle:

1. `idle`
2. `listening`
3. `transcribing`
4. `inserting`
5. `success` or `error`

Busy states reject a second recording request. Success and error messages return
to idle after a short visible delay.

When history is enabled, a record moves through `recording`, `transcribing`,
`ready`, and `inserted` or `copiedOnly`. An interrupted or failed operation
moves to `failed` and can retain its local audio for retry.

## Concurrency

UI and application state remain on the main actor. Whisper transcription runs
on a dedicated user-initiated serial queue so model processing does not block
ZenBar.

## Current trade-offs

- `whisper-cli` starts a new process for every dictation. This keeps the first
  version simple but reloads the model and adds latency.
- English uses `ggml-base.en.bin`. Multilingual support requires model and
  language-selection changes.
- One user-defined shortcut starts and stops dictation. Additional actions and
  shortcuts are intentionally deferred.
- Automatic paste uses the system clipboard and a synthetic `Command + V`
  event, which requires Accessibility permission.
- Local builds prefer a stable Apple Development signature so macOS privacy
  approvals survive rebuilds. The Hardened Runtime signature includes only the
  audio-input resource entitlement required for recording. Public distribution
  will require Developer ID signing and notarization.
