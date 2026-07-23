# ADR 0002: Default Local History and Private Capture

- Status: Accepted
- Date: 2026-07-23
- Supersedes: ADR 0001 local-history consent and retention-period decisions

## Decision

- ZenVoice saves every successful or usable partial transcript to its encrypted
  local vault by default.
- Transcript history has no automatic expiry. Only the user can delete it.
- Fully failed transcription audio may be retained for retry for at most 24
  hours from capture start. Disabling recovery deletes audio already retained.
  Successful and partial transcription audio is deleted.
- History rows are Copy-only. Paste-last remains an explicit global shortcut
  and menu action.
- Private Dictation can be toggled with a configurable shortcut. While active,
  transcript and audio persistence is disabled, including for a capture already
  recording or transcribing.
- Hold-to-dictate is optional and disabled by default. It supports Fn and
  right-side modifier keys so normal character entry is not intercepted.

## Consequences

- The app opens and maintains the vault at launch so interrupted work and
  expired recovery audio are handled even when new history saving is paused.
- Privacy changes must revoke persistence for in-flight work.
- In-flight privacy revocation is persisted before completion so relaunch
  recovery cannot restore a Private Dictation record after a crash.
- Local insights planned for M6 and M7 can use the encrypted transcript history,
  but are not part of M2.
