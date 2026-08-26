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
- Full rationale in [ADR 0010](decisions/0010-audio-history.md).

### Lecture capture

- Start/stop lives in History → Lectures. The dictation hotkey does not
  create, append to, or paste a lecture.
- Audio is a 16 kHz mono WAV in private Application Support (`Lectures/`).
  Like Audio History, the WAV is **not encrypted at rest**.
- A lecture is independent of the Audio History toggle. Starting one is
  consent to keep that file until you delete it.
- Quit or crash mid-session keeps the partial WAV and marks the sidecar
  `incomplete`.
- v1 stops at 90 minutes and refuses to start if the disk cannot hold that
  much 16 kHz float32 mono audio.
- After Stop, the selected local engine transcribes the file. The original
  transcript is encrypted in the sidecar with the History vault key. Failed
  decode keeps the WAV and offers Retry. Nothing is pasted into another app.
- Summarize appears only when Cloud AI is enabled and is disabled until its
  provider is fully configured. It sends only the original transcript text
  and the fixed lecture-summary prompt through the existing Cloud path. Audio,
  title, file paths, engine metadata, and other lectures never enter the
  request. The encrypted summary is stored separately; failure leaves the
  original untouched.
- Privacy & Data shows the current lecture count and total bytes used by
  lecture WAV files. The inventory reads local file metadata only and sends
  nothing.
- Full contract in [ADR 0014](decisions/0014-lecture-capture-v1.md).

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
- Off and Clean use deterministic application code. Smart runs Clean first and,
  on macOS 26 or later, may ask Apple's on-device `SystemLanguageModel` only
  for punctuation and layout.
- Smart creates a fresh model session for the completed transcript, supplies no
  API key, and never constructs `PrivateCloudComputeLanguageModel`. Unsupported,
  disabled, ineligible, not-ready, timed-out, or rejected model work falls back
  to deterministic local formatting.
- The lexical and semantic guards reject invention, deletion, paraphrasing,
  changed quantities, and changed negations before model output can replace the
  local transcript.
- Private Dictation can use the same in-memory formatting while saving no
  transcript or correction-usage event.
- The former downloadable Qwen/llama.cpp path remains removed; ZenVoice
  downloads and loads no refinement weights.

### Cloud AI Enhancement

- **This is the only ZenVoice feature that can send your text off this Mac.**
  It is off by default and does nothing until you both enable it and supply
  your own provider API key.
- What is sent: the finished transcript text and your prompt.
- What is never sent: audio, the application you dictated into (bundle
  identifier or name), the next-dictation context, transcript history,
  insights, voice-profile data, correction rules, and any device or install
  identifier.
- Requests go directly from your Mac to the provider you chose, authenticated
  with your key. ZenVoice operates no proxy and holds no vendor account, so
  there is no ZenVoice-side record of the request or its content.
- The endpoint must be HTTPS. Choosing the custom provider lets you point at a
  self-hosted or local model so the text stays on infrastructure you control.
- Your API key is stored in the macOS Keychain, never in preferences and never
  in the transcript database. Turning the feature off deletes it.
- Enhanced text is shown next to the original and is applied only when you
  accept it. A failed request leaves the local transcript untouched.
- Once you opt in, your transcript text is subject to the chosen provider's
  retention and training policies, which ZenVoice cannot control or promise
  anything about.
- Full rationale in [ADR 0011](decisions/0011-cloud-ai-enhancement.md).

### Updates

- ZenVoice is distributed directly rather than through the Mac App Store, so
  updates are verified against a signed release feed.
- The updater is currently inert: public distribution is deferred, and no
  release feed is configured for this build.
- An update check sends only what fetching a static URL requires — no install
  identifier, no usage data, no transcript or audio content.
- Checks happen only when automatic checking is enabled or you ask explicitly.
- The feed is signed with Ed25519 and verified against a key built into the
  app; the downloaded archive's SHA-256 must match the signed feed. Any
  verification failure rejects the update and changes nothing.
- Full rationale in [ADR 0012](decisions/0012-auto-updates.md).

### Local formatting

- The unified Formatting ladder replaces the former ZenIntelligence UI.
- Clean uses deterministic local rules. Smart adds the OS-managed on-device
  language model behind strict lexical and semantic guards.
- A bounded 500-character next-dictation context may still be used only by the
  deterministic context join. It is held in memory and is never persisted or
  sent to a model.
- No transcript or context is sent to a remote model, API, analytics service,
  or Private Cloud Compute. Cloud formatting is the separate opt-in feature
  described above.

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

### Agentic Mode

- Agentic Mode is off by default and is reached only after Command Mode's
  deterministic phrase matching declines a transcript.
- Planning is local: deterministic templates first, then Apple's on-device
  system model. No transcript, plan, or goal is sent to a ZenVoice server, and
  ZenVoice has no cloud planner.
- Nothing runs until you approve the exact steps shown. High-risk steps require
  their own approval, and only an unchanged low-risk step can be remembered.
- The plan, every approval decision, and captured step output are stored in the
  same encrypted local vault as transcripts (`agentic_tasks`). Output is passed
  through a secret redactor before it is written, retained output is capped per
  step, and the plan validator refuses commands that contain secret-shaped
  strings.
- Approved steps spawn local command-line tools (`codex`, `claude`, `zsh`,
  `shortcuts`) with a minimal environment that contains no ZenVoice keychain
  material and no provider API keys. **Those tools are separate products with
  their own accounts, credentials, and network behaviour: when you approve a
  Codex or Claude step, that tool contacts its own provider under its own
  configuration.** ZenVoice neither supplies nor inspects those credentials.
- Network egress in the agentic path is only whatever an approved step does
  itself, and any step whose command surface implies egress or writes outside
  the working directory is classified high risk and approved individually.
- Cancelling from ZenBar signals the whole child process group; relaunching
  ZenVoice never resumes an interrupted step.

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
