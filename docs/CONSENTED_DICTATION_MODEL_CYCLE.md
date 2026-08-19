# Consented Dictation Model Cycle

Status: public supplement experiment complete and rejected; product-specific frozen data still required  
Started: 2026-08-14

## Goal

Produce a smaller English Q5 model that improves representative ZenVoice
dictation without changing quantities, negations, or clean transcripts. Model
promotion is allowed only after every accuracy, safety, performance, provenance,
and redistribution gate passes.

## Completed

- Added a fail-closed semantic guard to `ZenVoiceCore`. If refinement changes
  the multiset of number words, digit-bearing tokens, or negations, ZenVoice
  returns the original ASR transcript with `wasRejected = true`.
- Protected both direct `InstantRefineEngine` use and the complete
  `TranscriptRefinement` pipeline.
- Added regression coverage for the observed `one one` quantity collapse and
  repeated-negation collapse. Existing `no wait` correction behavior remains
  supported, while ordinary `no wait` text remains protected.
- Replaced the old prompt/reference helper with a consented session workflow.
  It requires adult opt-in, pseudonymous IDs, local-only training/evaluation
  permission, verbatim human-reviewed transcripts, valid WAV files, and hashes.
- Expanded and checksum-locked the collection pack to 60 prompts: six prompts
  in each required category, mostly spontaneous. Prompt definitions cannot be
  edited to manufacture category coverage; spoken responses and verbatim
  transcripts remain participant-generated.
- Added explicit speaker-group split tooling. Generated train, validation, and
  test manifests are locked by SHA-256, and the output directory cannot be
  overwritten by the builder.
- Added a machine-enforced representativeness contract at dataset freeze time.
  The policy sets minimum clips, decoded WAV hours, speaker groups, and prompt
  category coverage for every split; the frozen summary records actual versus
  required values, and conservative training rejects missing or failed
  evidence.
- Added disposable pipeline checks proving successful consent validation,
  representativeness enforcement, speaker-disjoint splitting, lock
  verification, and tamper rejection.
- Added end-to-end 1-, 5-, and 10-second silence probes to the actual
  Whisper-plus-`TranscriptCleaner` runtime path.
- Added JSONL corpus support to `ZenVoiceAccuracyChecks`, so the exact locked
  test manifest can be evaluated without copying files into a mutable folder.
- Added conservative training mode, composite checkpoint selection, verified
  adapter merging, and selection-aware Q5 conversion. The public-supplement
  experiment can exercise these tools, but the promotable cycle cannot run
  until authorized recordings form a locked representative dataset.
- Added artifact-bound evidence collection. Baseline and checkpoint evidence
  records are tied to the exact frozen test, adapter, runtime model, native log,
  Hugging Face metrics, and license review by SHA-256. Selection rechecks those
  hashes and rejects post-evaluation changes.
- Added separate whole/segmented quantity and negation counts against the real
  dictation references. A candidate cannot introduce any new protected-token
  failure relative to the locked baseline.
- Downloaded and pinned OpenSLR SLR31 `train-clean-5` as the clean-English
  regularizer: 1,519 clips, 5.311 hours, 28 speakers, CC BY 4.0. Publisher and
  per-audio checksums, source URLs, and attribution are recorded under
  `Datasets/general-speech/librispeech-mini/prepared-v1`. It remains labelled
  read speech, not representative dictation.
- Added three-run native latency/memory and Q5-size gates. Selection rejects a
  hardware mismatch, over 20% throughput loss, over 25% latency regression,
  excessive memory growth, insufficient unload reclamation, or over 2% Q5
  growth relative to the frozen baseline.
- Added a final fail-closed promotion verifier requiring the all-gates decision,
  final Q5 inventory, human license/attribution and redistribution reviews,
  stable HTTPS artifact/model-card URLs, and matching bytes and SHA-256.
- Added a Mozilla Common Voice Spontaneous Speech 4.0 English intake tool. It
  requires a human terms/license review bound to the downloaded archive hash,
  rejects unsafe tar members, uses only validated and unflagged train/dev/test
  rows, converts audio to 16 kHz mono PCM, verifies Mozilla's speaker-disjoint
  splits, and checksum-locks the resulting manifests. It deliberately labels
  the corpus as a public spontaneous-speech supplement rather than claiming it
  is representative ZenVoice dictation.
- Prepared the reviewed English archive into 1,618 retained clips (4.557
  hours) from 278 disjoint speakers: 1,023 train, 333 validation, and 262 test.
  The exact archive, manifests, review, provenance, and summary are bound by
  SHA-256 under `Datasets/common-voice-spontaneous-4.0/prepared-v1`.
- Extended evidence collection and composite selection to understand public
  corpus locks. A machine-enforced `representative_zenvoice_dictation` gate
  prevents a public-only candidate from being selected for promotion even if
  its accuracy and runtime metrics improve.
- Completed the conservative public-supplement LoRA run and retained both epoch
  checkpoints. Checkpoint 636 improved frozen public-speech WER but regressed
  clean fixtures and introduced long-form insertions after Q5 conversion, so it
  was rejected. Checkpoint 318 also failed the clean and long-form gates.
- Converted the base and both candidates to English-labelled Q5_0 artifacts.
  Each file is 175,222,905 bytes. The runtime-facing `.en.` filename marker is
  mandatory so ZenVoice does not misclassify an English-only artifact as a
  multilingual model.

## Current authorization boundary

No participant has completed the consent form and no new representative audio
has been supplied. A gitignored nine-speaker cohort is pre-registered before
recording so speaker splits cannot be chosen after transcripts are observed:

`Datasets/consented-dictation/cohort-v1/cohort-v1-speaker-01/session-001`

Slots 01–05 are assigned to train, 06–07 to validation, and 08–09 to test in
`Datasets/consented-dictation/split-policy-v1.json`. Every session starts with
consent permissions set to false, participant-controlled timestamps and
recording metadata left as placeholders, zero recordings, and the same locked
60-prompt pack.

ZenVoice must not mark the form as accepted, fabricate transcripts, reuse
private History recordings without selection, or upload any session. The person
recorded must choose the contributed clips and personally accept the consent
statement.

The general-English regularizer is ready and independently verifiable:

```bash
Datasets/zenvoice-training/.venv/bin/python \
  Scripts/prepare-librispeech-general-speech.py verify \
  --dataset-dir Datasets/general-speech/librispeech-mini/prepared-v1
```

## Prepare Common Voice spontaneous English

Mozilla Common Voice Spontaneous Speech 4.0 English exceeds the initial numeric
floor for clips, decoded hours, and speakers. It improves domain proximity over
read speech, but it does not guarantee coverage of ZenVoice punctuation
commands, coding terms, numbers, negations, names, or corrections. Keep its
Mozilla validation/dev/test partitions held out from one another, and retain a
separate ZenVoice product-safety test set.

A person signed in to Mozilla Data Collective, accepted its current terms, and
downloaded the English 4.0 archive. ZenVoice did not automate account creation
or terms acceptance. The retained local archive is:

`Datasets/incoming/sps-corpus-4.0-2026-06-12-en.tar.gz`

Its SHA-256 is
`3b03ada7676a5f440a797d896035137fd073d0683133c3e9a83963480d88abfe`.
The review record is bound to those exact bytes:

```bash
python3 Scripts/prepare-common-voice-spontaneous.py init-review \
  --archive \
    Datasets/incoming/sps-corpus-4.0-2026-06-12-en.tar.gz \
  --output Datasets/common-voice-spontaneous-4.0/license-review.json
```

Review Mozilla's access terms and CC0 license, then truthfully fill
`dataset_access_terms_accepted`, `license_approved_for_local_training`,
`redistribution_review`, `reviewed_by`, and `reviewed_at`. Preparation fails
closed while placeholders or false approvals remain:

```bash
Datasets/zenvoice-training/.venv/bin/python \
  Scripts/prepare-common-voice-spontaneous.py prepare \
  --archive \
    Datasets/incoming/sps-corpus-4.0-2026-06-12-en.tar.gz \
  --license-review \
    Datasets/common-voice-spontaneous-4.0/license-review.json \
  --output-dir Datasets/common-voice-spontaneous-4.0/prepared-v1

Datasets/zenvoice-training/.venv/bin/python \
  Scripts/prepare-common-voice-spontaneous.py verify \
  --dataset-dir Datasets/common-voice-spontaneous-4.0/prepared-v1
```

Preparation requires at least 500 retained clips, 3 decoded hours, 300/100/100
train/validation/test clips, and at least 5/2/2 speaker IDs. These are minimum
coverage checks. They do not transform spontaneous answers into validated
ZenVoice task coverage.

## Collect the first session

1. Give one unused cohort slot to one consenting adult speaker. Do not reuse a
   speaker in another slot or split.
2. Open that slot's `consent.json` and `session.json`. The participant must
   personally review consent; complete timestamps and recording metadata
   truthfully. Keep the pre-registered pseudonymous IDs unchanged.
3. In ZenVoice, enable Audio History and make intentional test dictations from
   `prompts.jsonl`. Avoid real secrets and personal information.
4. Export only the selected test recordings with transcripts enabled.
5. Copy each contributed WAV into the session's `recordings/` directory and
   name it after its prompt ID, such as `email-update.wav`.
6. Add the matching `email-update.txt` containing the verbatim words actually
   spoken, including fillers, repetitions, and corrections.
7. Validate locally:

```bash
python3 Scripts/prepare-dictation-corpus.py validate \
  --session-dir \
    Datasets/consented-dictation/cohort-v1/cohort-v1-speaker-01/session-001 \
  --output-manifest \
    Datasets/consented-dictation/manifests/cohort-v1-speaker-01.jsonl
```

## Freeze the evaluation set

Collect separate authorized speaker groups before creating a production split.
Do not place one speaker in multiple splits. Then create and complete a policy:

```bash
python3 Scripts/build-consented-dictation-splits.py init-policy \
  --output Datasets/consented-dictation/split-policy-v1.json
```

The generated policy starts this cycle at 500 clips, 3.0 decoded hours, and 9
speaker groups (5 train, 2 validation, 2 test), with every prompt category
represented in every split. These are starting minimums, not a claim that
three hours alone is production quality. Do not lower them merely to make an
existing collection pass; document any change before recording. The builder
recalculates duration from each 16 kHz WAV and rejects edited duration metadata.

The 60-prompt pack permits nine complete speaker sessions to produce 540
distinct clips. Add another authorized session when total decoded audio remains
below three hours. Use the read-only status command at any time; it validates
the supplied manifests but never freezes data or changes consent:

```bash
python3 Scripts/build-consented-dictation-splits.py status \
  --session-manifest Datasets/consented-dictation/manifests/session-a.jsonl \
  --session-manifest Datasets/consented-dictation/manifests/session-b.jsonl \
  --policy Datasets/consented-dictation/split-policy-v1.json
```

It reports `ready_to_freeze`, assignment problems, and every remaining clip,
hour, speaker, and category deficit. With no manifests, omit the
`--session-manifest` arguments to inspect the starting targets.

Build the dataset by passing every validated session manifest:

```bash
python3 Scripts/build-consented-dictation-splits.py build \
  --session-manifest Datasets/consented-dictation/manifests/session-a.jsonl \
  --session-manifest Datasets/consented-dictation/manifests/session-b.jsonl \
  --session-manifest Datasets/consented-dictation/manifests/session-c.jsonl \
  --policy Datasets/consented-dictation/split-policy-v1.json \
  --output-dir Datasets/consented-dictation/frozen-v1
```

Verify the lock before every evaluation:

```bash
python3 Scripts/build-consented-dictation-splits.py verify \
  --dataset-dir Datasets/consented-dictation/frozen-v1
```

Validate the exact JSONL in the native harness without loading a model:

```bash
ZENVOICE_CORPUS_VALIDATE_ONLY=1 \
ZENVOICE_ACCURACY_CORPUS=Datasets/consented-dictation/frozen-v1/test.jsonl \
swift run ZenVoiceAccuracyChecks
```

## Public-supplement exploratory cycle

The frozen Common Voice test gives an honest public spontaneous-speech
comparison, not a ZenVoice product-acceptance result. The base Hugging Face
model scored 8.109% WER on its 262 clips. A two-epoch LoRA run mixed the 1,023
public training clips with 1,519 LibriSpeech regularizer clips:

```bash
Datasets/zenvoice-training/.venv/bin/python \
  Scripts/train-whisper-dictation.py \
  --model-dir \
    Datasets/whisper-dictation-experiment/base-model/whisper-small.en \
  --model-revision e8727524f962ee844a7319d92be39ac1bd25655a \
  --locked-dataset-dir \
    Datasets/common-voice-spontaneous-4.0/prepared-v1 \
  --general-train-manifest \
    Datasets/general-speech/librispeech-mini/prepared-v1/train.jsonl \
  --approved-general-license CC-BY-4.0 \
  --dictation-repeat 1 \
  --output-dir Datasets/whisper-small-en-v3/training
```

The run completed 636 optimizer steps on Apple Silicon MPS in 3,938.34 seconds.
Checkpoint 318 scored 6.589% Hugging Face WER and checkpoint 636 scored 6.400%,
relative improvements of 18.7% and 21.1% over the base. Validation loss chose
checkpoint 636, but the full native gates rejected it after Q5 conversion:

| Native Q5_0 | Public WER whole / segmented | Clean WER whole / segmented | Long-form insertions |
|---|---:|---:|---:|
| Base | 9.1% / 9.6% | 2.4% / 5.4% | 0 |
| Checkpoint 318 | 7.6% / 8.4% | 4.0% / 5.7% | 1 |
| Checkpoint 636 | 7.3% / 8.3% | 4.7% / 7.1% | 2 |

The candidate clears the public WER-improvement target but exceeds the maximum
one-point clean regression in both modes and introduces new long-form
insertions. Semantic quantity/negation guard violations and silence failures
remain zero, but segmented ASR negation failures rise from 7 for the base to 8
and 9 for checkpoints 318 and 636. All adapters and Q5 files from this cycle
remain local evaluation artifacts. The public-corpus representativeness gate
independently prevents selection or promotion. The per-checkpoint evidence
for that cycle stays in git history rather than in this directory.

## Retraining gate

Retraining starts only after:

- consent and provenance validation passes for every clip;
- train, validation, and test speaker groups are disjoint;
- the representativeness contract passes with actual-versus-required evidence;
- the frozen test lock verifies;
- the training mixture and licenses are recorded; and
- the frozen test transcripts have not been used for prompt design or tuning.

The next training run will use a lower learning rate than the first experiment,
mix representative dictation with licensed general English speech, retain every
candidate checkpoint, and select only among candidates with zero semantic
failures. Validation loss alone will not choose the released checkpoint.

The conservative command is intentionally shown only with placeholders until
the locked dataset exists:

```bash
Datasets/zenvoice-training/.venv/bin/python \
  Scripts/train-whisper-dictation.py \
  --model-dir \
    Datasets/whisper-dictation-experiment/base-model/whisper-small.en \
  --model-revision e8727524f962ee844a7319d92be39ac1bd25655a \
  --locked-dataset-dir Datasets/consented-dictation/frozen-v1 \
  --general-train-manifest \
    Datasets/general-speech/librispeech-mini/prepared-v1/train.jsonl \
  --general-train-manifest \
    Datasets/common-voice-spontaneous-4.0/prepared-v1/train.jsonl \
  --approved-general-license CC-BY-4.0 \
  --approved-general-license CC0-1.0 \
  --dictation-repeat 2 \
  --output-dir Datasets/whisper-small-en-v2/training
```

Locked mode defaults to two epochs and learning rate `5e-5`, retains all epoch
checkpoints, and writes no merged model. It rechecks all locked artifact hashes,
all audio hashes, source/license metadata, and overlap between general speech
and every locked dictation split. Run the same command with
`--validate-inputs-only` first to verify inputs without loading Whisper or
creating a training output.

Each retained checkpoint is first merged strictly for evaluation, then converted
to a temporary Q5 model. This does not authorize promotion:

```bash
Datasets/zenvoice-training/.venv/bin/python \
  Scripts/materialize-whisper-candidate.py \
  --checkpoint-dir Datasets/whisper-small-en-v2/training/checkpoints/checkpoint-1 \
  --training-result Datasets/whisper-small-en-v2/training/training-result.json \
  --base-model-dir \
    Datasets/whisper-dictation-experiment/base-model/whisper-small.en \
  --base-model-revision e8727524f962ee844a7319d92be39ac1bd25655a \
  --output-dir Datasets/whisper-small-en-v2/evaluation/checkpoint-1-merged

Datasets/zenvoice-training/.venv/bin/python \
  Scripts/convert-quantize-whisper.py \
  --model-dir Datasets/whisper-small-en-v2/evaluation/checkpoint-1-merged \
  --output-dir Datasets/whisper-small-en-v2/evaluation/checkpoint-1-ggml \
  --whisper-cpp-dir \
    Datasets/whisper-dictation-experiment/tooling/whisper.cpp \
  --openai-whisper-dir \
    Datasets/whisper-dictation-experiment/tooling/openai-whisper \
  --model-revision checkpoint-1 \
  --language-capability english
```

The generated inventory binds that Q5 model to the candidate adapter and marks
it evaluation-only. After each checkpoint has complete frozen-test and
native-runtime evidence,
collect an immutable baseline and one evidence record per checkpoint. The
license review JSON must use schema version 1 and explicitly record
`approved: true` and `attribution_recorded: true` only after human review.

```bash
python3 Scripts/collect-whisper-candidate-evidence.py \
  --evidence-kind baseline \
  --checkpoint-id whisper-small-en-base \
  --runtime-model <baseline-ggml-model> \
  --runtime-inventory <baseline-artifact-inventory.json> \
  --runtime-log <baseline-native-runtime.log> \
  --runtime-lifecycle-log <baseline-lifecycle-1.log> \
  --runtime-lifecycle-log <baseline-lifecycle-2.log> \
  --runtime-lifecycle-log <baseline-lifecycle-3.log> \
  --hf-metrics <baseline-hf-metrics.json> \
  --locked-dataset-dir Datasets/consented-dictation/frozen-v1 \
  --license-review <baseline-license-review.json> \
  --output Datasets/whisper-small-en-v2/baseline-evidence.json

python3 Scripts/collect-whisper-candidate-evidence.py \
  --evidence-kind candidate \
  --checkpoint-id checkpoint-1 \
  --checkpoint-dir Datasets/whisper-small-en-v2/training/checkpoints/checkpoint-1 \
  --runtime-model <checkpoint-1-ggml-model> \
  --runtime-inventory <checkpoint-1-artifact-inventory.json> \
  --runtime-log <checkpoint-1-native-runtime.log> \
  --runtime-lifecycle-log <checkpoint-1-lifecycle-1.log> \
  --runtime-lifecycle-log <checkpoint-1-lifecycle-2.log> \
  --runtime-lifecycle-log <checkpoint-1-lifecycle-3.log> \
  --hf-metrics <checkpoint-1-hf-metrics.json> \
  --locked-dataset-dir Datasets/consented-dictation/frozen-v1 \
  --license-review <candidate-license-review.json> \
  --output Datasets/whisper-small-en-v2/checkpoint-1-evidence.json
```

Then selection runs as follows:

```bash
python3 Scripts/select-whisper-checkpoint.py \
  --locked-dataset-dir Datasets/consented-dictation/frozen-v1 \
  --baseline-evidence <baseline-evidence.json> \
  --candidate-evidence <checkpoint-1-evidence.json> \
  --candidate-evidence <checkpoint-2-evidence.json> \
  --output Datasets/whisper-small-en-v2/selection.json
```

The selector filters candidates through every gate before comparing composite
scores. A lower-WER candidate with one semantic, silence, repetition, long-form
insertion, clean-regression, protected-token, latency, memory, Q5-size, license,
or attribution failure cannot win. The decision explicitly leaves
`promotion_authorized` false.

Only that decision can be merged and passed to selection-aware quantization:

```bash
Datasets/zenvoice-training/.venv/bin/python \
  Scripts/merge-selected-whisper-adapter.py \
  --selection-decision Datasets/whisper-small-en-v2/selection.json \
  --base-model-dir \
    Datasets/whisper-dictation-experiment/base-model/whisper-small.en \
  --base-model-revision e8727524f962ee844a7319d92be39ac1bd25655a \
  --output-dir Datasets/whisper-small-en-v2/merged

Datasets/zenvoice-training/.venv/bin/python \
  Scripts/convert-quantize-whisper.py \
  --model-dir Datasets/whisper-small-en-v2/merged \
  --output-dir Datasets/whisper-small-en-v2/ggml \
  --whisper-cpp-dir \
    Datasets/whisper-dictation-experiment/tooling/whisper.cpp \
  --openai-whisper-dir \
    Datasets/whisper-dictation-experiment/tooling/openai-whisper \
  --model-revision <selected-checkpoint-id> \
  --language-capability english \
  --require-selection-provenance
```

After the selected Q5 has an approved stable distribution source, run the final
verifier. It writes evidence but does not upload or edit the catalog:

```bash
python3 Scripts/verify-whisper-promotion.py \
  --selection-decision Datasets/whisper-small-en-v2/selection.json \
  --artifact-inventory Datasets/whisper-small-en-v2/ggml/artifact-inventory.json \
  --license-review <human-approved-license-review.json> \
  --distribution-review <human-approved-distribution-review.json> \
  --output Datasets/whisper-small-en-v2/promotion-approval.json
```

The distribution review must identify a stable HTTPS download URL and model
card, exact Q5 bytes and SHA-256, a reviewer, and an ISO-8601 review time.
The license review must contain `approved: true`,
`attribution_recorded: true`, nonempty `licenses` and `attribution_notice`
fields, plus the reviewer and review time. Boolean approval placeholders must
not be completed by automation.

## Local pipeline checks

```bash
python3 Scripts/check-consented-dictation-pipeline.py
Datasets/zenvoice-training/.venv/bin/python \
  Scripts/check-conservative-training-inputs.py
python3 Scripts/check-candidate-evidence-collection.py
python3 Scripts/check-composite-checkpoint-selection.py
python3 Scripts/check-whisper-promotion.py
```

The checks use disposable synthetic fixtures below `Datasets`, delete them on
exit, and never label them as real training speech.

## Promotion gates

- Representative dictation WER improves by at least 10% relative.
- Whole and segmented clean WER regress by no more than 1.0 absolute point.
- New quantity, negation, repetition, and silence failures are all zero.
- Q5 checksum, size, license, attribution, source revision, and performance are
  recorded.
- Three lifecycle runs on identical hardware pass throughput, warm-up, decode,
  loaded-memory, unloaded-memory, reclaimed-memory, and Q5-size budgets.
- A stable download source and redistribution review exist.

Failing any gate keeps the candidate local and out of `VerifiedModelCatalog`.
