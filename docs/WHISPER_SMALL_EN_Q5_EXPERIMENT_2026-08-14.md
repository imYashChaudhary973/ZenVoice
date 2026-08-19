# Whisper Small English Fine-Tune and Q5 Experiment

Date: 2026-08-14

## Decision

The experiment is complete. Fine-tuning materially improved held-out AMI speech,
and Q5_0 preserved nearly all of that gain, but the tuned artifact is **not
approved for catalog integration**. It regressed the segmented clean-fixture
score and introduced an additional quantity-preservation failure. AMI is also
not representative target-user dictation, and no reviewed redistribution source
exists. `VerifiedModelCatalog` therefore remains unchanged.

## Objective

Measure whether a locally fine-tuned `openai/whisper-small.en` model can improve
ZenVoice English dictation accuracy, then quantify the size, memory, speed, and
accuracy effects of converting it to whisper.cpp GGML Q5_0.

## Data and split policy

The experiment uses individual-headset speech from the AMI Meeting Corpus under
CC BY 4.0. AMI is real spontaneous English speech, but it is meeting speech—not
target-user dictation. A production decision still requires consented,
representative ZenVoice dictation.

| Split | AMI series | Clips | Hours | Use |
|---|---:|---:|---:|---|
| Train | ES2004–ES2008 | 1,673 | 3.165 | LoRA updates |
| Validation | ES2003 | 299 | 0.609 | Best-checkpoint selection |
| Test | ES2002 | 322 | 0.593 | Frozen final comparison |

`Scripts/prepare-whisper-dictation-data.py` validates 16 kHz mono PCM audio,
paired transcripts, duration bounds, repository-local paths, meeting-series
separation, and cross-split audio hashes. The frozen manifest hashes are:

- Train: `274365e912687a9a884a52dca33ee2f6d12064d5899fe830093bba545a4b845d`
- Validation: `f43a86217015dd0e22c208bc73f359a81edbb01dc47ef2cfca61999715212b71`
- Test: `029651d488dc188fa89eb57f6e5b45f71bfae6625204dfbb1b85b5bc995942c3`

## Model and tooling provenance

| Component | Revision or hash | License |
|---|---|---|
| `openai/whisper-small.en` | `e8727524f962ee844a7319d92be39ac1bd25655a` | Apache-2.0 |
| Base `model.safetensors` | `6014ac49b506df900f66f4aca6b0801eed7245594ace97bcaf73e0ae5b863066` | Apache-2.0 |
| whisper.cpp | `f049fff95a089aa9969deb009cdd4892b3e74916` (v1.9.1) | MIT |
| OpenAI Whisper conversion assets | `5f86d1d86363843179951550570367b37c5d6f78` | MIT |

Fine-tuning uses LoRA on attention `q_proj` and `v_proj`: rank 16, alpha 32,
dropout 0.05, learning rate 1e-4, effective batch 8, three epochs, seed 42.
Only 1,769,472 of 243,503,616 parameters (0.73%) are trainable. The merged model
is saved locally; no model, audio, transcript, or checkpoint is uploaded.

Training took 2,856.55 seconds on Apple Silicon MPS. Validation loss improved
from 0.37758 after epoch 1 to 0.35609 after epoch 2, then rose slightly to
0.35844 after epoch 3. The trainer restored epoch 2 (`checkpoint-420`) before
merging. The merged `model.safetensors` SHA-256 is
`b8f791c566f210dc3e515da294c10dd144858f96ba216f954dead03907602bdd`.

## Baseline measurements

| Runtime/model | Frozen real-speech WER | Clean fixture WER (whole / segmented) | Throughput | Process RSS snapshot |
|---|---:|---:|---:|---:|
| Transformers FP32 | 15.759% | Not run | 17.1× real time | Not measured |
| ZenVoice GGML F16 | 20.1% | 1.7% / 3.7% | 27× real time | ~731 MB |
| ZenVoice GGML Q5_0 | 18.4% | 2.4% / 5.4% | 24× real time | ~556 MB |

The Q5_0 file is 175,222,905 bytes versus 487,614,201 bytes for GGML F16, a
64.1% disk reduction. Q5_0 improved this difficult real-speech result by 1.7
points relative to F16 but regressed clean fixtures by 0.7 point. Quantization
therefore is not accurately described as producing universally identical
predictions.

The baseline Q5_0 SHA-256 is
`965e7706e3b14da6f7d3f78ef1e2223ea1e3bdabd207013bce8541e98baca1f5`.

## Acceptance gates

- Tuned Transformers WER must improve by at least 10% relative: at most 14.18%.
- Tuned Q5_0 ZenVoice WER must improve by at least 10% relative: at most 16.56%.
- Clean-fixture WER may regress by at most 1.0 absolute point from the matching
  base runtime.
- Q5_0 must not introduce new silence hallucinations, repetition failures,
  negation changes, or quantity changes.
- The artifact must retain exact model, corpus, tool, size, SHA-256, license,
  and attribution records.
- Catalog integration additionally requires a reviewed redistribution decision
  and a stable verified download source. This experiment does not authorize an
  upload or release.

## Tuned results

| Runtime/model | Frozen real-speech WER | Clean fixture WER (whole / segmented) | Throughput | Process RSS snapshot |
|---|---:|---:|---:|---:|
| Transformers FP32 | 9.816% | Not run | 16.8× real time | Not measured |
| ZenVoice GGML F16 | 9.9% / 10.3% segmented | 1.7% / 6.1% | 25× real time | ~707 MB |
| ZenVoice GGML Q5_0 | 10.1% / 10.8% segmented | 3.0% / 7.7% | 15× real time | ~489 MB |

The Transformers result is a 37.7% relative WER reduction from its baseline.
The tuned Q5_0 result is a 45.1% relative reduction from the ZenVoice Q5_0
baseline and is only 0.2 absolute point worse than tuned F16. Q5_0 therefore
preserved the main accuracy gain while reducing the file from 487,614,201 bytes
to 175,222,905 bytes (64.1%) and reducing the observed process RSS snapshot by
about 218 MB. These are benchmark snapshots, not guarantees of macOS idle RAM.

The dedicated ZenVoice runtime lifecycle check measured 475 MB loaded and
120 MB after unload, reclaiming 354 MB, with a 0.32-second warm-up and
0.17-second first and second sample decodes. This verifies that unload/reload
reclaims most model memory. It does not verify a 35–50 MB total idle process or
zero-delay cold start on this build.

The tuned artifacts are local and gitignored:

- GGML F16 SHA-256: `f1a818d882634be9f5d8ea454bae5c96d339b904fe01e8573d5e5ef5a6ef58e1`
- GGML Q5_0 SHA-256: `87b730407f9f7ed35a52142414a039180f5e43dbfc783b89ba0123e4502a6f72`
- Inventory: `Datasets/whisper-dictation-experiment/tuned-ggml/artifact-inventory.json`

## Gate results

| Gate | Result | Evidence |
|---|---|---|
| Transformers WER at most 14.18% | Pass | 9.816% |
| ZenVoice Q5_0 WER at most 16.56% | Pass | 10.1% |
| Clean fixtures regress at most 1.0 point | Fail | Whole +0.6 points; segmented +2.3 points |
| No new silence hallucination | Pass with known limitation | Base and tuned Transformers both emit `you` for 1/5/10 s silence; ZenVoice already filters it |
| No new repetition failure | Pass | Q5_0 long-form fixtures had 0 insertions and 0% repetition |
| No new negation or quantity change | Fail | New `ES2002a.D.0075` quantity failure, in addition to the existing `ES2002c.D.0119` failure |
| Provenance and artifact inventory | Pass | Pinned revisions, licenses, sizes, and SHA-256 values recorded |
| Representative consented dictation | Fail | AMI is licensed spontaneous meeting speech, not ZenVoice user dictation |
| Reviewed redistribution source | Fail | No upload or release was authorized |

Project verification also passed `swift build`, 10 core check groups plus the
extended core checks, 22 storage checks, deterministic scoring, and the live Q5
runtime lifecycle check. The first sandboxed storage attempt could not create
its temporary export; the same check passed with normal filesystem permissions.

Because safety gates are conjunctive, the large average-WER improvement is not
sufficient for release. The recommended next experiment is to add consented,
representative dictation and quantity/negation-focused training examples, then
repeat the same frozen evaluation without tuning on ES2002.

## Reproduction

The local pipeline is split into four auditable commands:

1. `Scripts/prepare-whisper-dictation-data.py` creates and validates disjoint
   manifests.
2. `Scripts/train-whisper-dictation.py` performs LoRA training, restores the
   best validation checkpoint, and merges it into a standard Whisper model.
3. `Scripts/evaluate-whisper-dictation.py` evaluates the frozen manifest and
   records WER, latency, edit counts, predictions, and silence probes.
4. `Scripts/convert-quantize-whisper.py` converts the merged model with pinned
   tooling, quantizes it to Q5_0, and records an artifact inventory.

Use the project virtual environment for all Python commands. The scripts reject
overlapping split hashes, unexpected model revisions, missing conversion tools,
and incomplete artifacts rather than silently continuing.

## Known harness behavior

The base ZenVoice runs completed ASR measurement, then the broader accuracy
harness failed because transcript refinement changed one protected quantity in
`ES2002c.D.0119` (`one` count 2→1). The tuned model adds a second failure in
`ES2002a.D.0075` (`one` count 3→2). These are refinement-stage failures, but
they remain release blockers for the end-to-end dictation pipeline.

whisper.cpp v1.9.1 also asserts while tearing down Metal after the harness's
intentional nonzero exit. All accuracy and timing aggregates are printed before
that teardown assertion.

## Follow-up: refinement guard

The second model cycle added a fail-closed core guard after this experiment.
It returns the original ASR transcript whenever refinement changes the multiset
of quantities, digit-bearing tokens, or negations. Re-running the tuned Q5_0
model on the same 322-clip corpus produced zero Clean and Agent Prompt semantic
violations while preserving 10.1% whole / 10.8% segmented real-speech WER.

This resolves the end-to-end refinement-safety defect, but it does not approve
the tuned model: segmented clean-fixture WER remains 7.7% versus the 5.4% base
result, representative consented dictation is still absent, and distribution
review remains incomplete.
