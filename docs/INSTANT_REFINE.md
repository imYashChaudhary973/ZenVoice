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
- **Clean:** removes standalone fillers, immediately repeated words, and
  punctuation-marked spoken restarts such as “a login page, no wait, a sign-up
  page.”
- **Agent Prompt:** includes Clean behavior and honors the explicit spoken
  commands “new line” and “new paragraph.”

Clean is the default. The selected mode is stored in local user defaults.
Instant Refine runs after recording stops and before text is saved or pasted.
Private Dictation uses the same in-memory refinement but stores no transcript.

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

## Model responsibilities

Whisper models convert audio into text. They are not general-purpose rewriting
models. The current Instant Refine foundation therefore does not pretend that
a speech model can perform semantic editing.

Downloadable text-refinement models are a separate future catalogue. Before
one appears in ZenVoice, its publisher, source, revision, licence,
redistribution rights, size, checksum, runtime format, hardware requirements,
latency, and meaning-preservation behavior must be approved independently.

## Next guarded stages

1. Measure partial-transcription stability and end-to-end latency.
2. Keep unstable words in ZenBar instead of the target application.
3. Commit a corrected phrase only after it is stable or the user pauses.
4. Add a legally reviewed local text-model catalogue.
5. Require structured output, a timeout, an edit-distance limit, and automatic
   fallback to deterministic refinement for every generative model.

ZenVoice will not continuously replace text inside another application until
focus changes, cursor movement, undo behavior, and application compatibility
have reliable tests.
