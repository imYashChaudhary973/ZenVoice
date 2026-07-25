# Instant Refine

Instant Refine is the local text-processing stage between Whisper
transcription and personal correction rules.

```text
Local audio
  → selected local Whisper model
  → conservative transcript cleanup
  → Instant Refine
  → encrypted personal correction rules
  → clipboard and optional paste
```

## Current modes

- **Off:** preserves the cleaned Whisper transcript.
- **Clean:** removes standalone fillers (`um`, `uh`, `erm`, `ah`, `hm`),
  comma-bracketed discourse markers such as “, you know,” and “, like,”,
  immediately repeated words, and punctuation-marked spoken restarts such as
  “a login page, no wait, a sign-up page.” It also recapitalizes a sentence
  whose opening filler it removed.

  Discourse markers are removed only when the speaker's own pauses bracket
  them in commas, because `like` and `you know` are ordinary words elsewhere —
  “I like the way you know the answer” is left alone. `er` is not treated as a
  filler at all, so “err on the side of caution” keeps its verb.
- **Agent Prompt:** includes Clean behavior and honors the explicit spoken
  commands “new line” and “new paragraph.”
There is no language-model mode. There used to be, and it was removed rather
than kept for later: measured against 400 human-annotated disfluent/fluent
pairs, the deterministic rules cut word error rate from 23.2% to 7.2%, and the
model added **0.0** on top of that. An oracle allowed to read the reference
would have added 0.1. There was no work left for a model to do, so the
download, the wait and the `llama.cpp` dependency were all buying nothing.

The full investigation, including the five architectures tried and why each
failed, is in [Refinement R&D](REFINEMENT_RD.md).

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
Whisper and local-refinement runtimes, never written to settings or History,
and cleared when recording successfully starts.

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

If the guard rejects a candidate, ZenVoice uses the original cleaned Whisper
transcript.

The downloadable local-model mode applies deterministic Clean first, then adds
stricter boundaries:

- generation is grammar-constrained to `{"text":"..."}`;
- output must preserve every normalized word in the same order, so the model
  cannot drop a negation, duplicate words, or reorder a sentence;
- output length is bounded and generation has a five-second deadline;
- the model keeps the spoken language and is forbidden from translating;
- failure always falls back to deterministic Clean refinement.

## Model responsibilities

Whisper models convert audio into text. They are not general-purpose rewriting
models. The current Instant Refine foundation therefore does not pretend that
a speech model can perform semantic editing.

The M14 refinement catalogue is independent from speech-model selection. Its
publisher, source, immutable revision, licence, size, checksum, runtime format,
hardware requirements, and language claims are recorded in
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
