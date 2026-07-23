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
- **Local Model:** runs the selected verified Qwen model through the bundled
  local `llama.cpp` runtime, then accepts its JSON result only if the meaning
  guard passes. Any unavailable, malformed, unsafe, or timed-out result falls
  back to Clean.

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

The downloadable local-model mode adds stricter boundaries:

- generation is grammar-constrained to `{"text":"..."}`;
- output cannot introduce a normalized word absent from the transcript;
- a five-word-or-longer result must retain at least 60 percent of its tokens;
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
3. Add new model entries only after the complete legal and integrity review.
4. Keep live commit-on-pause opt-in until duplicate-free insertion is proven
   across supported target applications.

ZenVoice will not continuously replace text inside another application until
focus changes, cursor movement, undo behavior, and application compatibility
have reliable tests.
