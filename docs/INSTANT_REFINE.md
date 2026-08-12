# Instant Refine

Instant Refine is the local text-processing stage between speech transcription
and personal correction rules.

Paragraph breaks come before any of this, from the speaker's own pauses.

```text
Local audio
  → selected local speech runtime
  → conservative transcript cleanup
  → Instant Refine
  → encrypted personal correction rules
  → clipboard and optional paste
```

## Current modes

- **Off:** preserves the cleaned speech transcript.
- **Clean:** removes standalone fillers (`um`, `uh`, `erm`, `ah`, `hm`),
  comma-bracketed discourse markers such as “, you know,” and “, like,”,
  immediately repeated words, and punctuation-marked spoken restarts such as
  “a login page, no wait, a sign-up page.” It also recapitalizes a sentence
  whose opening filler it removed.

  Discourse markers are removed only when the speaker's own pauses bracket
  them in commas, because `like` and `you know` are ordinary words elsewhere —
  “I like the way you know the answer” is left alone. `er` is not treated as a
  filler at all, so “err on the side of caution” keeps its verb.

  Hindi is covered by the same rules. The repetition patterns are script
  neutral, but only after their character classes were widened to admit
  combining marks — a Devanagari vowel sign is a mark rather than a letter, so
  the classes used to break a word in half and no Hindi repeat could ever
  match. Hindi hesitation sounds (उम्म, अम्म, अअअ) and the stalling phrase
  “वो क्या कहते हैं” are removed alongside their English counterparts. Measured
  on 400 human-annotated Hindi pairs, this took refinement from 0.5 points of
  improvement to 8.2.
- **Agent Prompt:** includes Clean behavior and honors the explicit spoken
  commands “new line” and “new paragraph.”
There is no language-model mode. There used to be, and it was removed rather
than kept for later: measured against 400 human-annotated disfluent/fluent
pairs, the deterministic rules cut word error rate from 23.2% to 7.2%, and the
model added **0.0** on top of that. An oracle allowed to read the reference
would have added 0.1. There was no work left for a model to do, so the
download, the wait and the `llama.cpp` dependency were all buying nothing.

The investigation that settled this — five architectures tried, each measured
and each rejected — is not kept as a document: the conclusion is the code, and
the numbers above are the part worth carrying.

Clean is the default. The selected mode is stored in local user defaults.
Instant Refine runs after recording stops and before text is saved or pasted.
Private Dictation uses the same in-memory refinement but stores no transcript.

## Application-aware behavior

An application profile is keyed only by the target app's bundle identifier.
It can choose a language profile, an Instant Refine mode, and whether local
voice commands are enabled. ZenVoice resolves the profile when recording
starts and keeps that choice fixed for the entire recording, including stable
phrase previews.

The optional next-dictation context accepts up to 500 characters of names,
product terms, or topic hints. It is sanitized, passed only to the in-process
speech runtime, never written to settings or History, and cleared when
recording successfully starts.

Local voice commands are deterministic and run before Instant Refine. The
reviewed commands are new line, new paragraph, comma, full stop, question
mark, and exclamation mark. English controls work with every language
profile. Reviewed aliases are also included for Hindi, Spanish, French,
Mandarin, and Arabic; other language profiles remain supported for
transcription while their native command vocabulary is still preview work.

## Meaning guard

The built-in engine is deterministic:

- it has no network client and uses no account or API key;
- it can remove or reformat only reviewed patterns;
- it cannot introduce a semantic word that was not present in the input;
- it rejects the entire refinement if a five-word-or-longer transcript would
  lose more than half of its tokens;
- personal correction rules run afterward, so user-approved names and
  technical terms remain explicit and encrypted.

If the guard rejects a candidate, ZenVoice uses the original cleaned speech
transcript.

## Model responsibilities

Speech models convert audio into text. They are not general-purpose rewriting
models. Instant Refine therefore uses only deterministic application code and
has no downloadable refinement-model catalogue. The former M14 Qwen/llama.cpp
path was measured, contributed no useful accuracy beyond deterministic rules,
and was removed. Current speech-model provenance and verification remain in the
[Verified Model Catalogue](MODEL_CATALOG.md).

## Next guarded stages

1. Measure real-language correction quality and end-to-end latency.
2. Tune Fast versus Balanced recommendations from local benchmark evidence.
3. Expand native voice-command aliases only after spoken-language QA.
4. Add new model entries only after the complete legal and integrity review.
5. Keep live commit-on-pause opt-in until duplicate-free insertion is proven
   across supported target applications.

ZenVoice will not continuously replace text inside another application until
focus changes, cursor movement, undo behavior, and application compatibility
have reliable tests.

## Paragraph structure

A minute of dictation used to arrive as one unbroken block. Breaks now come
from the speaker's pauses, which is a fact about the recording rather than a
judgement about the words — no model is involved.

Two obstacles had to be cleared, both invisible until measured:

- `no_timestamps` was on, so Whisper returned the whole recording as a single
  segment spanning its full window. There was nothing to align text against.
- With timestamps on, Whisper's segments *abut*: `t1` of one equals `t0` of
  the next, so every gap computes as zero even across a pause of a second and
  a half. The segment times align text to the recording but do not contain the
  silence.

So the pauses are measured from the audio, using the same adaptive noise floor
as live dictation, and matched against the segment boundaries. The threshold
adapts to the speaker — 2.5× their median silence, clamped to between 0.9 s
and 3.0 s — because the research consensus is against fixed thresholds and a
deliberate talker means something different by a one-second pause than a fast
one does.

A break is only taken where the previous segment ended on a full stop. A pause
mid-sentence is someone hesitating, not starting a new thought.

Still to calibrate: the thresholds are set from literature and synthetic
fixtures whose 1.4 s pauses were chosen for a different purpose. Real
recordings should set them.
