# Implementation Plan

Ordered so that each phase is independently shippable and measurable. Phase 0
comes first because without it no later phase can be shown to have helped.

Effort estimates assume familiarity with this codebase.

---

## Phase 0 — Measurement (blocking)

**Goal:** be able to say "this change moved Hinglish WER from X to Y".

Nothing here improves quality. It makes every later phase falsifiable. Full
design in [04-evaluation.md](04-evaluation.md).

| Task | Files | Effort |
|---|---|---|
| Record ~30 Hinglish utterances with reference transcripts | `Tests/Fixtures/hinglish/` | 3 h |
| Hinglish-aware WER with spelling normalization | new `HinglishMetrics.swift` | 4 h |
| Loanword-preservation metric (see [04](04-evaluation.md#loanword)) | same | 2 h |
| Offline benchmark runner over fixtures × models | new `ZenVoiceHinglishBench` target | 4 h |
| Baseline numbers for current config | — | 1 h |

**Exit criterion:** one command prints WER, CER and loanword-preservation for a
given model + profile, and the current pipeline's baseline is recorded.

**Risk:** the fixture set is small and personal, so it measures *this user's*
Hinglish. That is the right target for a personal dictation tool but must not be
mistaken for a general benchmark.

---

## Phase 1 — Stop the bleeding (no new model architecture)

Cheap, low-risk, mostly independent of each other.

### 1a. Enforce profile↔model compatibility — **Critical**

[Finding 3](01-diagnosis.md#f3): the machine is on `whisper-medium-en` with an
English profile while trying to dictate Hinglish. `isCompatible(with:)` exists;
verify it is actually enforced where a profile and model meet, not merely used to
filter a picker.

- Selecting the Hinglish profile with an `.en` model must be impossible
- On load, an incompatible pair must self-correct and say so, following the
  pattern established for hot keys — never silently substitute
- Add a `ZenVoiceCoreChecks` case for the invalid combination

**Effort:** 3 h · **Risk:** low · **Expected gain:** very large for anyone
currently in this state — this is a total-failure condition, not a quality issue.

### 1b. Add `large-v3` and `large-v3-turbo` to the catalog

[Finding 4](01-diagnosis.md#f4). Both exist as GGML in the whisper.cpp
repository, so this is catalog entries plus checksums.

- Prefer `f16`/`q8_0` over aggressive quantization — low-bit quantization
  disproportionately harms non-English languages ([02 §3.3](02-research.md))
- Surface the size/latency trade-off in the Models screen
- `large-v3-turbo` is the better default for dictation given the latency profile

**Effort:** 4 h · **Risk:** low · **Expected gain:** moderate and reliable.

### 1c. Beam search + temperature fallback

[Finding 5](01-diagnosis.md#f5). Switch from `WHISPER_SAMPLING_GREEDY` and
configure the fallback thresholds.

- Beam size 5 is the reference default; measure 1/3/5 for latency versus WER
- Make it a setting if the latency cost is material on `large-v3`

**Effort:** 3 h + measurement · **Risk:** medium — **this is a latency
regression on a push-to-talk tool**, so it must be measured before defaulting on,
not assumed to be free.

### 1d. Hinglish priming via `initial_prompt`

[Finding 8](01-diagnosis.md#f8). Prepend a short Hinglish-register exemplar to
the existing context prompt when the Hinglish profile is active.

**Effort:** 2 h · **Risk:** low, but **expected gain is speculative** — prompt
conditioning is unreliable and an overlong prompt displaces audio context. Treat
as an experiment that Phase 0 can settle, and revert if it does not measure.

---

## Phase 2 — Fix the representation (the real fix)

This is where Hinglish either becomes good or stays broken. Two routes; **2a is
strongly preferred** and 2b exists because 2a can fail on integration.

### 2a. Hinglish-native acoustic model — *preferred*

Adopt Whisper-Hindi2Hinglish Prime (Apache 2.0), which emits Latin-script
Hinglish directly. If this lands, `LocalTransliterator` is **deleted from the
Hinglish path entirely**, and Findings [1](01-diagnosis.md#f1) and
[2](01-diagnosis.md#f2) disappear rather than being mitigated.

**Sequenced as a spike, because conversion is unproven ([02 §4](02-research.md#4-integration-huggingface--whispercpp)):**

| Step | Outcome |
|---|---|
| 1. Time-boxed GGML conversion spike (2 days) | Does a loadable GGML model exist? |
| 2. If yes: run Phase 0 benchmark against it | Does it beat the baseline on *this user's* audio? |
| 3. If yes: add as a catalog model, Hinglish profile skips transliteration | Ship |
| 4. If no: fall back to 2b | — |

**Must verify during the spike, not after:**
- Conversion produces a model whisper.cpp actually loads and runs
- Quality holds on **English-dominant** Hinglish, not just Hindi-dominant
- Behaviour on pure English is acceptable, or the profile is well-isolated
- Licensing and redistribution for a model ZenVoice would ship or download

**Effort:** 2 days spike + 2 days integration · **Risk:** **medium-high, entirely
on conversion** · **Expected gain:** the largest available by a wide margin.

### 2b. Better romanization — *fallback only*

If 2a fails, improve the Devanagari→Latin step. **This cannot recover English
loanwords** ([Finding 2](01-diagnosis.md#f2)) — that information is destroyed
before the romanizer runs. It only addresses schwa and diacritics.

- Replace ICU `.toLatin` with a Hindi-specific romanizer implementing schwa
  deletion
- Keep vowel length instead of `.stripDiacritics` flattening it (`aa` not `a`)
- Strip ICU's syllable apostrophes (`da'una` → `dauna`)
- Add a reverse-transliteration lexicon for the most common English loanwords
  (`कंप्यूटर`→`computer`, `मीटिंग`→`meeting`, …), which recovers the *frequent*
  cases but never the general one

**Effort:** 3–5 days · **Risk:** medium · **Expected gain:** partial. Fixes
"hala"→"haal"; leaves the loanword problem structurally unsolved beyond whatever
the lexicon covers. **This is a consolation prize, not a fix.**

---

## Phase 3 — LLM normalization pass {#phase-3}

Only worthwhile after Phase 2, and its value depends on which route landed:
substantial after 2b (cleaning up residual romanization), marginal after 2a.

[Finding 6](01-diagnosis.md#f6): the existing guard requires token-for-token
identity, so this **cannot** reuse the current refinement path.

**Design sketch:**

- A separate `HinglishNormalizer` path, not a relaxation of the existing guard —
  the strict guard is correct for its own job and must stay strict
- Its own safety property, since exact-token-match is unusable here. Candidates:
  bounded edit distance per word; require phonetic similarity between original
  and replacement; restrict edits to a known loanword lexicon; reject any change
  in word *count*
- Few-shot prompt built from ASR-vs-reference diffs ([02 §6](02-research.md#6-llm-post-correction))
- Runs only when the Hinglish profile is active

**Effort:** 4–6 days · **Risk:** **high** — a 1.5B model rewriting words is
exactly the failure mode the original guard was built to prevent. Needs the
Phase 0 harness to prove it does more good than harm, and should ship
off-by-default.

---

## Phase 4 — Data flywheel (long horizon)

Only justified if Hinglish becomes a core use case.

- Capture user corrections as training pairs, with explicit opt-in
- LoRA fine-tune on the collected set
- Grow the personal fixture set from real corrections

**Effort:** weeks · **Risk:** high, includes privacy design · **Gain:** compounding.

Note the tension with ZenVoice's local-only, privacy-first positioning: any
correction corpus must be local and opt-in, which limits how much data
accumulates.

---

## Sequencing

```
Phase 0  ─────────────────────────►  (blocks everything)
   │
   ├── 1a  enforce compatibility  ── ship immediately, independent
   ├── 1b  large-v3-turbo         ── ship immediately, independent
   ├── 1c  beam search            ── needs Phase 0 to justify latency cost
   └── 1d  prompt priming         ── needs Phase 0; revert if it doesn't measure
              │
              ▼
         Phase 2a spike ──► success ──► ship, delete transliteration
              │
              └────────► failure ──► Phase 2b romanizer
                                        │
                                        ▼
                                    Phase 3 LLM pass
                                        │
                                        ▼
                                    Phase 4 flywheel
```

## Effort summary

| Phase | Effort | Risk | Expected gain |
|---|---|---|---|
| 0 — Measurement | ~2 days | Low | None directly; unblocks all |
| 1a — Compatibility | 3 h | Low | Very large in the broken state |
| 1b — large-v3-turbo | 4 h | Low | Moderate, reliable |
| 1c — Beam search | 3 h + eval | Medium (latency) | Moderate |
| 1d — Prompt priming | 2 h | Low | Speculative |
| 2a — Hinglish model | ~4 days | Medium-High | **Largest** |
| 2b — Romanizer | 3–5 days | Medium | Partial |
| 3 — LLM pass | 4–6 days | High | Moderate |
| 4 — Flywheel | Weeks | High | Compounding |

## Decisions needed from you

1. **Is Hinglish a first-class use case** or occasional? Phases 2–4 are only
   justified if first-class.
2. **Latency budget.** Beam search and `large-v3` both cost time. What delay is
   acceptable between releasing the key and seeing text?
3. **Model download size.** `large-v3` is ~3 GB; turbo far less. Acceptable?
4. **Appetite for the 2a spike** — two days that may produce nothing if GGML
   conversion fails.
5. **Devanagari Hindi profile** — separate goal from Hinglish. Wanted? It changes
   whether IndicWhisper is worth pursuing.

## What I would do

Phase 0, then 1a and 1b together — that is roughly a day and a half and clears
the total-failure condition plus the model ceiling. Then re-measure before
touching anything else, because [Finding 3](01-diagnosis.md#f3) may be
responsible for so much of the current badness that the remaining problems look
quite different once it is fixed.
