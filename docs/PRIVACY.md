# Privacy

## Current privacy promise

ZenVoice's current transcription pipeline is local. Application code does not
send audio, transcripts, clipboard contents, or usage analytics over the
network.

## Data lifecycle

### Microphone audio

- Recorded as a temporary 16 kHz mono WAV file.
- Read in-process by the bundled local `whisper.cpp` runtime.
- Deleted after successful transcription.
- Deleted immediately when a recording is cancelled.
- When local history and failed-audio recovery are enabled, audio from a failed
  or interrupted transcription may remain in private Application Support
  storage for up to 24 hours from the start of its capture.
- Only fully failed transcriptions retain recovery audio, and only for up to
  24 hours when recovery is enabled.
- Turning failed-audio recovery off deletes any recovery recordings that are
  already retained.
- Private Dictation mode retains no transcript or recovery audio, including
  when it is enabled during an active or transcribing dictation and ZenVoice
  exits unexpectedly.
- A crash or forced termination could leave a temporary file until macOS cleans
  its temporary directory when history is disabled.

### Transcripts

- Stored in memory as the last transcript for immediate recovery.
- Written to the macOS clipboard before insertion.
- Remain on the clipboard until another application replaces them.
- Successful and usable partial transcripts are saved locally by default.
- Encrypted with AES-GCM before being written to the ZenVoice SQLite database.
- New ciphertext is authenticated against its record identifier and field, so
  encrypted values cannot be swapped between records or columns.
- Protected by a 256-bit key stored in the user's macOS Keychain.
- Kept until the user deletes an item or chooses Delete All; ZenVoice does not
  automatically expire transcript history.
- Never synced or uploaded by ZenVoice.

### Application context

- When history is enabled, ZenVoice stores the target application's bundle
  identifier and display name.
- ZenVoice uses that application identity for a conservative local category;
  unknown applications remain **Other**, and the user can change a record's
  category in History.
- ZenVoice does not store window titles, browser URLs, surrounding text,
  recipients, document contents, or geographic location.

### Insights

- Insights are derived locally from completed encrypted-history records.
- Aggregate fields include total words, recording duration, weighted
  words-per-minute, correction count, streak days, application counts, and
  user-correctable categories.
- A streak day requires at least one completed dictation containing five final
  words.
- Private Dictation and unsaved dictations never contribute to insights.
- ZenVoice does not send insight data, app identity, or category data to a
  server.

### Voice profile and corrections

- The Voice Profile is a local language-usage profile, not a biometric
  voiceprint.
- ZenVoice analyzes up to 500 recent saved transcripts in-process for frequent
  words, recurring phrases, and the most active hour.
- Personal correction source and replacement phrases are encrypted in the
  local vault with the same Keychain-protected key as transcripts.
- Only rules explicitly saved inside ZenVoice are applied. ZenVoice does not
  watch or infer later edits made in another application.
- Correction usage increases only when the corrected transcript is saved to
  history. Private Dictation and unsaved dictations leave no correction-usage
  event.
- Delete All removes correction rules before rotating the vault key.

### Highlight cards

- Highlight cards are rendered locally as 1200×630 images.
- The card payload contains only total words, weighted words-per-minute,
  current streak days, and distinct application count.
- Transcript text, application names, bundle identifiers, profile terms, and
  correction rules cannot enter the card payload.
- ZenVoice shows the exact preview before any action.
- Saving opens the macOS save panel. Sharing opens the macOS Share menu.
- ZenVoice never selects a destination, uploads, or publishes automatically.

### Models and configuration

- Whisper models remain in the user's local Application Support directory.
- A developer can override the selected model with a local environment
  variable; ZenVoice does not execute a model-supplied program.
- The runtime is a checksum-pinned binary dependency bundled inside the app.
- No API key or online account is required.

## macOS permissions

- **Microphone** is required to record speech.
- **Accessibility** is required only to simulate `Command + V`.

The signed app includes the Hardened Runtime audio-input entitlement. This
permits ZenVoice to ask macOS for microphone access; it does not bypass the
user's explicit Microphone approval.

If Accessibility permission is denied, transcription still works and the result
is copied to the clipboard.

## Security boundaries

Local-first does not mean risk-free:

- Other applications may be able to inspect clipboard contents.
- Anyone able to use the unlocked macOS account may be able to open ZenVoice
  and view decrypted history.
- Secure deletion on SSD storage has platform limitations; Delete All removes
  records, recovery audio, and rotates the encryption key.
- A developer-provided `ZENVOICE_MODEL_PATH` bypasses catalogue verification;
  only use it with a model file you trust.
- Apple Development signing gives local builds a stable macOS identity but is
  not appropriate for public distribution.

The project now records its release security review, third-party notices, and
automated readiness checks. Public release remains blocked until the owner
chooses a project licence and distribution policy, signs the exact artifact
with Developer ID, completes Apple notarization, and finishes the manual
privacy and clean-device QA checklist.
