# Privacy

## Current privacy promise

ZenVoice's current transcription pipeline is local. Application code does not
send audio, transcripts, clipboard contents, or usage analytics over the
network.

The Privacy screen shows live local counts for encrypted transcripts, retained
recovery audio, correction rules, and installed speech models. These counts are
derived in-process and are not telemetry. The transcript and recovery counts are
taken from the most recent 500 records the screen has loaded, so they describe
that window rather than the whole database.

## Data lifecycle

### Microphone audio

- Recorded as a temporary 16 kHz mono WAV file.
- The chosen microphone identifier is stored locally. System Default stores no
  device identifier and follows the current macOS input.
- Audio Doctor records an explicit three-second local fixture, validates its
  signal and format, deletes it immediately, and creates no History record.
- Read in-process by the selected bundled local speech runtime.
- Deleted after successful transcription, unless Audio History is enabled — see
  below.
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
  exits unexpectedly. If it is enabled mid-dictation after a live-preview
  partial has already been written, that partial stays encrypted in the
  database until the dictation completes or ZenVoice next launches, whichever
  comes first; both discard it.
- A crash or forced termination could leave a temporary file until macOS cleans
  its temporary directory when history is disabled.
- Users can delete all retained recovery audio independently from the Privacy
  inventory after a destructive-action confirmation.

### Audio History

- Off by default. Nothing is archived until the user turns it on, and the
  setting records whether an explicit choice has been made.
- When enabled, the full recording is copied into private Application Support
  storage (`AudioHistory/`) after the transcript is stored.
- Archived audio is **not encrypted**. Transcripts are encrypted; whole
  recordings are not. The archive is protected by private directory
  permissions, by being opt-in, and by the size and age budgets below. This is
  stated in the Audio History screen as well as here.
- Archives are separate from encrypted transcript history and have their own
  storage, table, budgets, and delete controls.
- Two budgets bound the archive, both user-configurable: total size (default
  2 GB, minimum 100 MB) and age (default 30 days, minimum 1 day). Cleanup runs
  at launch and after each archived recording, deleting the oldest first.
- Archiving follows transcript persistence, so Private Dictation, paused
  history, and suppressed dictations are never archived.
- Recordings can be played back, deleted individually, or deleted all at once.
- Export produces a ZIP of the audio plus a metadata manifest — timestamp,
  duration, size, language, model, target app, category. Transcript text is
  excluded unless the user explicitly turns it on for that export.
- Audio never leaves the Mac unless the user exports it themselves.
- Full rationale in [ADR 0009](decisions/0009-audio-history.md).

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
- Application profiles store only the bundle identifier, display name,
  language choice, refinement mode, ZenIntelligence mode, Command Mode command
  set, Write Mode default sub-mode, custom prompt hints, and voice-command
  toggle in local preferences.
- The optional next-dictation context is bounded to 500 characters, held only
  in memory, and cleared when recording starts. It is not stored in History,
  preferences, logs, or analytics.
- That temporary context is provided only to the selected local speech runtime.
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
- Personal rule application and saved-history pattern analysis can be paused
  independently. Pausing leaves existing encrypted data untouched.
- Delete All Rules removes correction rules without deleting transcript
  History. Full Delete All still removes both and rotates the vault key.

### Recovery Inbox

- Recovery Inbox is a local filter over existing encrypted History records;
  it creates no duplicate database or transcript.
- Failed dictations appear with Retry only while valid recovery audio exists.
- Usable partial transcripts remain copyable even when their audio has been
  deleted.
- The existing 24-hour failed-audio expiry and Private Dictation rules still
  apply.

### Instant Refine

- Instant Refine processes the completed transcript in memory after the
  selected local speech runtime finishes and before storage or paste.
- Off, Clean, and Agent Prompt modes use deterministic application code.
- Refinement is deterministic and local. No transcript is sent to an API,
  analytics endpoint, or cloud service.
- Its meaning guard rejects destructive or vocabulary-expanding candidates,
  including dropped negations.
- Private Dictation can use the same in-memory refinement while saving no
  transcript or correction-usage event.
- The former downloadable refinement-model path was measured and removed; no
  refinement weights are downloaded or loaded by the current application.

### ZenIntelligence

- ZenIntelligence is an opt-in, local post-processing layer that runs after
  Instant Refine.
- Format mode uses deterministic local rules for capitalization, spoken-digit
  conversion, punctuation spacing, and whitespace cleanup.
- Context Aware mode may use the same bounded 500-character next-dictation
  context described under Application context. That context is held in memory,
  is not persisted, and is only used to join sentence fragments conservatively.
- A local meaning guard rejects candidates that invent words, change numeric
  values, or alter facts.
- No transcript or context is sent to a remote model, API, or analytics service.

### Command Mode

- Command Mode is an opt-in per-app and global feature that converts matching
  voice phrases into local actions.
- The command manifest and per-app command-set choices are stored in local
  preferences.
- Phrases are matched by deterministic local rules; no audio or transcript is
  sent to a server.
- System actions such as volume, mute, brightness, display sleep, lock screen,
  application launch, and AppleScript invocation are executed through local macOS
  APIs (`CoreAudio`, `IOKit`, `CGEvent`, `NSWorkspace`, `Process`).
- Destructive or system-affecting actions require explicit approval in the ZenBar
  before they run.
- Approved command actions are recorded only in the same local History record as
  a normal dictation; no separate command log is kept.

### Write Mode

- Write Mode is an opt-in per-app mode for composing new text or rewriting
  text that is already selected in the target application.
- Reading the current selection uses Accessibility APIs or the system
  clipboard as a fallback. The source text is held in memory only long enough to
  produce the rewrite or replacement and is not stored in History unless the
  final result is saved as a normal dictation.
- Composed or rewritten text is shown in a preview before insertion when a
  preview threshold is configured.
- Insertion uses the same Accessibility path as standard dictation insertion.
- No text is sent to a remote service.

### Live dictation

- Live phrase samples stay in memory and are processed by the same selected
  local speech runtime after a detected pause.
- Stable phrases are encrypted into the active History record for interruption
  recovery; Private Dictation and paused History write no partial text.
- Commit on pause is off by default. When enabled, it inserts only into the
  application that was active when dictation began.
- In-memory samples are released with the recording session and are never sent
  to a network service.

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

- Whisper GGML files remain in the user's local Application Support directory.
- A developer can override the selected model with a local environment
  variable; ZenVoice does not execute a model-supplied program.
- Model downloads are fixed to reviewed HTTPS sources, immutable revisions,
  expected sizes, and SHA-256 digests before installation. ZenVoice constructs
  every download URL itself and installs only after the whole download verifies.
- The `whisper.cpp` XCFramework is checksum-pinned; it runs in process.
- No API key or online account is required.

## macOS permissions

- **Microphone** is required to record speech.
- **Accessibility** is required to place the transcript into the focused
  application. That is normally a simulated `Command + V`, but it also covers
  two narrower uses of the same permission:
  - when macOS secure input is active, ZenVoice writes the transcript into the
    focused control directly instead of synthesizing a keystroke; and
  - when it replaces an already-inserted transcript with a refined version, it
    reads the focused control's text and caret range to find the span it wrote,
    then overwrites just that span.
  Text read this way is used in memory for that comparison only. It is not
  stored in History, preferences, insights, or logs.
- ZenVoice refuses to insert into a field macOS marks as a secure text field,
  and refuses text fields it cannot positively identify while secure input is
  active. In those cases the transcript is copied to the clipboard instead and
  ZenBar says so.

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

The project records its release security review, third-party notices, and
automated readiness checks. Public release remains blocked until the signed
artifact passes Apple notarization and the manual privacy and clean-device QA
checklist is completed.
