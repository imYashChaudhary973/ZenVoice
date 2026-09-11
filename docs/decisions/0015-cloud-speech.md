# ADR 0015 — Cloud speech-to-text (BYO-key)

## Status

Accepted — Phases 1–4 (OpenAI + Gemini transcribe).

## Context

ZenVoice's default path is on-device. ADR 0011 added optional cloud
**text** cleanup and promised audio never leaves the Mac.

Users also want hosted speech models (OpenAI transcribe, later Gemini)
because they are fast and accurate. That is a different trust boundary:
**the recording leaves this Mac.**

Grok (xAI) has no public transcription API at the time of this decision
and is not an STT engine.

## Decision

1. Cloud STT is a `SpeechEngine`, selectable next to Parakeet and Whisper.
2. Off until the user stores a key **and** taps Use on that engine.
3. Bring-your-own key. No ZenVoice proxy. Keychain, not `UserDefaults`.
4. Recording stays local. On stop, the wav is uploaded once. No live stream.
5. Cloud is never a silent fallback for a local engine. Local **is** the
   fallback if the selected cloud engine fails.
6. The request body is the audio file, model id, and optional language.
   Nothing else.
7. ADR 0011 still holds for Cloud Formatting: that path still must not send
   audio. When the speech engine was already cloud, skip Formatting's second
   network hop so insert stays fast.

## Consequences

- Default install unchanged.
- Choosing OpenAI Transcribe is an explicit "audio leaves this Mac" choice.
- Private Dictation still skips history; it does not block the upload if
  that engine is selected.
- Gemini and any future Grok STT add engines, not a second architecture.
