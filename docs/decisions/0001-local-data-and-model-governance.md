# ADR 0001: Local Data and Model Governance

- Status: Accepted
- Date: 2026-07-23

## Context

ZenVoice is expanding from ephemeral local dictation into recoverable history,
downloadable speech models, and local usage insights. Dictation text can contain
private messages, work material, documents, and prompts. Local-first operation
reduces network exposure but does not remove storage, licensing, or product
honesty risks.

## Decision

### Local history

- ZenVoice asks for an explicit one-time choice before saving transcript
  history.
- Transcript contents are encrypted using CryptoKit with a key protected by the
  user's macOS Keychain.
- Successful recording audio is deleted immediately after the transcript is
  safely stored.
- Failed transcription audio may be retained locally for up to 24 hours for
  retry, with a user-facing off switch.
- Cancelled recordings are deleted immediately.
- Private Dictation mode stores neither transcript nor recovery audio.
- Users can delete individual records, delete all local data, and choose a
  retention period.

### Application context

- ZenVoice may store the frontmost application's bundle identifier and display
  name at dictation start.
- ZenVoice does not collect window titles, browser URLs, surrounding text,
  document contents, recipients, or geographic location.
- Work, personal, document, message, email, AI, and other categories remain
  local and user-correctable.

### Voice profile

- A ZenVoice voice profile is a local usage profile, not a biometric voiceprint.
- ZenVoice does not identify or authenticate people from their voice.
- “Corrected words” includes only changes made by ZenVoice's documented
  correction pipeline or changes the user explicitly saves inside ZenVoice.
- ZenVoice does not monitor edits performed later inside another application.

### Metric definitions

- `wordCount` is the number of whitespace-separated words in the final stored
  transcript.
- Per-dictation words per minute is `wordCount / recordingDurationMinutes`.
- Overall words per minute is weighted:
  `totalWordCount / totalRecordingDurationMinutes`.
- A successful dictation with at least five final words counts as an active
  streak day.
- Distinct-app counts use bundle identifiers.
- Time-based insights use local calendar dates and hours.

### Model catalogue

- The initial catalogue contains only reviewed OpenAI Whisper models and
  official `whisper.cpp` conversions.
- Every entry records publisher, source, pinned revision, SHA-256, file size,
  format, language coverage, licence, attribution, and compatibility.
- ZenVoice downloads model weights only from approved HTTPS sources.
- ZenVoice never executes repository scripts or arbitrary code from model
  downloads.
- Fast, Balanced, and High Accuracy are performance tiers. English and
  Multilingual are separate language capabilities.
- Model recommendations are evidence-backed by hardware checks and local
  benchmarks; users retain a safe manual override.

### Sharing

- Share cards are rendered locally.
- Transcript text and application names are excluded by default.
- ZenVoice never uploads or publishes a highlight automatically.
- The user previews and initiates every export or share action.

## Consequences

- The local vault and its migrations must precede insights.
- Encrypted transcript search and phrase analysis occur in-process rather than
  through plaintext database indexing.
- Recovery requires explicit lifecycle states for recording, transcription,
  storage, and insertion.
- Model catalogue changes require licence and provenance review.
- Public release requires a separate legal and security gate.

