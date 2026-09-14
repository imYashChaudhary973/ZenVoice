# ADR 0016 — Meeting notetaker

## Status

**Accepted — 2026-09-12.** Phase 1 (local capture) is implemented in this
change. Later phases are in scope; they are not deferred out of the product.

## Context

ZenVoice 0.4.5 is dictation. Lecture capture (ADR 0014) shipped in 0.4.0 and
was removed in 0.4.5. The notetaker is a new session type with lecture-capture
invariants, written from scratch — not a restore of `LectureStore`.

The dictation hotkey stays paste-into-app. A meeting never pastes into the
call.

## Decision

### Invariants (from ADR 0014, kept)

1. One meeting is local audio, one **immutable original transcript**, and an
   optional **recap** in a separate field.
2. Start/stop is a meeting control, not the dictation hotkey.
3. Recap is opt-in BYO-key Cloud AI (ADR 0011 transport). Text only. Audio
   never leaves for recap.
4. Meeting audio is not a dictation History row. Delete in one list does not
   delete the other.
5. Ninety minutes is the Phase 1 ceiling. Stop at cap, keep the files.

### Capture

Two paths, same `MeetingStore` record:

- **Local.** App-scoped ScreenCaptureKit system audio (Them) plus microphone
  (You). macOS 14 converts SCK audio to 16 kHz mono; macOS 15 may use
  `captureMicrophone`. Echo cancellation is required when both streams run.
- **Bot.** A ZenVoice proxy joins Zoom / Meet / Teams as a visible participant.
  Phase 1 does not ship the bot; the store already records `captureSource`.

Meeting WAV is never sent to a cloud speech engine (`EngineIdentifiers.isCloudSpeech`).
Local engines only.

### Product surface (all in scope)

Auto-record, meeting bots, embeddings, Mail, Slack, ZenVoice proxy,
cross-meeting voiceprints, and meeting commands. Each later phase adds to
this ADR; none of those surfaces is out of scope.

Phase 1 ships: local You/Them capture, encrypted original, recap prompt,
History → Meetings, Privacy inventory, consent copy on Start.

### Identity

- Live labels are channel labels: `You` / `Them`.
- Named speakers and cross-meeting voiceprints are a later phase and a
  separate biometric gallery — not the dictation Voice Profile.
- Meet window-title matching is in-memory only and is never stored.

### Consent

Recording chrome is visible. Start copy tells the user to tell the room.
Auto-record (later) still posts a notification; it does not hide the indicator.

## Supersedes, for meeting mode only

- ADR 0014 out-of-scope: Zoom / Meet / Teams, loopback, diarization
- ADR 0011 / 0015: “no ZenVoice proxy” — proxy is required for bots and
  connector OAuth. Recap remains text-only on the existing Cloud transport
  until the proxy exists.
- ADR 0001: no window titles / no voiceprints — meeting mode may match Meet
  titles in memory and will add an explicit speaker gallery later.

Dictation is unchanged.

## Consequences

- Users who never open Meetings gain no new retained audio and no Screen
  Recording prompt until they tap Start.
- Screen Recording is required to capture Them. Without it, Phase 1 still
  records You (microphone) and labels the original accordingly.
- Implementation of bots, index, connectors, voiceprints, and commands
  starts when those phases are requested, against this ADR.

## Related

- ADR 0001, 0010, 0011, 0014, 0015
