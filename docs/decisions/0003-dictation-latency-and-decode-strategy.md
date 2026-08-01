# ADR 0003: Dictation Latency and Decode Strategy

- Status: Accepted
- Date: 2026-07-29

## Context

ZenVoice was spending measurable time and battery on work that did not improve
the transcript, and in one case actively degraded it. Three costs were
identified and measured against `ZenVoiceAccuracyChecks` on
whisper-large-v3-turbo:

- Live preview decoded every pause-delimited fragment with the selected model,
  and the finished recording was then decoded again in a single pass. Both share
  one serial queue, so the accurate decode could not begin until the last
  preview drained.
- Model load and Metal pipeline construction happened inside the *first*
  `transcribe` call — after the user had already stopped talking.
- The encoder ran across whisper's full 30-second window on every dictation
  regardless of length.

## Decision

### Live preview is opt-in, not default

Measured on twelve clips:

|                | word error rate | decode time |
| -------------- | --------------- | ----------- |
| whole recording| 3.0%            | 11.13s      |
| segmented      | 3.4%            | 28.39s      |

Segmented decoding costs 2.55x the compute to be less accurate, because words
either side of a cut lose their context. The absent preference now reads as
off. Crash recovery is unaffected: recovery audio is written before the recorder
consults the preference at all.

Commit-on-pause remains available, and still requires preview.

### The model is warmed before it is needed

`WhisperTranscriber.warmUp()` loads the context and runs a throwaway decode of
silence, dispatched on the serial transcription queue at launch, on model swap,
and on entry to a recording. This mirrors what `ParakeetTranscriberEngine`
already did at construction.

Measured on whisper-large-v3-turbo: warm-up absorbs 1.08s, after which the first
decode takes 0.83s — identical to the second. That 1.08s previously landed on
the user's first dictation of every session.

### `audio_ctx` stays at the model default — rejected

Scaling the encoder window to the audio, with 50% headroom over what the speech
occupied, is dramatically faster and unusable:

|                     | before | after  |
| ------------------- | ------ | ------ |
| decode, whole       | 10.90s | 6.44s  |
| decode, segmented   | 27.96s | 10.28s |
| synthetic whole WER | 3.0%   | 24.2%  |
| synthetic segmented | 3.4%   | 125.6% |
| clean speech WER    | 3.0%   | 29.3%  |
| Hinglish loanwords  | 4/26   | 0/26   |

The decoder cross-attends to an encoding that stops before the utterance does
and loops on the last thing it is confident about, repeating whole clauses or
degenerating into fragments. Hindi transliteration was dropped entirely.
Fabricated text is the worst failure mode a dictation tool has, because the user
may never notice words they did not say.

Flash attention was tested as the suspected cause and exonerated: with
`flash_attn` off the repetition is cleaner but reaches 218% and 520% word error
rate on individual clips. The model requires the window it was trained on.

### P-core thread pinning — rejected

`n_threads` was expected to benefit from excluding efficiency cores. Measured on
a 4P/6E machine: 8 threads 11.02s, 4 threads 11.10s. No difference beyond noise.
The encoder runs on Metal, so the thread count barely participates. The
whole-machine count stands.

## Consequences

- A dictation is decoded exactly once by default, and the model is already built
  when the user stops talking.
- Users who want live text must switch it on and accept the stated cost.
- Both rejected optimisations are recorded in code — `WhisperDecoding` and
  `ProcessorTopology` — so the next person to have either idea finds the
  measurement rather than repeating the experiment.
- `ZENVOICE_DECODE_THREADS` remains available for re-measuring thread count on
  other hardware.
