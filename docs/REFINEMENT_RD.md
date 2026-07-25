# Refinement R&D

Where Instant Refine stands today, why it under-delivers, and the research
tracks that would close the gap with products like Wispr Flow.

This is an investigation document, not a commitment. Nothing here has shipped.
Section 0 is measured; sections 1–5 are analysis and proposals.

## 0. Measured baseline

`ZenVoiceAccuracyChecks`, `ggml-base.en`, Qwen 2.5 1.5B installed, 15 clips
(3 disfluent + 12 clean) through each mode:

```
refinement — disfluent speech (8 clips, refinement must help)
raw transcript                24.6%
after clean                   16.9%   -7.7 pts   2 changed, 0 rejected ( 0%)     8 ms
after agent prompt            16.9%   -7.7 pts   2 changed, 0 rejected ( 0%)     8 ms
after local model             16.9%   -7.7 pts   3 changed, 1 rejected (12%)  5044 ms

refinement — clean speech (12 clips, refinement must not meddle)
raw transcript                 5.4%
after clean                    5.4%   +0.0 pts   0 changed, 0 rejected ( 0%)    13 ms
after agent prompt             5.4%   +0.0 pts   0 changed, 0 rejected ( 0%)    12 ms
after local model              5.4%   +0.0 pts   0 changed, 8 rejected (67%)  6458 ms
```

Readings:

- **The local model contributes nothing.** Identical word error rate to Clean
  in both cohorts. On clean speech the guard rejects 67% of its candidates and
  the accepted third changes nothing measurable — acceptance requires exact
  token equality, so by construction those could differ only in punctuation
  and case.
- **It costs roughly half a second per dictation to do so.** 6458 ms across 12
  clips is ~540 ms each in steady state, against ~1 ms for the regex modes.
  (The disfluent cohort's 5044 ms runs first and absorbs the one-time model
  load.) That is a user-visible stall on every dictation, buying 0.0 points.
- **Semantic safety is clean today: zero violations across all modes.** That is
  the baseline Track A must not regress — the current design buys its
  uselessness honestly, and a more permissive guard has to keep this at zero.

### 0.1 Whisper already removes much of what Clean is aimed at

The unhandled-disfluency list is the most useful thing the run produced, and it
partly refutes the fixtures that produced it:

```
dis-doubled:        Please review the migration script before the release.
dis-discourse:      The API, you know, returns a cached response, like, when the token is valid.
dis-phrase-restart: We should probably revert the change before the release.
dis-negation:       Do not merge the branch. Ah, until the tests pass.
dis-quantity:       Increase the request time up to 30 seconds.
```

Five disfluent clips passed through every mode unchanged — but only **two** are
genuine refinement gaps:

- `dis-discourse` — "you know" and "like" survive. Clean's filler list is only
  `um|uh|erm`. A real miss, and the commonest fillers in English.
- `dis-negation` — Whisper wrote "Ah," which is not in that list either. A real
  miss, and a one-word fix.

The other three are not refinement failures at all. Whisper **already** deleted
the disfluency: "the the migration" came back as "the migration", and "We
should we should" as "We should", with no help from Clean. `dis-quantity` lost
its "um" the same way and what remains is a transcription error ("timeout" →
"time up"), which is not refinement's problem.

This matters more than the fixture bug it exposes. Whisper's decoder has a
language model and it normalizes away doubled words and hesitations on its own.
So some of the value Clean appears to be chasing is **already delivered
upstream**, and fixtures must be built from transcripts that demonstrably
*retain* their disfluencies or they measure nothing.

**Correction, from the literature.** The first draft of this section concluded
the headroom was broadly thin. That overstates it. Whisper's implicit
disfluency removal is a documented artifact of its training-data normalization,
but the specific finding is that it *"removes the ums and uhs"* while
*"transcrib[ing] most of the other disfluencies"*
([Cortico](https://cortico.ai/news/insights/evaluating-openai-s-whisper-on-community-conversations/),
[CrisperWhisper](https://arxiv.org/abs/2408.16589)). Repetitions and false
starts are supposed to survive — and ours did not.

The likely reason is the fixture medium, not the model. `say` renders "the the"
as two acoustically **identical** tokens, which is precisely the input a decoder
language model collapses; a human saying it produces two different durations
and pitches that survive decoding. So the three "already handled upstream"
clips are probably an artifact of synthesized speech, and the real headroom for
repetition and restart handling is larger than the measurement suggested.

That does not rescue those fixtures — it condemns them further. It also makes
real recordings the blocking dependency for Track A, since no synthetic fixture
can produce a realistic repetition, and it puts CrisperWhisper (section 7) on
the table as a way to get verbatim fixtures at all.

Corollary for Track H: if the headroom on word-level cleanup is thin, the
argument for a downloadable language model rests almost entirely on the
structure and formatting work (Tracks D and E), not on disfluency removal.

### 0.2 The two real gaps, fixed and re-measured

Both misses above were one-line rule gaps, so they were fixed directly rather
than deferred to Track A: `ah` and `hm` added to the filler stems, and
comma-bracketed `you know` / `like` / `sort of` / `kind of` removed. Removing a
sentence-opening filler left the next word lowercased, so Clean now
recapitalizes after a sentence break too.

```
                       before          after
disfluent raw          24.6%           24.6%
after clean            16.9%  -7.7     10.8%  -13.8 pts
clips changed          2 of 8          4 of 8
insertions             7               3
unhandled clips        5               3
clean-speech delta     +0.0            +0.0
semantic violations    0               0
```

The improvement refinement delivers on disfluent speech **roughly doubled**,
from 7.7 to 13.8 points, with no movement on clean speech and no semantic
violations. The three still-unhandled clips are exactly the three identified
above as not being refinement's problem — Whisper had already removed the
disfluency, or the residue is a transcription error.

Guarded in `ZenVoiceCoreChecks` by text-level cases rather than audio ones,
which is the right instrument: the TTS-to-Whisper round trip destroys the
disfluencies under test, which is what 0.1 is about. The negative cases are
pinned alongside the positive ones — "I like the way you know the answer" must
survive intact, and "err on the side of caution" must keep its verb, which is
why `er` is not a filler stem.

**Not fixed:** the local model still contributes 0.0 points and still costs
~540 ms per dictation, rejecting 67% of its own output on clean speech. No
rule change reaches that; it is the guard, and it is Track A.

The harness **passed** this run. Its only refinement assertion is
`delta > 2.0` — it fails when refinement makes the transcript worse and
asserts nothing about it helping. Instant Refine could be deleted entirely and
this test would stay green. A feature whose failure mode is silence needs a
two-sided test, and that absence is why this reached users unnoticed.

## 1. Diagnosis

### 1.1 The local-model guard forbids refinement

`LocalRefinementGuard.validatedCandidate` accepts a model candidate only when

```swift
tokens(in: candidate) == tokens(in: original)
```

This is exact token-sequence equality over alphanumeric tokens. The model may
therefore alter punctuation, capitalization, and whitespace — and nothing else.
It cannot delete a filler, repair a misheard word, expand a contraction, split
a run-on sentence, or reorder anything. Every substantive edit is rejected and
the pipeline falls back to deterministic Clean.

This single line explains most of "there is not much refinement happening."
The model is loaded, prompted, decoded under a JSON grammar, and then its work
is thrown away.

### 1.2 Clean is delete-only, so any insertion voids the whole transcript

`InstantRefineEngine.meaningIsPreserved` requires that every candidate token
appear in the original's token *vocabulary*. Consequences:

- No word may ever be introduced. Inverse text normalization
  ("twenty five percent" → "25%"), contraction handling, and connective repair
  are all structurally impossible.
- Rejection is all-or-nothing across the entire transcript. One disallowed edit
  in sentence nine discards the correct cleanup of sentences one through eight.

### 1.3 The deterministic rule set is very small

Clean applies four content regexes:

| Pattern | Covers |
| --- | --- |
| `(a\|an\|the) X , no wait , (a\|an\|the)` | punctuated article restarts |
| `X , no wait\|sorry\|i mean\|rather , Y` | punctuated single-word restarts |
| `um+\|uh+\|erm+` | three filler stems |
| `\b(word)\b (word)+` | immediate repetition |

Not covered: `you know`, `like`, `I mean` as filler, `basically`, `actually`,
`right?`, `so yeah`, `kind of` / `sort of`, stutters (`I-I-I`), un-punctuated
false starts, trailing `and so on`, restarts spanning more than four words.

The two restart patterns both require a comma or dash at the pivot. Whisper
frequently emits disfluent speech without that punctuation, so in practice
these fire far less often than the rule list suggests.

### 1.4 "Agent Prompt" is not an agent or a prompt

It is Clean plus two literal regexes mapping the spoken phrases `new line` and
`new paragraph` to line breaks. Users reading the mode name expect
instruction-following ("make this an email", "make this a bulleted list") and
receive filler removal. The name writes a cheque the implementation does not
honour.

### 1.5 There is no structure layer

Whisper returns one undifferentiated blob. Nothing in the pipeline produces
paragraph breaks, sentence segmentation, or lists. A 60-second dictation lands
as a wall of text. This is the single most visible difference against Wispr
Flow, which is perceived as "smart" largely because it returns *structured*
prose.

Note that `WhisperTranscriber.swift:130` iterates segments but reads only
`whisper_full_get_segment_text`. The `t0`/`t1` timestamps — the natural signal
for pause-derived structure — are already available from the runtime and are
being discarded.

### 1.6 The rewrite has no context

`ApplicationProfiles` selects a *mode* per bundle identifier, but the model
prompt itself receives only the transcript and an optional 500-character
next-dictation context. It does not know the target application, the window
title, the user's vocabulary, or any selected text. Wispr Flow's accuracy on
names and its tone-matching both come from exactly this context.

### 1.7 Personal vocabulary runs too late and matches too literally

`DictationVault.applyCorrections` runs *after* refinement as literal rule
substitution. Two problems:

- The refinement model never sees the user's vocabulary, so it cannot use
  "Chaudhary" to interpret a garbled token.
- Literal matching cannot repair the actual failure mode. Whisper writing
  "Yash Chowdhury" will not match a rule keyed on "Yash Chaudhary". Phonetic
  and edit-distance matching is required.

### 1.8 Runtime cost is paid on every dictation

`LocalTextRefiner.generate` calls `llama_init_from_model` and frees the context
on every single refinement. The system-prompt KV cache is never reused. The
model itself loads lazily inside the first `refine` call, so the first
dictation after launch pays a multi-hundred-millisecond to multi-second stall
inside the user-visible path.

Additional ceilings: `n_ctx` is 2048 and `maximumOutputTokens` is 192, so
anything beyond roughly 150 words either throws `promptTooLong` or truncates —
and both outcomes are indistinguishable from "refinement did nothing" to the
user.

### 1.9 Nothing is measured

`InstantRefineResult.wasRejected` is computed and then read nowhere outside
`ZenVoiceCore`. There is no counter, no log, and no UI surface. The guard
rejection rate for `.localModel` is, per section 1.1, almost certainly close to
100% — but the codebase cannot currently prove it.

`docs/ACCURACY_HARNESS.md` covers ASR only. There is no refinement eval set, so
no proposed change below can be shown to help.

## 2. What the comparison product actually does

Wispr Flow's refinement is a single LLM pass that is permitted to rewrite,
constrained by product rules rather than by token equality:

1. Disfluency and self-correction removal, semantically rather than by regex.
2. Punctuation and sentence segmentation.
3. Paragraph and list structure.
4. Context-conditioned formatting — email vs. chat vs. code comment, inferred
   from the focused application and surrounding text.
5. A personal dictionary injected into the rewrite, not applied after it.
6. Tone and register matching learned from the user's own history.

The gap is not model quality. It is that ZenVoice's safety architecture
converts the model into a punctuation formatter.

## 3. Research tracks

Ordered by expected impact per unit of effort.

### Track A — Replace the equality guard with an alignment guard (highest impact)

Equality is the wrong primitive. Replace it with a token alignment (Myers or
Levenshtein) between baseline and candidate, then classify each edit and accept
or reject *per edit* against a budget:

| Edit class | Default policy |
| --- | --- |
| Punctuation / case / whitespace | allow |
| Deletion of a listed disfluency | allow |
| Deletion of a content word | reject |
| Substitution, phonetically near (Double Metaphone + edit distance) | allow — this is the ASR-repair case |
| Substitution, phonetically distant | reject |
| Insertion of a closed-class function word | allow, bounded count |
| Insertion of an open-class word | reject |
| Any edit touching a negation, numeral, or dictionary term | reject |

The negation/numeral lock list is what preserves the current safety promise:
`not`, `no`, `never`, `don't`, `can't`, `without`, all digits and spelled
numerals, plus every user dictionary entry. These are the tokens where a
silent change is genuinely harmful.

**Sub-track A1 — reject per sentence, not per transcript.** Segment, refine,
and validate each sentence independently. One bad sentence should cost one
sentence, not the whole dictation. This is cheap and independently valuable.

**Sub-track A2 — tiered aggressiveness.** The budget becomes the actual
difference between modes: Clean = conservative budget, a new Rewrite mode =
generous budget with a visible indicator and one-keystroke revert to raw.

### Track B — Input-derived decoding grammar

Currently the GBNF grammar enforces only JSON shape, and semantic safety is
enforced afterwards by rejection. Invert this: build the grammar **from the
transcript at request time**, so the decoder can only emit tokens drawn from
the input (in order), plus punctuation, plus explicit skip operations.

The model then *physically cannot* invent a word, which means the post-hoc
guard can be relaxed to near-nothing without weakening the safety promise. It
also makes small models far more reliable, because the search space collapses.

This is the most technically interesting idea in this document and deserves a
spike before Track A hardens.

### Track C — Reformulate as tagging rather than free generation

A 0.5B model asked to rewrite freely under a JSON grammar is being asked for
the thing it is worst at. Reformulate as per-token classification —
`keep` / `drop` / `punct-after` — which is the standard formulation in the
disfluency-removal literature and is dramatically more stable at this size.

Downstream benefit: the output is an edit script, so the guard is trivial and
the UI can *show* what changed.

### Track D — Structure from prosody (cheap, high perceived value)

Surface `whisper_full_get_segment_t0/t1` through `TranscriptionResult`, then
derive structure deterministically from inter-segment gaps:

- gap > ~700 ms → sentence boundary
- gap > ~1.5 s → paragraph break
- `first … second … third` / `one … two … three` → list items

No model involved, no guard interaction beyond permitting whitespace, and it
directly attacks the wall-of-text problem from 1.5. `SpeechActivity.swift`
already models the noise floor, so the pause detection has a calibrated basis
rather than fixed thresholds.

Requires validating the gap thresholds against real dictations — speakers vary
widely, and the thresholds may need to adapt per user the way the noise floor
already does.

### Track E — Make "Agent Prompt" real

Replace the two-regex mode with user-defined named presets — Email, Slack,
Notes, Commit message, Prompt-for-an-LLM — each holding an editable
instruction, bindable per application through the existing
`ApplicationProfiles`. These run under Track A's generous budget tier with an
explicit "rewritten" indicator.

This is the feature users believe they already have.

### Track F — Context injection

Feed the refiner: focused application and window title, the user's dictionary
terms, the previous dictation, and — only with explicit permission and a
visible indicator — the current selection. Names and jargon are where local
refinement can beat a generic cloud model, and vocabulary is the lever.

### Track G — Vocabulary before refinement, matched phonetically

Move personal vocabulary ahead of the model rather than after it:

1. Inject dictionary terms into the Whisper `initialPrompt` (partly done today
   via next-dictation context) and into the refiner prompt.
2. Match transcript tokens against entries with Double Metaphone plus bounded
   edit distance, so "Chowdhury" resolves to "Chaudhary".
3. Lock the resulting terms in the Track A guard so nothing downstream may
   alter them.

### Track H — Model and runtime evaluation

- **Candidates:** Qwen 3 0.6B / 1.7B, Gemma 3 270M / 1B, Llama 3.2 1B,
  SmolLM2 360M. Qwen 2.5 0.5B is old for this task.
- **Fine-tuning:** a LoRA on synthetic disfluent→clean pairs will beat a much
  larger general model at this one narrow job, at a fraction of the latency.
  Generating that dataset is itself a work item, and is the same dataset the
  eval harness in Track I needs.
- **Apple Foundation Models:** macOS 26 exposes an on-device LLM with no
  download and no 500 MB catalogue entry. The package targets macOS 14, so this
  would be an availability-gated fast path, not a replacement. Worth a spike on
  quality and latency before committing further to llama.cpp for this stage.
- **Runtime:** persist the llama context across calls, prefill and cache the
  system-prompt KV, raise `n_ctx`, and chunk long transcripts by sentence so
  long dictations stop silently failing. Warm the model at launch rather than
  inside the first user-visible refinement.
- **Prompting:** the ChatML `<|im_start|>` delimiters are hardcoded in
  `LocalRefinementPrompt.make`, which will silently corrupt any future
  non-ChatML catalogue entry. Few-shot examples matter more than instructions
  at this parameter count.

### Track I — Measurement (prerequisite for everything above) — **in progress**

Nothing in Tracks A–H can be shown to work without this, so it landed first.

Done in `ZenVoiceAccuracyChecks`:

- **Cohorts split.** Disfluent and clean clips were pooled, so twelve clean
  clips (where every mode scores identically, correctly) diluted three
  disfluent ones. A mode doing nothing posted the same improvement as a mode
  that worked. Each cohort now asserts its own half of the contract.
- **Fixtures widened** from 3 to 8. The original three mapped one-to-one onto
  three of Clean's four regexes, making the suite self-fulfilling — it could
  only confirm that implemented rules run. The new ones sit deliberately
  outside that rule set: discourse markers (`you know`, `like`), phrase-level
  restarts, and a self-correction with no comma at the pivot.
- **`SemanticSafety`** counts protected tokens — negations, quantities, digits
  — altered between raw and refined, as an absolute count. Compared raw against
  refined rather than against the reference, so it holds regardless of what
  Whisper heard.
- **Rejection rate and per-stage latency** now reported per cohort.
- **The missing assertion**, that refinement must measurably help. Currently
  advisory behind `ZENVOICE_REFINE_STRICT=1`, because it fails today by
  design; enabling it is the definition of done for Track A, not a CI break to
  absorb beforehand.

- **Real recordings wired into the refinement section.** `Fixtures.corpus`
  and `ZENVOICE_ACCURACY_CORPUS` already existed for transcription; refinement
  now reads the same directory, as its own cohort. Drop `name.wav` beside
  `name.txt` — the `.txt` being the finished text the speaker wanted, not a
  transcript of every sound made — and point the variable at the folder. Real
  audio skips the synthetic gain/noise degradation.
- **Unhandled-disfluency list.** Any disfluent clip that no mode altered is
  printed with its transcript. An eight-clip average can look healthy while
  most of them pass through untouched, and that list is what Track A works from.

Known gap: bare "no" is excluded from the protected set, because it doubles as
a correction cue ("a login page, no wait, …") where deleting it is correct.
Protecting it everywhere would flag good refinement as a violation. The fix is
structural and belongs to Track A.

Still to do: Hinglish refinement coverage.

**Metrics:**

| Metric | Why |
| --- | --- |
| Disfluency removal F1 | did it remove what should go, keep what should stay |
| Semantic violations (count) | the safety metric — target zero, never a rate |
| Punctuation / capitalization F1 | the bulk of perceived polish |
| Paragraph boundary F1 | Track D |
| Guard rejection rate by reason | is the guard tuned or just refusing |
| Latency p50 / p95 | refinement sits in the user-visible path |

Semantic violations must be reported as an absolute count, not a rate. One
dropped negation in a thousand dictations is a product failure, and a
percentage will hide it.

## 4. What to preserve

The conservatism in the current design is a real asset and should survive the
rework:

- Local-only, no network, no API key.
- Never silently change a negation, a number, or a user's own vocabulary.
- Always fall back to something correct rather than failing loudly.
- Every model entry legally reviewed with a pinned revision and checksum.

The argument of this document is not that the guards are wrong in spirit. It is
that a binary token-equality check is too blunt an instrument to express them,
and it currently costs the feature its entire reason to exist.

## 6. Solving the local-model problem

The measured facts: 0.0 points contributed, ~540 ms per dictation, 67%
rejection on clean speech. Three separate defects are tangled together here,
and each has a different fix.

### 6.1 The literature agrees with the guard, and with why it fails

Generative error correction — handing an LLM an ASR transcript and asking for a
better one — has a documented failure mode that is exactly the one ZenVoice's
guard was built to prevent: *"a critical flaw in GEC is the hallucination issue
due to the complete rewriting of transcriptions, where entity phrases that are
not spoken can be mistakenly added."* The canonical example is a user saying
"I like algorithms" and the model, primed with a contact list, confidently
emitting *"I like Al Gore"*
([arXiv 2505.17410](https://arxiv.org/pdf/2505.17410)).

So the instinct behind the guard is correct and should not be softened on
vibes. What the literature also says is that binary equality is not how the
field solves it: *"unconstrained generation can hallucinate or over-correct;
constrained or closest-mapping approaches (e.g. mapping generation back to an
actual hypothesis via edit distance) balance creativity and fidelity"*, with
*"constrained decoding approaches based on the N-best list or an ASR lattice"*
as the mitigation. That is the alignment guard of Track A, arrived at
independently, plus one idea this document had missed.

### 6.2 The missed idea: constrain to the ASR lattice, not to the 1-best

The current design hands the refiner Whisper's single best hypothesis and then
forbids it from changing any word. That is why it cannot fix "timeout" → "time
up": the correct word is not in its input, and inventing it is exactly what the
guard exists to stop. Both constraints are individually right and jointly
useless.

Whisper produces an **N-best list as a byproduct of beam search** — alternative
sequences the acoustic model genuinely considered. Feeding those alternatives
to the refiner, and constraining its output to tokens drawn from *any* of them,
changes the shape of the problem:

- the model gains the power to fix misrecognitions, because the right word is
  now in its input;
- it gains no power to invent, because every token it may emit was something
  the acoustic model actually heard;
- the safety property strengthens rather than weakens — "did the acoustic model
  consider this?" is a better test than "is this the top hypothesis?"

This is the single highest-value change available, and it makes the difference
between a refiner that can only reformat and one that can genuinely repair.

Cost: `WhisperTranscriber` currently reads only `whisper_full_get_segment_text`
and discards everything else. N-best requires plumbing beam candidates out of
whisper.cpp, which is a real piece of work and should be spiked before being
committed to.

### 6.3 Input-derived grammar is mechanically supported

Track B assumed llama.cpp could constrain generation to the input's own tokens.
It can: GBNF *"can match specific tokenizer tokens directly, bypassing
character-level decoding"*, supports matching token IDs, and supports negation
([llama.cpp GBNF](https://deepwiki.com/qualcomm/llama.cpp/8.1-gbnf-grammars)).
So a grammar built at request time from the transcript's — or the lattice's —
token set is implementable rather than aspirational.

With that in place the decoder *physically cannot* emit an unspoken word, and
the post-hoc guard relaxes to checking edit budgets and protected tokens rather
than enforcing equality. Grammar construction is per-request work, so it should
be measured against the 540 ms budget below rather than assumed free.

### 6.4 The 540 ms is self-inflicted

`LocalTextRefiner.generate` calls `llama_init_from_model` and `llama_free` on
every refinement, so the KV cache — including the system prompt, which is
identical every single time — is built and thrown away per dictation. The
system prompt is the definition of a stable prefix, and llama.cpp's own server
exists to avoid exactly this: it *"checks the common prefix between the old and
new token sequences and skips prefill for the matching portion"*
([discussion #20574](https://github.com/ggml-org/llama.cpp/discussions/20574)).

In-process the fix is to hold one context open for the app's lifetime, prefill
the system prompt once, and reuse that KV prefix per dictation — the same
mechanism, without the server.

**This was implemented, and the hypothesis was wrong.** Tracing the refiner
per call:

```
prefix 72  tail 18  generated 17  prefill 109ms  total 1036ms   ← first call
prefix 72  tail 16  generated 15  prefill   1ms  total  855ms
prefix 72  tail 39  generated 38  prefill   1ms  total  747ms
prefix 72  tail 39  generated 38  prefill   1ms  total 1424ms
```

Prefix reuse works — prefill drops to 1 ms — but prefill was never the cost.
The instruction block is 72 tokens and cost ~109 ms *once*. Generation is
essentially all of the time, at **25–40 ms per token**. The ceiling on any
prefill optimization is therefore about 110 ms once per session, not 540 ms
per dictation.

Note also the last two rows: identical tail length, identical generated count,
747 ms against 1424 ms. Wall-clock on a working laptop carries ~2× variance on
identical work, so single-run A/B comparisons at this granularity cannot
resolve anything smaller than a factor of two. Latency claims in this document
need repeated runs and medians, and the earlier "540 ms" figure should be read
as an order of magnitude rather than a measurement.

### 6.4.1 The real latency constraint: the transcript is regenerated

The trace exposes something more important than the failed optimization.
Generated tokens track tail tokens almost exactly — 18→17, 39→38 — because the
design has the model **re-emit the entire transcript** inside a JSON envelope.
Latency is therefore linear in dictation length, at roughly 30 ms per token:

| dictation | ~tokens | ~generation |
| --- | --- | --- |
| 20 words | 27 | 0.8 s |
| 60 words | 80 | 2.4 s |
| 150 words | 200 | 6.0 s |
| 300 words | 400 | 12.0 s |

The five-second deadline lands at roughly 120 words. Past that the model is
killed mid-generation and the result silently falls back to Clean — which is
indistinguishable, from the user's side, from refinement doing nothing. The
2048-token context sets a second ceiling in the same region.

Two consequences:

1. **Apple Foundation Models does not fix this.** At ~30 tokens/second it is
   the same order of speed. It removes the download and the catalogue burden
   (6.5), but a full-transcript rewrite is just as slow there.
2. **Track C stops being a reliability preference and becomes a requirement.**
   Any design where the model re-emits the transcript is latency-bound by
   transcript length and cannot serve long dictation. The model must emit an
   *edit script* — tags, spans, or operations — whose length tracks the number
   of corrections rather than the length of the text. A transcript needing
   three fixes should cost three edits' worth of tokens whether it is twenty
   words or three hundred.

This reorders the plan: the tagging formulation is now the load-bearing piece,
and the N-best lattice work (6.2) should be designed to produce edits rather
than a rewritten string.

### 6.5 Apple Foundation Models may delete the problem outright

macOS 26 ships an on-device model of roughly 3B parameters behind the
Foundation Models framework, generating around 30 tokens/second, with
`session.prewarm()` cutting time-to-first-token by up to 40%
([Apple](https://machinelearning.apple.com/research/introducing-apple-foundation-models),
[Apple 2025 updates](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)).

Against the current path that is: no 1.1 GB download, no catalogue entry, no
checksum and licence review, no llama.cpp lifecycle, a model roughly 2–6× the
parameter count of the Qwen entries, and a supported prewarm API. The package
targets macOS 14, so this is an availability-gated fast path rather than a
replacement — but on macOS 26 it plausibly makes the entire download flow
unnecessary, and it should be spiked before more effort goes into the
llama.cpp path.

The open question a spike must answer is whether it supports constrained
decoding equivalent to GBNF. Without that, 6.2 and 6.3 do not transfer, and it
becomes a formatting engine only — which, per section 0.2, may still be where
the value is.

## 7. Verbatim transcription as an enabler

`CrisperWhisper` is a Whisper variant fine-tuned for verbatim output that
*"captures disfluencies, fillers, stutters, and false starts that the original
Whisper omits"*, using dynamic time warping over decoder cross-attention to
produce *"accurate timestamps even around disfluencies and pauses"*, at 6.66%
average WER across nine benchmarks
([arXiv 2408.16589](https://arxiv.org/abs/2408.16589),
[GitHub](https://github.com/nyrahealth/CrisperWhisper)).

It is interesting here for two reasons at once, both of which are current
blockers:

1. It gives refinement something to refine. Per 0.1, standard Whisper is
   quietly doing part of the job and hiding the rest of it.
2. Its timestamps are accurate *around pauses* specifically, which is precisely
   what Track D's prosodic structure depends on and what ordinary Whisper
   segment timestamps are worst at.

Against: it is large-v3 derived, so it is a heavier download than anything in
the current catalogue, and its licence and provenance need the same review
every catalogue entry gets before it goes anywhere near users. Worth evaluating
as a **harness-side reference decoder** first — where none of that applies —
to find out how much disfluency ordinary Whisper is actually hiding.

## 8. Revised pause thresholds for Track D

Track D proposed 700 ms for a sentence boundary and 1.5 s for a paragraph,
which the literature suggests is too conservative:

- 400–600 ms is a common line-break threshold, and one study used 575 ms for
  topic boundaries ([arXiv cs/0105037](https://arxiv.org/pdf/cs/0105037));
- pauses under ~250 ms are articulatory rather than intended, so that is the
  floor rather than the target;
- pause duration is *"an excellent criterion for segmentation, giving
  comparable or better performance than standard sentence boundaries"*
  ([arXiv cs/0006036](https://arxiv.org/pdf/cs/0006036)) — so this is a
  well-supported approach, not a heuristic hack.

The more useful finding is that modern work argues against fixed thresholds
entirely, in favour of adapting to the speaker. ZenVoice already has the right
shape for this: `SpeechActivity`'s noise floor drops instantly and rises slowly
to track the room. The same treatment applied to inter-segment gaps would adapt
to a fast talker versus a deliberate one, which a fixed 700 ms cannot.

Revised starting points: ~250 ms floor, 400–600 ms sentence boundary, and a
paragraph break at a multiple of the speaker's own running median gap rather
than a constant.

## 8.1 The harness is not yet a reliable instrument

Two runs of the *same binary* over the *same cached fixtures*:

| | run 1 | run 2 |
| --- | --- | --- |
| disfluent raw WER | 24.6% | 27.7% |
| clean raw WER | 5.4% | 4.0% |
| local model, disfluent | 8717 ms | 2967 ms |
| local model, clean | 13298 ms | 10372 ms |

Neither the accuracy nor the latency numbers are reproducible. Latency varies
by up to 3× and word error rate by more than a point, which is larger than most
of the effects this document is trying to measure.

Causes, in order of confidence:

- **Latency** — ordinary machine load. Confirmed within a single process: two
  calls with identical tail and generated-token counts took 747 ms and 1424 ms.
- **Accuracy** — `ggml-base.en` is under `beamSearchSizeCeilingBytes`, so it
  decodes with beam search, and `whisper_full_default_params` enables
  temperature fallback, which samples when a segment trips the entropy or
  logprob thresholds. Thread count also tracks `activeProcessorCount`, and
  multi-threaded float reductions do not have to associate identically run to
  run.

Consequences for everything above: single-run comparisons can only support
conclusions about large effects. The Clean improvement in 0.2 (7.7 → 13.8
points) is large enough to survive this, and is independently pinned by
deterministic text-level checks in `ZenVoiceCoreChecks` — which is the stronger
evidence and the reason those checks exist. Any *smaller* claim in this
document, including anything about the local model's contribution, needs
repeated runs and medians before it is trusted.

Fixing the instrument is now a prerequisite rather than a chore: pin the decode
temperature and thread count for harness runs, report medians over N runs, and
separate the accuracy measurement from the latency measurement so a busy
machine cannot move a correctness number.

### 8.2 Fixed

`WhisperTranscriber` gained an `isReproducible` option — off everywhere in the
app, on by default in the harness — which sets `temperature_inc = 0` to disable
the sampled re-decode and pins `n_threads` to 4. The harness now refines each
clip three times and reports the per-clip **median** rather than a sum, so one
scheduling stall cannot dominate. `ZENVOICE_ACCURACY_SAMPLED=1` measures the
shipping configuration instead; `ZENVOICE_REFINE_REPEATS` tunes the repeats.

Two consecutive runs now agree exactly:

| | run 1 | run 2 |
| --- | --- | --- |
| disfluent raw WER | 27.7% | 27.7% |
| after clean | 15.4% | 15.4% |
| clean raw WER | 4.0% | 4.0% |
| local model, disfluent | 262 ms/clip | 244 ms/clip |
| local model, clean | 539 ms/clip | 531 ms/clip |

Every accuracy figure is identical; latency varies by ~7% rather than 3×. The
median also vindicates the original estimate — 539 ms per clip on clean speech,
262 ms on the shorter disfluent clips, which is exactly the length-linear
behaviour 6.4.1 predicts.

### 8.3 What the deterministic decode revealed

Pinning the decode changed one entry in the unhandled list, and it reverses
part of 0.1. Both lines are the **raw transcript** of the same fixture — the
input to refinement, not its output — under the two decode configurations:

```
spoken by the fixture:  "We should we should probably revert the change …"

sampled decode:  We should we should → We should probably revert the change …
pinned decode:   We should we should probably revert the change …
```

This is not a regression. The pinned decode is the *more faithful*
transcription: the speaker really did say it twice, and now Whisper reports
that. Refinement's behaviour is unchanged — what changed is that the
disfluency now reaches it, and Clean fails to remove it.

So "Whisper already removed it" was an artifact of temperature fallback
resampling that segment, not a reliable property of the decoder. Phrase-level
repetition is a genuine refinement gap after all: Clean's repetition regex is
single-token (`\b(word)\b (word)+`) and cannot see a repeated *phrase*.

The disfluent cohort's raw word error rate rising from 24.6% to 27.7% is the
same effect and equally not a degradation. Raw transcripts in that cohort are
scored against the *cleaned* reference, so a more verbatim transcript
necessarily scores worse. That number measures how much work is left for
refinement, not how well the model heard.

### 8.4 Phrase-level restarts, fixed

The gap 8.3 exposed, closed. Clean now collapses a repeated *phrase* — bounded
at two to four words, blocked by a line break or by punctuation between the
halves, so "New York, New York" and "come on, come on" survive as the
deliberate repeats they are.

```
                       before          after
disfluent raw          27.7%           27.7%
after clean            15.4%  -12.3     12.3%  -15.4 pts
clips changed          4 of 8          5 of 8
insertions             6               4
unhandled clips        3               2
clean-speech delta     +0.0            +0.0
semantic violations    0               0
```

Pinned by four text-level checks, which matter more than the harness number:
the restart collapses, a *tripled* restart collapses to one rather than two,
a non-adjacent recurrence ("the more you test the more you learn") survives,
and a punctuated deliberate repeat survives.

### 8.5 The instrument caught its first real change

Re-running after the fix reproduced every figure exactly — OVERALL, long-form,
and both refinement cohorts — confirming 8.2 holds across the whole harness
rather than only the section originally compared.

That reproducibility immediately paid for itself. Between two runs the
transcription section moved (whole 5.4% → 4.7%, segmentation cost
0.0 → +2.4 pts) with no committed change to transcription. Because the harness
is now deterministic, that shift had to have a cause, and it did: parallel work
in the tree added `WhisperDecoding.leadInSilenceSeconds` and made
`WhisperTranscriber` pad every recording with half a second of silence.

Worth flagging to whoever owns that change: the padding improves
whole-recording word error rate but moves segmented decoding the other way,
turning a 0.0-point segmentation cost into +2.4. The release path decodes
whole, so this is not urgent, but live preview does not.

Under the old sampled decode this would have been invisible — indistinguishable
from the ±1 point the harness produced on its own.

This is the first real gap the harness has surfaced under conditions where its
answer can be trusted, and it is directly actionable. Single-word repetition
("the the") is still collapsed by the decoder, and `dis-quantity` remains a
transcription error rather than a refinement problem — so of the three
originally dismissed, one comes back as a true defect.

## 9. Suggested sequence

Revised after the section 6–8 research. The ordering changed in two places:
latency work moved up because it turned out to be cheap, and the guard rework
moved behind real recordings because 0.1 showed synthetic fixtures cannot
validate it.

1. **Done** — Track I: cohort split, widened fixtures, semantic safety,
   rejection and latency reporting, the missing assertion.
2. **Done** — the two measured Clean gaps (0.2).
3. **Done, and it did not pay off** — context reuse and launch warming (6.4).
   Implemented and correct: prefill is now 1 ms. But prefill was never the
   cost, so the win is ~110 ms once per session rather than 540 ms per
   dictation. Kept because it is correct and removes per-call context
   allocation, not because it moved the number.
4. **Make the harness reproducible** (8.1). Now blocking. The instrument
   currently has 3× latency variance and >1 point of WER variance between
   identical runs, which is larger than most remaining effects. Nothing after
   this step can be evaluated until it is fixed.
5. **Redesign the refiner to emit edits, not text** (6.4.1). Promoted to the
   top of the model work. Regenerating the transcript makes latency linear in
   dictation length and puts anything past ~120 words beyond the deadline, so
   no choice of model or runtime rescues the current shape.
6. **Apple Foundation Models spike** (6.5). Still worth answering for the
   download and catalogue burden, but demoted: at ~30 tokens/second it does
   not solve 6.4.1, so it is no longer a potential shortcut past the
   architectural work.
5. **Real recordings** into `ZENVOICE_ACCURACY_CORPUS`. Now a blocking
   dependency rather than a nice-to-have — per 0.1, synthetic speech cannot
   produce a realistic repetition, so Track A cannot be validated without it.
   CrisperWhisper as a harness-side reference decoder (section 7) to quantify
   how much ordinary Whisper is hiding.
6. **Track D** — prosodic structure, with the revised adaptive thresholds from
   section 8. Still independent of the guard, still low risk, and now the
   likeliest home of the local model's justification.
7. **N-best lattice spike** (6.2). The highest-value change to what refinement
   can actually do, and the one that turns the model from a reformatter into a
   repairer. Gated on plumbing beam candidates out of whisper.cpp.
8. **Track A** — alignment guard, per-sentence rejection, tiered budgets,
   constrained to the lattice from step 7. Enabling
   `ZENVOICE_REFINE_STRICT=1` is the definition of done.
9. **Tracks E, F, G** — the product-visible layer, once the guard supports them.
