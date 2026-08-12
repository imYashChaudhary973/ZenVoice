# Architecture

## Purpose

ZenVoice is a local-first macOS dictation application. Its first responsibility
is dependable transcription without sending microphone audio or transcripts to
an external service.

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
    │                      ▲
    └─► stable pause ──────┘
                                           │
                                           ▼
                                    TranscriptCleaner
                                           │
                                           ▼
                                    InstantRefineEngine
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
- `InsightsViewModel` reads privacy-safe aggregate metrics from the vault.
- `VoiceProfileViewModel` manages the local language profile and explicit
  personal correction rules plus explicit switches for rule application and
  pattern analysis.
- `ShareHighlightCardRenderer` renders a fixed 1200×630 image locally from a
  numeric-only `ShareCardSummary`.
- `ZenVoiceSettingsView` provides Overview, Models, History, Insights,
  Voice Profile, Shortcuts, and Privacy screens.
- `OnboardingViewModel` presents an upgrade-safe, reopenable setup sheet.
  `OnboardingPreferences` distinguishes a fresh install from an existing
  configured installation before default History state is materialized.
- `ZenDesignTokens` keeps the dark Zen visual language consistent.
- `AudioRecorder` captures 16 kHz mono PCM audio using AVFoundation.
- `MicrophoneCatalog` discovers connected inputs and maps the selected
  AVFoundation identifier to its Core Audio device without changing the macOS
  system default.
- `AudioRecorder` uses `AVAudioEngine` to capture the selected input and
  converts it to 16 kHz mono PCM for the selected local speech runtime.
  `SettingsViewModel` runs the explicit three-second Audio Doctor and deletes
  its temporary file.
- When live preview is enabled, `AudioRecorder` also keeps bounded-to-session
  in-memory samples. `StablePauseDetector` exposes a phrase only after reviewed
  speech and silence thresholds.
- `ZenBarPanelController` presents ZenBar across desktop spaces.
- `ZenBarView` renders state and microphone-responsive waveform history.
- `BrandAssets` loads packaged Zen branding.

### `ZenVoiceCore`

The shared core contains logic that can be checked without launching the full
application:

- `AudioLevelMeter` maps microphone dB readings into smoothed waveform levels.
- `HotKeyConfiguration` validates and serializes shortcut choices.
- `TranscriptCleaner` performs conservative whitespace and filler cleanup.
- `InstantRefineEngine` removes reviewed fillers, repetitions, spoken
  restarts, and explicit layout commands before paste. Its meaning guard
  rejects destructive or vocabulary-expanding candidates.
- `InstantRefinePreferences` persists Off, Clean, or Agent Prompt mode locally.
- `ApplicationProfilePreferences` stores non-sensitive per-app language,
  refinement, and voice-command settings by bundle identifier.
- `LocalVoiceCommandEngine` applies reviewed layout and punctuation commands
  before refinement. `NextDictationContext` bounds and sanitizes the
  memory-only hint passed to local runtimes.
- `TextInserter` owns the macOS clipboard and accessibility boundary. Its
  secure-input policy is deterministic and checked in `ZenVoiceCoreChecks`.
- `LanguageCatalog` exposes the reviewed language codes and product support
  level. `LanguagePreferences` persists the explicit input/output profile.
- `LocalTransliterator` converts supported native scripts to Latin characters
  after transcription without a network service.
- `ZenVoiceConfiguration` discovers the selected verified model and rejects
  incompatible language/model combinations.
- `VerifiedModelCatalog` is the signed allowlist for model publisher, source,
  revision, size, format, language capability, licence, and SHA-256.
- `TranscriptionResult` carries raw and cleaned text without deciding its
  storage lifecycle.

`ModelManagerViewModel` reports byte-based download progress, verifies approved
downloads before atomic replacement, prevents cancelled tasks from clearing a
new download, and updates the selected local model without sending speech data
to a server.
`HistoryViewModel` derives its Recovery Inbox directly from encrypted History
records marked failed or partial; it does not create a second transcript copy.
The Privacy screen derives live inventory counts from the same view models and
confirms destructive recovery-audio deletion instead of maintaining another
analytics store.
`ModelRecommendationEngine` maps RAM and storage headroom to a default tier,
while `ModelBenchmarkStore` keeps bounded, content-free local timing samples.

### `ZenVoiceRuntime`

- `WhisperTranscriber` is the local speech interface. It calls the official
  pinned `whisper.cpp` XCFramework directly instead of launching a child process.
  It accepts a per-recording language token and sanitized initial prompt, enables
  local translation only for English-output profiles, and applies local
  transliteration only for Latin-script profiles.
- The runtime warms and retains its model state for subsequent dictations.
- Model replacement creates a new transcriber; an active transcription keeps
  its original transcriber until that operation completes.
- The runtime accepts only 16 kHz mono audio produced by `AudioRecorder`.
- File and in-memory sample transcription use the same retained runtime and
  dedicated serial queue, preventing concurrent access to model state.

The previous Parakeet/CoreML path, which required the closed-source FluidAudio
runtime, has been removed. ZenVoice now uses `whisper.cpp` as its only local
speech engine.

### `ZenVoiceStorage`

The storage target owns the sensitive local-data boundary:

- `DictationVault` stores lifecycle records in native SQLite.
- Transcript fields use AES-GCM encryption.
- `KeychainVaultKeyProvider` protects the 256-bit encryption key in the macOS
  Keychain.
- `HistoryPreferences` records history saving, failed-audio recovery, and
  Private Dictation mode.
- `LocalInsightsSnapshot` calculates weighted WPM, total words, streaks,
  seven-day activity, application usage, and category totals from completed
  local records.
- `ApplicationCategoryClassifier` assigns a conservative initial category from
  the frontmost app. Unknown apps remain Other, and users can correct any
  category from History.
- `VoiceProfileSnapshot` analyzes up to 500 recent decrypted-in-process
  transcripts for frequent words, recurring two- and three-word phrases, and
  the most active local hour.
- Correction source and replacement phrases are encrypted with field-bound
  AES-GCM. `TranscriptCorrectionEngine` applies explicit case-insensitive,
  whole-phrase rules without monitoring edits in other applications.
- Recovery audio lives in private Application Support storage and expires no
  later than 24 hours after capture began; disabling recovery removes retained
  recovery recordings immediately.

### `ZenVoiceCoreChecks`

`ZenVoiceCoreChecks` provides deterministic checks for transcript cleanup,
quiet-versus-loud waveform behavior, strict hotkey validation, private-mode
shortcut defaults, and hold-key serialization.

`ZenVoiceStorageChecks` verifies encrypted-at-rest transcript storage, weighted
WPM and insights, editable categories, application classification,
encrypted correction rules and usage, recurring phrases,
interruption recovery, capture-bounded recovery expiry, durable
Private Dictation suppression, recovery-disable cleanup, cancellation cleanup,
cryptographic Delete All, ciphertext field binding, recovery-path confinement,
partial transcript flags, and history preferences.

`ZenVoiceRuntimeChecks` creates a local silent WAV and performs two sequential
passes through one transcriber. It validates the embedded Whisper C API and the
persistent Whisper-model lifecycle without microphone or UI interaction.

`ShareCardSummary` lives in the core target and can contain only total words,
weighted WPM, current streak, and distinct application count. It has no field
for transcript text, application identity, profile terms, or correction rules.

## Delivery boundaries

GitHub Actions runs deterministic Swift checks and packages an ad-hoc-signed
app on a hosted macOS runner. A separate token-free Semgrep Community Edition
job scans tracked source with read-only repository permissions. Real-speech
decoding stays off the pull-request path deliberately; a scheduled speech-gate
workflow decodes the pinned model and corpus weekly, and the automated release
gate in `Scripts/check-release-readiness.sh` is runnable on demand from the
Actions tab.

CI artifacts are verification builds, not public releases. Public distribution
requires the independent gates in `docs/RELEASE_READINESS.md`, including
Developer ID Application signing, a secure timestamp, Apple notarization, a
stapled ticket, clean-device QA, and founder approval. No signing or
notarization credentials are stored in this repository.

## State model

ZenBar exposes the actual dictation lifecycle:

1. `idle`
2. `listening`
3. `transcribing`
4. `inserting`
5. `success` or `error`

Busy states reject a second recording request. Success and error messages return
to idle after a short visible delay.

If the active microphone disconnects, the recording stops and moves through
the existing failed-recovery policy instead of silently changing devices.

Stable live phrases are encrypted into the active record without changing its
recording status. Final stop combines accepted phrases with the uncommitted
remainder. Optional commit-on-pause insertion locks to the original foreground
application and is disabled for the rest of a session after any safety guard
fails.

When history is enabled, a record moves through `recording`, `transcribing`,
`ready`, and `inserted` or `copiedOnly`. An interrupted or failed operation
moves to `failed` and can retain its local audio for retry.

The completed speech transcript passes through deterministic Instant Refine and
then encrypted personal correction rules. The resulting text is what history
and insertion receive; the raw speech transcript remains available in the
encrypted record for local recovery and comparison.

## Concurrency

UI and application state remain on the main actor. Local speech transcription
and deterministic text refinement run on a dedicated user-initiated serial
queue so model processing does not block ZenBar.

## Memory

A loaded speech model is the dominant term in ZenVoice's memory use — measured
at **600 MB** for Whisper Turbo and **940 MB** for Nemotron, almost all of it
GPU buffers allocated in 128 MB regions. With no model resident the app sits at
about **50 MB**.

Measured on one machine with Whisper Turbo selected as the model and Nemotron
as the engine:

| | Steady | Peak at launch |
| --- | --- | --- |
| Before | 2,369 MB | 5,469 MB |
| Streaming hash | 1,687 MB | 2,662 MB |
| Warming only the engine in use | 991 MB | 1,930 MB |
| After five idle minutes | **53 MB** | — |

Three rules keep that from becoming the app's steady state:

**Only the engine that will be used is warmed.** Warm-up used to load Whisper
unconditionally *and* prepare whichever engine the user had selected, so a Mac
set to Nemotron or Parakeet loaded two models at launch and held both — about
600 MB spent on a decode that was never going to happen. `warmUpEngines()` now
warms Whisper only when a dictation will actually reach it: when Whisper is the
resolved engine, or when live preview is on, since preview decodes its partial
segments with Whisper whatever produces the final transcript.

**Models are unloaded after five idle minutes.** `AppDelegate` runs a one-shot
timer, restarted by every route into a dictation, and calls
`EngineRegistry.releaseAll()` when it expires. The next dictation reloads
transparently — `beginRecording` already warms the engines. A dictation that
outlives the timeout is not interrupted: the timer sees the app is busy and
comes back in thirty seconds.

`release()` is a `SpeechEngine` requirement with a no-op default, so an engine
whose `prepare()` is cheap need not implement it — but every engine that loads
weights must. Whisper, all three Parakeet variants, Nemotron and Cohere do.
When only Whisper implemented it, idle unloading reclaimed the one model the
user had *not* selected and left the other resident indefinitely.

Freeing a model while a decode holds it would be a use-after-free, and the
Whisper context is reached from two serial queues — the engine's own, and the
app's transcription queue for live preview. `WhisperTranscriber` therefore
counts decodes in flight and `unload()` waits for that count to reach zero.

**Hashing streams.** `VerifiedModelCatalog.sha256Hex` reads in 1 MB chunks
inside an `autoreleasepool`. Without the pool the chunks are autoreleased
`NSData` that live until the function returns, which made hashing O(file size)
rather than O(chunk): measured across a full install (~6.6 GB of models), the
unpooled loop peaked at 6,364 MB against 5 MB pooled.

`verify` itself never caches: it is the integrity boundary, and it re-hashes
every time. The settings list — which runs over every catalogue entry each time
the window opens, about 6.6 GB on a full install — calls `verifyForListing`
instead, which may reuse this process's answer for a file whose path, size,
modification date and identifier all match. That distinction is not cosmetic.
Size and mtime are not an integrity boundary: a same-size edit inside the
filesystem's timestamp resolution is indistinguishable from no edit at all,
which is exactly what `ZenVoiceCoreChecks` demonstrates by rewriting a fixture
in place and demanding a rejection. The worst a stale listing answer can do is
leave a badge wrong in a list; nothing is loaded on its say-so, because
`ZenVoiceConfiguration.discover` calls `verify` and hashes the bytes.

## Current trade-offs

- The first transcription after launch, after a model change, or after an idle
  unload pays the model-load cost; later dictations reuse that in-memory
  context.
- English remains explicit even with a multilingual model. Automatic language
  detection is an opt-in profile because short phrases are easy to misclassify.
- Users can configure toggle dictation, paste-last, and Private Dictation
  shortcuts. Hold-to-dictate supports Fn and right-side modifier keys.
- Automatic paste uses the system clipboard and a synthetic `Command + V`
  event, which requires Accessibility permission.
- Local builds prefer a stable Apple Development signature so macOS privacy
  approvals survive rebuilds. The Hardened Runtime signature includes only the
  audio-input resource entitlement required for recording. Public distribution
  will require Developer ID signing and notarization.
- Automated security scanning identifies known code patterns; it cannot prove
  that privacy promises, permission UX, or release decisions are correct.
