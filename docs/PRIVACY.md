# Privacy

## Current privacy promise

ZenVoice's current transcription pipeline is local. Application code does not
send audio, transcripts, clipboard contents, or usage analytics over the
network.

## Data lifecycle

### Microphone audio

- Recorded as a temporary 16 kHz mono WAV file.
- Read by the local `whisper-cli` process.
- Deleted immediately after success or failure on a best-effort basis.
- A crash or forced termination could leave a temporary file until macOS cleans
  its temporary directory.

### Transcripts

- Stored in memory as the last transcript for recovery.
- Written to the macOS clipboard before insertion.
- Remain on the clipboard until another application replaces them.
- Not persisted to a ZenVoice history database.

### Models and configuration

- Whisper models remain in the user's local Application Support directory.
- Runtime paths can be overridden with local environment variables.
- No API key or online account is required.

## macOS permissions

- **Microphone** is required to record speech.
- **Accessibility** is required only to simulate `Command + V`.

If Accessibility permission is denied, transcription still works and the result
is copied to the clipboard.

## Security boundaries

Local-first does not mean risk-free:

- Other applications may be able to inspect clipboard contents.
- A configured `ZENVOICE_WHISPER_PATH` is executed as a local process; only set
  it to software you trust.
- Ad-hoc signing is appropriate for local development, not public distribution.

Before public release, the project should add hardened runtime configuration,
Developer ID signing, notarization, dependency review, and a documented update
mechanism.
