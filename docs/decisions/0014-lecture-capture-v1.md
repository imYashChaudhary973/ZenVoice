# ADR 0014 — Lecture Capture v1 (offline)

## Status

**Accepted — 2026-08-22.** Phase 0 contract locked. No feature code in
this change. Implementation starts only when Phase 1 is requested.

## Context

ZenVoice today is short, on-demand speech that pastes into the focused
app. A lecture is a different job: a long, explicit recording that must
keep the original words, then optionally summarize them.

This ADR locks v1 only. Meetings (Zoom / Meet / Teams), system-audio
loopback, and speaker diarization are out of scope.

## Decision

### 1. One lecture is three things

A lecture is:

1. one local audio file,
2. one **immutable original transcript**,
3. an optional **summary** in a separate field.

The original transcript is never overwritten, merged, or replaced by a
summary, a Cloud result, Instant Refine, or a later re-transcribe that
the user did not explicitly request. Re-transcribe writes a new original
only after the user confirms; the previous original is discarded only
then. Summary stays in its own field or is cleared; it never lands in
the original.

### 2. Capture is start/stop inside ZenVoice

Lecture recording starts and stops from a ZenVoice lecture control, not
from the global dictation hotkey.

The dictation hotkey keeps its current job: record a short utterance and
paste. It must not create a lecture, append to a lecture, or paste a
lecture into the frontmost app.

### 3. Summary is opt-in, BYO-key, text only

Summarize is off until Cloud AI Enhancement is enabled **and** a
provider key is stored (same gate as ADR 0011).

What may leave the Mac: the original transcript text and a lecture
prompt.

What must never leave the Mac: audio, lecture title, file paths, other
lectures, dictation history, app identity, device identifiers.

Send through the existing Cloud transport and provider list only. A
failed, cancelled, or empty result leaves the original transcript
untouched and stores no summary.

### 4. Codex is out

Lecture summary must not call Codex, the `codex` CLI, Agentic Mode, or
any code-agent path.

Allowed providers are exactly the current Cloud set: OpenAI, Groq,
Anthropic (Claude), OpenRouter, Ollama Cloud, Ollama, and custom
HTTPS / loopback. No new vendor for v1.

### 5. Ninety minutes is the v1 ceiling

Maximum duration is **90 minutes**.

- Refuse **Start** if remaining disk cannot hold ~90 minutes of 16 kHz
  mono WAV.
- Refuse to continue past 90:00: stop recording, keep the file, mark
  the lecture complete-at-cap (not failed).
- No file splitting in v1. Over-long sessions are a later phase.

### 6. Storage stays on this Mac

Same privacy story as History and Audio History:

- Audio lives in a private Application Support lecture directory. Like
  Audio History, the WAV is **not encrypted at rest**; protection is
  directory permissions plus explicit start/stop consent.
- Original transcript and summary are encrypted in the local vault with
  the same Keychain-backed key as dictation History.
- Lecture rows are not dictation History rows. Delete in one list does
  not delete the other.
- Nothing syncs. Nothing uploads except the opt-in summary text in §3.
- Delete a lecture removes its audio file, original, and summary.

## Out of scope for v1

- Zoom, Google Meet, Microsoft Teams, or any meeting-app integration
- System-audio / loopback capture
- Speaker diarization or teacher-vs-student labels
- Live paste of lecture text into another app
- Codex or any new cloud vendor
- Splitting sessions longer than 90 minutes

## Consequences

- Dictation behavior is unchanged until a later ADR says otherwise.
- Users who never open lecture capture gain no new network path and no
  new retained audio.
- Users who record a lecture have consented to keep that audio locally
  for that lecture, independent of the Audio History toggle.
- Implementation (Phases 1–5) starts only after this ADR is Accepted.

## Related decisions

- ADR 0001 — Local data and model governance
- ADR 0002 — Default local history and private capture
- ADR 0010 — Audio History
- ADR 0011 — Cloud AI Enhancement
