# ZenVoice

ZenVoice is a local-first macOS dictation app. Press a global hotkey, speak,
and the transcript is produced by `whisper.cpp` on your Mac before being pasted
into the active application.

## Current MVP

- `Control + Option + Space` toggles recording.
- ZenBar shows Ready, Listening, Transcribing, Inserting, Done, and Error states.
- Audio is recorded as a temporary local WAV file.
- `whisper-cli` performs transcription with a local model.
- The transcript is copied to the clipboard and pasted into the active app.
- There are no accounts, network calls, subscriptions, analytics, or cloud fallbacks.

## Requirements

- macOS 14 or newer
- Apple Silicon
- Swift 5.10 or newer
- [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp)
- A local GGML Whisper model

The app searches for:

1. `ZENVOICE_MODEL_PATH`
2. `~/Library/Application Support/ZenVoice/Models/ggml-base.en.bin`
3. `~/Library/Application Support/Zero/models/ggml-base.en.bin`

It searches for `whisper-cli` at `ZENVOICE_WHISPER_PATH`,
`/opt/homebrew/bin/whisper-cli`, then `/usr/local/bin/whisper-cli`.

## Build

```bash
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh
open build/ZenVoice.app
```

On first use, macOS asks for:

- **Microphone**: required to capture speech.
- **Accessibility**: required only for automatic `Command + V`.

If Accessibility permission is unavailable, ZenVoice still puts the transcript
on the clipboard.

## Verify

```bash
swift run ZenVoiceCoreChecks
swift build
```

Then open TextEdit, place the cursor in a document, press
`Control + Option + Space`, speak, and press the shortcut again.

## Privacy boundary

The current code launches only the local `whisper-cli` process. Temporary audio
is deleted immediately after transcription. The text remains on the macOS
clipboard so it can be recovered if automatic paste fails.

## Next milestones

1. Keep the Whisper model loaded for lower latency.
2. Add configurable hotkeys and microphone selection.
3. Add a local dictionary and snippet expansion.
4. Add optional local-only rewriting through Ollama.
5. Add multilingual model selection.
