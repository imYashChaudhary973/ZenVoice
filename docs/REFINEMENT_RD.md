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
So a meaningful part of the value Clean appears to be chasing is **already
delivered upstream**, and the true headroom for a refinement layer on clean
English dictation is smaller than section 1 assumes. It also means fixtures
must be built from transcripts that demonstrably *retain* their disfluencies,
or they measure nothing — and it sharpens the case for real recordings, where
hesitation is messier and less normalizable than anything `say` produces.

Corollary for Track H: if the headroom on word-level cleanup is thin, the
argument for a downloadable language model rests almost entirely on the
structure and formatting work (Tracks D and E), not on disfluency removal.

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

## 5. Suggested sequence

1. Track I step 0 — instrument rejection rate and latency. Confirms 1.1.
2. Track D — prosodic structure. Independent of the guard work, immediately
   visible, low risk.
3. Track I — build the eval set.
4. Track B spike — input-derived grammar. If it works it simplifies Track A.
5. Track A — alignment guard, per-sentence rejection, tiered budgets.
6. Tracks E, F, G — the product-visible layer, once the guard can support them.
7. Track H — model and runtime, guided by the harness.
