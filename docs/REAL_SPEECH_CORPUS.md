# Real-Speech Evaluation Corpus

> **Status:** The corpus foundation is built and Whisper-family baselines are
> measured. Two gaps remain: **per-engine baselines for Apple Speech,
> Parakeet, Nemotron, and Cohere**, and the **consented representative
> dictation cohort** (pre-registered, zero sessions recorded). This document
> tells the coding agent exactly what exists, where, under which licence, and
> how to run a baseline — no discovery required.
>
> Related: [Consented Dictation Model Cycle](CONSENTED_DICTATION_MODEL_CYCLE.md),
> [Accuracy Harness](ACCURACY_HARNESS.md),
> [2026-08-17 QA record](DAILY_RELIABILITY_QA_2026-08-17.md).

## 1. What "real speech" means here

Synthetic `say`-rendered fixtures are deterministic and licence-free but are
not people: they do not hesitate, breathe, or sit in a room. The evaluation
program uses four tiers, in increasing order of product relevance:

| Tier | Corpus | Role |
|---|---|---|
| Public spontaneous | Common Voice Spontaneous 4.0 English | Frozen public WER comparison |
| Public read | Mini LibriSpeech `dev-clean-2` / `train-clean-5` | Clean-speech floor + regularizer |
| Public meetings | AMI Meeting Corpus (headset audio) | Long-form spontaneous experiment (cycle rejected) |
| Consented dictation | `consented-dictation/cohort-v1` (pre-registered) | **The only representative corpus** — not yet recorded |

No public corpus is treated as representative ZenVoice dictation. The machine
`representative_zenvoice_dictation` gate exists precisely so a public-data
candidate can never be promoted.

## 2. Corpora on disk (all under gitignored `Datasets/`)

Audio and manifests are **never committed**. Scripts and locks are.

| Corpus | Path | Licence | Splits (clips) | Locked by |
|---|---|---|---|---|
| Common Voice Spontaneous 4.0 EN | `Datasets/common-voice-spontaneous-4.0/prepared-v1` | CC0 1.0 (Mozilla terms reviewed) | 1023 / 333 / 262 | `PUBLIC_CORPUS_LOCK.json`, manifest SHA-256 |
| Mini LibriSpeech dev-clean-2 | rebuilt on demand by `Scripts/build-librispeech-corpus.py` | CC BY 4.0 | per-speaker `single/` + `dictation/` | archive SHA-256 in script |
| LibriSpeech train-clean-5 (mini) | `Datasets/general-speech/librispeech-mini/prepared-v1` | CC BY 4.0 | 1,519 clips / 5.31 h | per-audio + manifest SHA-256 |
| AMI (cycle artifacts) | `Datasets/whisper-dictation-experiment/…` | CC BY 4.0 | 1673 / 299 / 322 (ES2004–08 / ES2003 / ES2002) | manifest SHA-256 |
| Consented cohort | `Datasets/consented-dictation/cohort-v1` | participant consent (fail-closed) | 0 recorded / 9 slots pre-registered | consent + split-policy JSON |

### 2.1 Provenance discipline (do not bypass)

- Every public download has its **archive SHA-256 recorded** and a
  **human licence review bound to those exact bytes** before preparation
  (`prepare-common-voice-spontaneous.py init-review`). Placeholder or false
  approvals fail closed.
- Mozilla archives **cannot be re-hosted**; only the preparation scripts and
  locks live in git.
- The consented cohort is **pre-registered**: speaker slots, split policy
  (01–05 train / 06–07 validation / 08–09 test), and the 60-prompt pack are
  locked **before** any recording exists, so splits cannot be chosen after
  transcripts are observed. Validation rejects placeholder consent
  timestamps, missing recordings, and edited metadata.

## 3. Running an evaluation (current commands)

The harness is `ZenVoiceAccuracyChecks`. The relevant environment contract:

| Variable | Effect |
|---|---|
| `ZENVOICE_MODEL_PATH` | Point the run at a specific model file (bypasses app defaults) |
| `ZENVOICE_ACCURACY_CORPUS` | Flat audio+`.txt` directory **or** locked JSONL manifest |
| `ZENVOICE_CORPUS_VALIDATE_ONLY=1` | Validate corpus paths/audio without loading a model |
| `ZENVOICE_ACCURACY_REQUIRED=1` | Fail (exit 1) instead of skipping when no model resolves |
| `ZENVOICE_ACCURACY_REQUIRE_REAL=1` | Refuse synthetic-only runs |
| `ZENVOICE_ACCURACY_SMOKE=1` | Decode exactly one real clip (CI smoke path) |
| `ZENVOICE_ACCURACY_NOISE` / `_CLEAN` / `_VERBOSE` / `_MAX_SYNTHETIC_CLIPS` | Noise floor, clean mode, per-clip hypotheses, synthetic cap |

Standard frozen-test run:

```bash
ZENVOICE_ACCURACY_REQUIRED=1 \
ZENVOICE_MODEL_PATH="<model.bin>" \
ZENVOICE_ACCURACY_CORPUS=Datasets/common-voice-spontaneous-4.0/prepared-v1/test.jsonl \
swift run ZenVoiceAccuracyChecks
```

Output per run: whole vs segmented WER, per-clip table, silence-suppression
probes (1/5/10 s), semantic-safety violation counts (must be zero), decode
time vs audio seconds. Known harness behavior: after an intentional nonzero
exit, whisper.cpp v1.9.1 asserts during Metal teardown — all aggregates print
before it.

## 4. Baselines measured (2026-08-15 → 2026-08-17)

Frozen Common Voice Spontaneous test (262 clips, 3,084 s), native Q5/F16
decode through the real runtime:

| Model | Whole / Segmented WER | Notes |
|---|---|---|
| whisper-small.en base Q5_0 | 9.1 % / 9.6 % | Cycle baseline |
| Fine-tuned ckpt 636 Q5_0 | 7.3 % / 8.3 % | **Rejected** — clean-fixture regression + insertions (see cycle doc) |
| Whisper Turbo Q5_0 | 8.1 % / 9.6 % | Daily-driver model; 10× real time; 0 semantic violations |

AMI cycle (rejected candidate): tuned Q5_0 reached 10.1 % whole on its frozen
test vs 18.4 % base — evidence that fine-tuning works technically while the
gates correctly block promotion without representative data.

**Open finding (2026-08-17):** Turbo decodes 1/5/10 s of near-silence to
"Thank you." which survives cleanup. `TranscriptCleaner` deliberately keeps
"Thank you." (plausible dictation). This is a product decision, not a bug —
options are recorded in the QA record. Do not "fix" it by widening the
suppression list without an explicit decision.

## 5. Per-engine baselines (the open Phase 6 item)

**Current limitation:** `ZenVoiceAccuracyChecks` decodes through the
Whisper path. Apple Speech, Parakeet, Nemotron, and Cohere have runtime
coverage but no WER baseline on real speech. Plan for the coding agent:

1. Extend the harness with an engine-selection switch that mirrors
   `EngineRegistry` selection (for example
   `ZENVOICE_ACCURACY_ENGINE=parakeet|nemotron|cohere|appleSpeech`), reusing
   the existing corpus loader, scoring, and report — do not fork the harness.
2. Per engine, run the same frozen Common Voice test plus the LibriSpeech
   clean set; record the same table columns as §4 plus p50/p95 decode
   latency.
3. Apple Speech runs on-device only and may require authorization prompts —
   gate it behind a manual QA step, not unattended CI.
4. Record results in this file and refresh the recommendation table in the
   architecture reference.
5. Definition of done: one table row per installed engine, produced by a
   command a reviewer can re-run.

**Pinned unknowns:** whether Apple Speech permits reproducible batch decode
(some locales cache); Cohere CoreML warm-up cost on cold CI runners;
Nemotron streaming-mode accuracy vs non-streaming.

## 6. Baseline procedure rules

- A frozen test's transcripts are **never** used for prompt design or
  tuning; the lock makes tampering detectable.
- Candidates are compared against the **locked baseline of the same runtime
  family**; a new candidate cannot introduce silence, semantic, or protected-
  token failures even when average WER improves.
- Numbers reported in docs must name the exact corpus version, split, model
  file, and date. Numbers without provenance do not count as baselines.

## 7. Consent path to representative data

Until the cohort exists, every model improvement is exploratory. The first
three recorded sessions double as the **measure-before-training checkpoint**:
if base-model WER on real user dictation is already comfortable, the
fine-tuning program should stop rather than proceed to nine speakers. The
runbook for session 001 is
`Datasets/consented-dictation/cohort-v1/SESSION_001_RUNBOOK.md` (local,
gitignored) and the full cycle contract is
[CONSENTED_DICTATION_MODEL_CYCLE.md](CONSENTED_DICTATION_MODEL_CYCLE.md).
