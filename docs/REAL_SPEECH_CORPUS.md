# Real-Speech Evaluation Corpus

> **Status:** The corpus foundation is built, Whisper-family baselines are
> measured, and **per-engine baselines for Parakeet, Nemotron, and Cohere
> landed 2026-08-18** (§5) — one re-runnable command per engine. Remaining
> gaps: **Apple Speech** (manual-QA authorization gate) and the **consented
> representative dictation cohort** (pre-registered, zero sessions
> recorded). This document tells the coding agent exactly what exists,
> where, under which licence, and how to run a baseline — no discovery
> required.
>
> Related: [Consented Dictation Model Cycle](CONSENTED_DICTATION_MODEL_CYCLE.md),
> [Accuracy Harness](ACCURACY_HARNESS.md).

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

## 5. Per-engine baselines (measured 2026-08-18)

**Done, except Apple Speech** (manual-QA gate below). The harness grew
`ZENVOICE_ACCURACY_ENGINE`, which baselines one engine through its own
`SpeechEngine` path — resolved via `EngineRegistry`, decoded via
`transcribe(audioURL:)`, the same entry the app uses. One re-runnable
command per engine:

```bash
ZENVOICE_MODEL_PATH="<whisper model for registry construction>" \
ZENVOICE_ACCURACY_ENGINE=parakeet-flash \
ZENVOICE_ACCURACY_CORPUS=Datasets/common-voice-spontaneous-4.0/prepared-v1/test.jsonl \
swift run ZenVoiceAccuracyChecks
```

- `ZENVOICE_ACCURACY_ENGINE=list` prints the exact ids this machine has;
  an unknown id fails closed with the same list.
- Output columns match §4 (whole and segmented WER, protected-token
  failures) plus p50/p95 decode latency and the real-time multiple.
- `ZENVOICE_ACCURACY_NOSEGMENT=1` skips the segmented pass for slow
  engines. On this corpus every clip is a single utterance
  (`LiveSegmentation` yields one segment), so the segmented column
  re-measures the whole decode rather than a chunking penalty.
- Apple Speech still requires an authorized process (manual QA), per the
  rule below.

Frozen Common Voice Spontaneous test (262 clips, 3,084 s), 2026-08-18,
MacBook Pro M5, every installed engine through its own
`SpeechEngine.transcribe(audioURL:)` path:

| Engine | Whole / Segmented WER | Protected q / n | p50 / p95 decode | Real time |
|---|---|---|---|---|
| Parakeet TDT v3 Q8 | **6.9 % / 8.3 %** | 7 / 5 | 0.13 s / 0.37 s | **73×** |
| Parakeet TDT v2 Q8 | 7.3 % / 9.3 % | 2 / 5 | 0.12 s / 0.37 s | 73× |
| Whisper Turbo Q5 | 8.2 % / 9.8 % | 10 / 5 | 1.00 s / 2.19 s | 11× |
| Cohere Transcribe INT8 | 10.8 % / 12.5 % | 8 / 9 | 1.93 s / 5.75 s | 5× |
| Nemotron 3.5 Multilingual Q8 | 13.8 % / 14.0 % | 4 / 8 | 0.20 s / 0.60 s | 45× |
| Parakeet Flash Q8 | 14.1 % / 14.6 % | 11 / 8 | 0.58 s / 1.67 s | 16× |
| Nemotron Speech 3.5 Ultra Fast Q8 | 23.8 % / 29.1 % | 4 / 8 | 0.83 s / 2.37 s | 12× |
| Apple Speech | not measured | — | — | manual-QA gate |

Cross-check: the Whisper row through the engine path (8.2 % / 9.8 %) matches
the §4 `WhisperTranscriber` numbers (8.1 % / 9.6 %) within rounding — the
two paths measure the same decoder.

**Recommendation-relevant reading:** on this corpus Parakeet TDT v3 is both
the most accurate engine installed *and* ~7× faster than Whisper Turbo,
with fewer protected-token failures (7 vs 10 quantities). It is
English-only; multilingual users still need Whisper. Nemotron Ultra Fast —
marketed for streaming latency — is the least accurate non-streaming
decoder here, consistent with its streaming-first design. No engine except
Whisper-family has a Hinglish story.

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
