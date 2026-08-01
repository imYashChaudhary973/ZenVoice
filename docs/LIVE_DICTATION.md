# Live Dictation

M13 adds local stable-phrase preview and an optional commit-on-pause insertion
mode. Both reuse the selected Whisper model and Instant Refine settings.

**Both are off by default.** Preview decodes every pause-delimited fragment with
the selected model, and the finished recording is then decoded again in a single
pass. The two share one serial queue, so the accurate decode cannot begin until
the last preview drains — twice the compute and twice the battery, spent on
fragments that transcribe measurably worse than the whole utterance. The
default path decodes the recording once, at the end.

## Stability boundary

ZenVoice does not treat every changing token as final. It waits for:

- at least 450 milliseconds of detected speech; and
- at least 700 milliseconds of following silence.

The completed phrase is then transcribed on the existing serial Whisper queue.
Only that stable phrase appears in ZenBar. Continuous speech remains recording
audio and is handled at the next pause or final stop.

## Commit on pause

**Paste stable phrases on pause is experimental and off by default.** When the
user enables it, ZenVoice pastes a stable phrase only if:

1. Accessibility permission is still available.
2. The application active at dictation start is still the active application.
3. The session has not already hit a streaming-insertion safety failure.

If any guard fails, ZenVoice stops incremental insertion for that dictation and
holds the remaining text for final stop. It never redirects a stable phrase to
a different foreground app.

## Final stop and recovery

Final stop invalidates any in-flight preview and transcribes all samples after
the last accepted phrase. ZenVoice combines stable and remaining text for the
authoritative History record. Text already inserted during stable commits is
not inserted again.

Each accepted stable phrase is encrypted into the active local History record
with `isPartial = true` while recording continues. A crash or microphone
disconnect can therefore retain usable text in addition to recovery audio.
Private Dictation and paused History never write these partials.

## Resource behavior

- Live preview is off by default.
- Commit on pause is off by default.
- Turning live preview off also turns commit on pause off.
- With preview off nothing is captured in memory, no preview decode is queued,
  and the recording is decoded exactly once.
- In-memory live samples are captured only for a recording that starts with
  live preview enabled, then released when that recording stops.
- Preview and final transcription share one serial Whisper queue so the model
  context is never used concurrently.

## Manual QA still required

- Speak two phrases separated by a natural pause and confirm only the first
  stable phrase appears before the second pause.
- Enable commit on pause in a disposable document and verify no duplicate text
  is inserted at final stop.
- Change the foreground app during a pause and confirm incremental insertion
  stops rather than pasting into the new app.
- Force quit after a stable phrase and confirm encrypted partial text appears
  in History according to the recovery policy.
- Repeat with English, Hinglish, and one native-script language.
