# Whisper Small English Public-Supplement Cycle

Date: 2026-08-15  
Decision: reject both fine-tuned checkpoints; do not promote or publish

## Outcome

Conservative LoRA fine-tuning improved the frozen public spontaneous-speech
test, but neither Q5_0 checkpoint passed ZenVoice's conjunctive safety gates.
Checkpoint 636 is the stronger public-speech candidate and improves native
whole-recording WER from 9.1% to 7.3% (19.8% relative), but clean-fixture WER
regresses by more than one absolute point and two new long-form insertions
appear. The corpus is also not representative ZenVoice dictation. The model
catalog and shipped model remain unchanged.

## Frozen data

Mozilla Common Voice Spontaneous Speech 4.0 English was downloaded only after a
person accepted the Mozilla Data Collective access terms. The controlled local
archive has SHA-256
`3b03ada7676a5f440a797d896035137fd073d0683133c3e9a83963480d88abfe`.
Its reviewed intake produced disjoint, checksum-locked splits:

| Split | Clips | Hours | Speakers | Manifest SHA-256 |
|---|---:|---:|---:|---|
| Train | 1,023 | 2.699 | 200 | `618901ff8fb9a84caadca5b5b65d220429c5df74d5f0c7fa40464e3202dd9040` |
| Validation | 333 | 1.001 | 25 | `7800d05e5cb258b7f0abeb2fd401ba8f45b484e2902ec7dcf724d85fb120b036` |
| Test | 262 | 0.857 | 53 | `317492494a4c50ba93a6e68579a81b1bd15be73b96123d75a1136530325df62a` |

The 1,023 public train clips were mixed once with 1,519 Mini LibriSpeech
train-clean-5 clips (5.311 hours, 28 speakers) as a general-English
regularizer. Test audio and transcripts were never included in training.

This dataset covers spontaneous English from many speakers. It does not prove
ZenVoice coverage of punctuation commands, coding terms, corrections, names,
numbers, negations, microphones, or target Indian-accent dictation. The frozen
lock therefore records `representative_zenvoice_dictation: false`.

## Training provenance

| Item | Value |
|---|---|
| Base model | `openai/whisper-small.en` |
| Base revision | `e8727524f962ee844a7319d92be39ac1bd25655a` |
| Base weights SHA-256 | `6014ac49b506df900f66f4aca6b0801eed7245594ace97bcaf73e0ae5b863066` |
| Method | LoRA on attention `q_proj` and `v_proj` |
| LoRA | rank 16, alpha 32, dropout 0.05 |
| Schedule | 2 epochs, learning rate 5e-5, seed 42 |
| Effective batch | 8 (batch 1, gradient accumulation 8) |
| Device | Apple Silicon MPS |
| Mixed samples | 2,542 |
| Optimizer steps | 636 |
| Runtime | 3,938.34 seconds |
| Train loss | 0.412244 |

Every epoch checkpoint was retained. Validation loss was 0.296152 at
checkpoint 318 and 0.289691 at checkpoint 636. Validation loss identified a
candidate for evaluation; it did not authorize model selection.

## Frozen-test results before quantization

| Model | WER | Relative change from base | Insertions / deletions / substitutions |
|---|---:|---:|---:|
| Base FP32 | 8.109% | baseline | 81 / 138 / 208 |
| Checkpoint 318 FP32 | 6.589% | 18.7% better | 75 / 76 / 196 |
| Checkpoint 636 FP32 | 6.400% | 21.1% better | 76 / 72 / 189 |

Both checkpoints pass the exploratory 10% public-WER target. This is necessary
but insufficient for promotion.

## English Q5_0 artifacts

The base and both candidates were converted with whisper.cpp revision
`f049fff95a089aa9969deb009cdd4892b3e74916` and OpenAI Whisper conversion
revision `5f86d1d86363843179951550570367b37c5d6f78`. Every runtime artifact is
175,222,905 bytes and uses the exact `ggml-model.en.q5_0.bin` filename so
ZenVoice identifies it as English-only.

| Artifact | SHA-256 |
|---|---|
| Base Q5_0 | `965e7706e3b14da6f7d3f78ef1e2223ea1e3bdabd207013bce8541e98baca1f5` |
| Checkpoint 318 Q5_0 | `9eb9406aee7070902a62964fb29acb4d7743ede6333af3e865395ca844fae0b3` |
| Checkpoint 636 Q5_0 | `6f6216aba80b6c6ad1b2a048ebf6abfc912bfa64aa388cd26026d24d7cbeddf6` |

All are local, evaluation-only artifacts.

## Native ZenVoice gates

| Q5_0 model | Public WER whole / segmented | Clean WER whole / segmented | Silence failures | Semantic guard violations | Long-form insertions |
|---|---:|---:|---:|---:|---:|
| Base | 9.1% / 9.6% | 2.4% / 5.4% | 0 | 0 | 0 |
| Checkpoint 318 | 7.6% / 8.4% | 4.0% / 5.7% | 0 | 0 | 1 |
| Checkpoint 636 | 7.3% / 8.3% | 4.7% / 7.1% | 0 | 0 | 2 |

Checkpoint 318 decodes the 3,084-second public test in 87.90 seconds (35x real
time), checkpoint 636 in 96.02 seconds (32x), and the base in 79.85 seconds
(39x). Performance lifecycle gates were not run because accuracy and
representativeness already fail; later gates cannot overturn an earlier
conjunctive failure.

The refinement guard reports zero quantity/negation semantic violations, and
1-, 5-, and 10-second silence remains suppressed. However, checkpoint 636
regresses clean whole WER by 2.3 points and segmented clean WER by 1.7 points.
Checkpoint 318 regresses clean whole WER by 1.6 points. Both exceed the maximum
one-point clean regression and both introduce a long-form insertion. The
segmented public test also adds negation-recognition failures: 8 for checkpoint
318 and 9 for checkpoint 636, versus 7 for the base.

## Gate decision

| Gate | Result | Reason |
|---|---|---|
| Public frozen-test WER improves at least 10% | Pass | Both retained checkpoints improve |
| Clean whole and segmented WER stay within 1 point | Fail | Checkpoint 636: +2.3 / +1.7; checkpoint 318 whole: +1.6 |
| No new quantity or negation safety failures | Fail | Guard violations are zero, but segmented ASR negation failures rise from 7 to 8/9 |
| No new repetition or long-form insertion failures | Fail | Both candidates introduce insertions |
| Silence suppressed | Pass | 1, 5, and 10 seconds suppressed |
| Representative ZenVoice dictation | Fail | Public supplement is not product dictation |
| License, attribution, redistribution, stable source | Fail | Training source redistribution review is pending; Mozilla data cannot be re-hosted |
| Lifecycle performance gates | Not reached | Earlier mandatory gates failed |

The correct decision is **no selection and no promotion**. No model was merged
as a selected release, no catalog entry was changed, and nothing was uploaded.

## Remaining production blocker

Collect the pre-registered, consented ZenVoice cohort: at least 500 validated
clips, three decoded hours, and nine speaker groups split 5 train / 2 validation
/ 2 test. Freeze it permanently, retrain without touching its test transcripts,
and rerun the same base-versus-candidate Q5 gates. Human license, attribution,
and redistribution review must also approve the final artifact before any
catalog or download-source work.
