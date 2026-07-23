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
AudioRecorder ──────► local WAV ──────► ZenVoiceRuntime
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
- `GlobalHotKey` registers action-specific global shortcuts with Carbon and
  validates the delivered hotkey identifier before dispatch.
- `HoldToDictateController` listens for supported modifier press/release events.
- `HotKeyPreferences` persists that shortcut in local user defaults.
- `SettingsWindowController` owns the reusable native settings window.
- `SettingsViewModel` captures shortcut combinations and reports live
  Microphone, Accessibility, and model status.
- `HistoryViewModel` manages local-history controls, search, recovery actions,
  privacy controls, and deletion.
- `ZenVoiceSettingsView` provides Overview, History, Shortcuts, and Privacy
  screens.
- `ZenDesignTokens` keeps the dark Zen visual language consistent.
- `AudioRecorder` captures 16 kHz mono PCM audio using AVFoundation.
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
- `ZenVoiceConfiguration` discovers the selected verified model.
- `VerifiedModelCatalog` is the signed allowlist for model publisher, source,
  revision, size, format, language capability, licence, and SHA-256.
- `TranscriptionResult` carries raw and cleaned text without deciding its
  storage lifecycle.

`ModelManagerViewModel` verifies approved downloads before atomic installation
and updates the selected local model without sending speech data to a server.
`ModelRecommendationEngine` maps RAM and storage headroom to a default tier,
while `ModelBenchmarkStore` keeps bounded, content-free local timing samples.

### `ZenVoiceRuntime`

- `WhisperTranscriber` calls the official pinned `whisper.cpp` XCFramework
  directly instead of launching a child process.
- The model context is loaded lazily on the transcription queue and retained
  by the transcriber for subsequent dictations.
- Model replacement creates a new transcriber; an active transcription keeps
  its original transcriber until that operation completes.
- The runtime accepts only 16 kHz mono audio produced by `AudioRecorder`.

### `ZenVoiceStorage`

The storage target owns the sensitive local-data boundary:

- `DictationVault` stores lifecycle records in native SQLite.
- Transcript fields use AES-GCM encryption.
- `KeychainVaultKeyProvider` protects the 256-bit encryption key in the macOS
  Keychain.
- `HistoryPreferences` records history saving, failed-audio recovery, and
  Private Dictation mode.
- Recovery audio lives in private Application Support storage and expires no
  later than 24 hours after capture began; disabling recovery removes retained
  recovery recordings immediately.

### `ZenVoiceCoreChecks`

`ZenVoiceCoreChecks` provides deterministic checks for transcript cleanup,
quiet-versus-loud waveform behavior, strict hotkey validation, private-mode
shortcut defaults, and hold-key serialization.

`ZenVoiceStorageChecks` verifies encrypted-at-rest transcript storage, weighted
WPM, interruption recovery, capture-bounded recovery expiry, durable
Private Dictation suppression, recovery-disable cleanup, cancellation cleanup,
cryptographic Delete All, ciphertext field binding, recovery-path confinement,
partial transcript flags, and history preferences.

`ZenVoiceRuntimeChecks` creates a local silent WAV and performs two sequential
passes through one transcriber. It validates the embedded C API and persistent
model lifecycle without microphone or UI interaction.

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

- The first transcription after launch or model selection pays the model-load
  cost; later dictations reuse that in-memory context.
- Multilingual models currently use local automatic language detection.
- Users can configure toggle dictation, paste-last, and Private Dictation
  shortcuts. Hold-to-dictate supports Fn and right-side modifier keys.
- Automatic paste uses the system clipboard and a synthetic `Command + V`
  event, which requires Accessibility permission.
- Local builds prefer a stable Apple Development signature so macOS privacy
  approvals survive rebuilds. The Hardened Runtime signature includes only the
  audio-input resource entitlement required for recording. Public distribution
  will require Developer ID signing and notarization.
