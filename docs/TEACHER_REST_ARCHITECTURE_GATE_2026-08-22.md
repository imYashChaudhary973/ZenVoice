# Lecture v2 Teacher-vs-Rest Architecture Gate — 2026-08-22

## Decision

**FAIL. Do not start Lecture v2 Phase 2.**

The isolated Teacher-vs-Rest architecture is fast and memory-bounded, but it
fails every identity-quality gate and the required consented classroom corpus
does not exist. No model, dependency, role storage, or diarization UI enters
ZenVoice.

## Frozen gate

`Research/TeacherRestPrototype/GATE.json` was written before prototype tuning.
Promotion requires every hard condition:

| Metric | Required |
| --- | ---: |
| Teacher precision | ≥98% |
| Teacher recall | ≥95% |
| Main-speaker suggestion | ≥95% |
| Student-question attribution | ≥95% |
| Silence false positives | ≤2% |
| Unsafe Teacher/Others label during overlap | 0% |
| 30/60/90-minute speed | ≥10x real time |
| Peak memory | <1 GiB |
| Classroom evaluation corpus | Required |

Missing classroom data is FAIL, not SKIP.

## Corpus

### AMI engineering data

- Calibration: ES2008b/c/d
- Held out: ES2004a–d and IS1009a–d
- Stress: ES2004a distant Array1 microphone and ES2003b A/B same-gender pair
- Questions: AMI Elicit dialogue acts with word-derived timestamps
- Simulated Teacher: longest annotated speaker per meeting

AMI is suitable for engineering but is not classroom evidence.

### Consented classroom data

`CORPUS_STATUS.json` records the current state:

- 60 consented recordings
- one recorded speaker
- 15.14 minutes total
- longest recording 16.36 seconds
- zero qualifying multi-speaker classroom lectures

The existing corpus is short dictation and cannot satisfy Teacher/Others
promotion. `classroom-manifest.schema.json` defines the required future input.

Future promotion does not trust these summary counts alone. The retained Swift
evaluator loads the consented classroom JSONL manifest, rejects malformed or
unknown fields, requires non-empty regular audio/RTTM/question files, parses
RTTM and question annotations, derives student-question totals, verifies
consent and teacher/room split isolation, and requires separate 30–<60,
60–<90, and 90-minute evaluation buckets.

## Prototype architecture

The prototype is a separate Swift package under
`Research/TeacherRestPrototype`. The root ZenVoice package does not depend on
it.

```text
16 kHz mono audio
    ↓
Pyannote Community-1 CoreML segmentation
    ↓
WeSpeaker v2 256-dimensional embeddings
    ↓
Coarse anonymous clusters
    ↓
Frozen main-speaker suggestion
    ↓
Ground truth simulates user Teacher confirmation
    ↓
Robust per-lecture Teacher centroid
    ↓
Cosine rescore → Teacher / Others / Unknown
    ↓
Frame and question-role evaluation
```

Model conversion: `FluidInference/speaker-diarization-coreml`, revision
`1ed7a662fdc7109e36d822db793ee6eebdaf8594`, CC-BY-4.0. FluidAudio v0.12.4
was used only as an external CoreML extraction runner. The role classifier,
thresholding, overlap policy, and evaluator are pure Swift with no dependencies.

Source: <https://huggingface.co/FluidInference/speaker-diarization-coreml>

## Phase results

| Phase | Result |
| --- | --- |
| 1B.0 Gate | Declared frozen before prototype execution; chronology is session-attested, not cryptographically retained |
| 1B.1 Corpus | AMI ready; classroom prerequisite **failed** |
| 1B.2 Segmentation | Local CoreML turns produced on 13 scenarios |
| 1B.3 Embeddings | 256-dimensional per-turn embeddings produced locally |
| 1B.4 Main suggestion | 0/3 calibration; 6/10 held-out/stress |
| 1B.5 Teacher reference | Robust confirmed-cluster centroid implemented |
| 1B.6 Classifier | No threshold met calibration constraints |
| 1B.7 Questions | 80.68% held-out attribution; required 95% |
| 1B.8 Long form/privacy | Long-form performance, network isolation, and final cleanup passed; persisted-embedding encryption and product delete behavior were not implemented, so privacy gate **failed** |

## Calibration

The grid and tie-break procedure were frozen in `GATE.json`. No configuration
met the 98% precision, 2% silence, and zero-unsafe-overlap constraints. The
best fallback was evaluated only to produce a complete failure record.

| Metric | Calibration result |
| --- | ---: |
| Teacher precision | 56.40% |
| Teacher recall | 86.21% |
| Main suggestion | 0% |
| Question attribution | 55.10% |
| Silence false positives | 16.46% |
| Unsafe overlap assignments | 75.52% |

Fallback thresholds: Teacher ≥0.60, Others ≤0.55, Unknown between them.

## Held-out and stress evaluation

| Metric | Required | Actual | Result |
| --- | ---: | ---: | --- |
| Teacher precision | ≥98% | 82.51% | FAIL |
| Teacher recall | ≥95% | 90.11% | FAIL |
| Main suggestion | ≥95% | 60.00% | FAIL |
| Question attribution | ≥95% | 80.68% | FAIL |
| Silence false positives | ≤2% | 13.67% | FAIL |
| Unsafe overlap assignments | 0% | 89.13% | FAIL |
| Held-out inference speed | ≥10x | 134.17x | PASS |
| Held-out peak memory | <1 GiB | 634.9 MiB | PASS |
| Model size | prefer ≤100 MiB | 36.1 MiB | PASS |
| Classroom corpus | required | missing | FAIL |

The classifier's apparent low 3.14% Unknown rate is not a success: it forces
Teacher/Others labels during uncertain and overlapping speech instead of
failing closed.

### Per-file failure shape

- ES2004d: 75.8% precision, 80.3% recall, wrong main suggestion
- IS1009a: 71.9% precision, 0% question attribution
- ES2004a distant: 76.1% precision, 20% question attribution
- ES2003b same-gender pair: 92.7% precision, 24.3% silence false positives
- Reference overlap receives an unsafe role label on roughly 89% of held-out
  overlap frames

## Long-form and privacy gate

Models were cached first. Every measured run then executed under macOS
`sandbox-exec` with `network*` denied.

| Duration | Processing | Speed | Max RSS | Peak footprint |
| ---: | ---: | ---: | ---: | ---: |
| 30 min | 11.71 s | 153.7x | 473.8 MiB | 775.1 MiB |
| 60 min | 26.03 s | 138.3x | 661.3 MiB | 879.5 MiB |
| 90 min | 40.61 s | 133.0x | 895.3 MiB | 921.1 MiB |

- Runtime model files: 36.1 MiB
- Network-denied runs: PASS
- FluidAudio disk-backed temporary files after runs: none
- Research embedding JSON and model caches: deleted after normalization
- Cross-lecture comparisons and persistent voiceprints: none
- Research candidate JSON contained unencrypted embeddings while evaluation was
  active: persisted-embedding encryption gate **failed**
- Product deletion of turns / embeddings / caches was not implemented or tested:
  delete-behavior gate **failed**
- Product network/runtime changes: none

Long-form performance and final cleanup pass. The full privacy gate does not.
Neither result rescues identity accuracy.

## Why the custom architecture fails

1. The coarse clusterer does not produce a stable dominant cluster under the
   frozen dominance rule.
2. Confirmed-cluster embeddings are not sufficiently exclusive: other speakers
   frequently score as Teacher.
3. The underlying segmentation output rarely preserves overlap, so post-
   processing cannot safely recover it.
4. Silence and distant speech produce too many false role turns.
5. Question attribution inherits those role errors.
6. There is no consented classroom corpus to demonstrate generalization.

These are architecture/model failures, not UI defects. Building encrypted timed
turn storage would make incorrect labels durable, so Phase 2 remains blocked.

## Reproduction

```bash
# Gate and classifier self-checks
jq -e . Research/TeacherRestPrototype/GATE.json
swift run -c release --package-path Research/TeacherRestPrototype \
  teacher-rest-prototype self-check

# AMI references and question metadata
Scripts/benchmark-diarization.py reference \
  --meeting ES2004a --annotations Datasets/ami_public_1.6.2 \
  --output /tmp/ES2004a.rttm
Scripts/benchmark-diarization.py metadata \
  --meeting ES2004a --annotations Datasets/ami_public_1.6.2 \
  --output /tmp/ES2004a.json

# Calibrate and evaluate normalized CoreML output. Promotion requires actual
# consented classroom calibration and evaluation candidate outputs.
swift run -c release --package-path Research/TeacherRestPrototype \
  teacher-rest-prototype calibrate \
  GATE.json manifest.json CORPUS_STATUS.json thresholds.json
swift run -c release --package-path Research/TeacherRestPrototype \
  teacher-rest-prototype evaluate \
  GATE.json manifest.json thresholds.json CORPUS_STATUS.json \
  GATE_EVIDENCE.json result.json
```

Raw audio, model, and embedding outputs are intentionally excluded from the
repository. `RESULT.json` is the Phase 1B decision. `RESULT_1C.json` is the
Phase 1C retry.

## Phase 1C retry — 2026-08-23

**FAIL again. Phase 2 stays blocked.**

1C.1 collected no classroom lectures. The Mac still has only 103
single-speaker dictation clips (max 16.36 s). Ingest fail-closes. A classroom
fine-tuned model was not trained.

1C.2 ran Pyannote powerset logits directly, with FluidAudio exclusive
reconstruction off. Overlap recall on AMI is 39–65% (ES2004a 51%). LS-EEND
CoreML is released and ran; on ES2004a it has 40% overlap recall and 4.1%
silence false alarms. It is not better enough to replace powerset.

1C.3–1C.5 added a speech/SNR/overlap silence gate, kept several Teacher
prototypes, and scored each turn independently. Clustering is suggestion-only.

| Metric | Required | 1B | 1C | Result |
| --- | ---: | ---: | ---: | --- |
| Teacher precision | ≥98% | 82.5% | 89.9% | FAIL |
| Teacher recall | ≥95% | 90.1% | 62.0% | FAIL |
| Main suggestion | ≥95% | 60% | 70% | FAIL |
| Question attribution | ≥95% | 80.7% | 64.0% | FAIL |
| Silence false positives | ≤2% | 13.7% | 9.7% | FAIL |
| Unsafe overlap assignment | 0% | 89.1% | 25.2% | FAIL |
| Classroom corpus | required | missing | missing | FAIL |

Precision and overlap safety improved. Recall and question attribution fell
because more speech is now Unknown. No frozen threshold was lowered.

## Reconsideration

Do not start Phase 2. Reopen only when both are true:

1. A consented classroom corpus satisfies the frozen teacher/room-disjoint
   minimums. Use `CLASSROOM_COLLECTION.md` and `Scripts/ingest-classroom-corpus.py`.
2. A new segmentation/embedding architecture can keep overlap Unknown and meet
   the frozen precision/recall/silence/question gates without relaxing them.

Until then, Lecture v1 remains the shipped boundary.
