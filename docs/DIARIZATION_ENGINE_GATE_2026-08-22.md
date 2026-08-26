# Lecture v2 Diarization Engine Gate — 2026-08-22

## Decision

**STOP. Do not integrate a diarization engine.**

FluidAudio Offline VBx is fast enough and its longest output cluster maps to the
annotated dominant speaker in most AMI meetings, but it does not meet this
report's conservative reliability gate: held-out dominant-cluster accuracy is
87.5%, speaker count is wrong on all eight held-out meetings, overlap is
effectively discarded, and the same-gender two-voice stress case fragments two
people into five speakers.

The ONNX candidate fails even earlier. Sortformer preserves four speaker slots
but misses too much speech. Adding any of these runtimes would ship incorrect
role labels.

No product dependency, model, Python runtime, PyTorch runtime, NeMo runtime, or
Cloud path was added.

## Gate

ADR 0015 prohibits automatic identity claims and requires a benchmark to earn
implementation. It does not set numerical thresholds. This report adopts the
following conservative, **post-hoc** operational definition of **reliably
isolate the dominant speaker**:

- at least 95% dominant-cluster mapping accuracy on held-out AMI meetings,
- no dominant-cluster miss on a required stress scenario,
- absolute speaker-count error no greater than 1 per scenario,
- meaningful overlap detection (at least 50% recall on annotated overlap),
- a 60-minute local file processed at 10x real time or faster with peak memory
  below 1 GiB.

The accuracy conditions are conjunctive. Fast inference does not compensate for
wrong people. No per-lecture dominance threshold was calibrated because every
candidate stopped at this engine gate.

## Reproducibility

### Host

- MacBook Pro, Apple M5, arm64
- macOS / Darwin 27.0.0
- Metrics: 10 ms frames, 0.25 s collar, overlap ignored for DER and measured
  separately
- Memory: `/usr/bin/time -l`; no swap occurred. Fluid and Sortformer memory
  figures below were manually observed; their raw `time -l` logs were not
  retained. Accuracy failures independently determine STOP.

### Corpus

AMI Meeting Corpus manual annotations and real 16 kHz mono recordings, CC BY
4.0. The repository already held individual-headset training and validation
audio plus AMI 1.6.2 annotations.

- Tuning only: ES2008b/c/d mixed headset channels
- Held out: ES2004a–d and IS1009a–d
- Distant-room test: ES2004a `Array1-01`
- Similar-voice proxy: ES2008c speakers A/B, both female; this is a same-gender
  stress proxy, not proof that their voices are acoustically identical
- 60-minute test: ES2004b + 30 s silence + IS1009b, eight reference speakers

`Scripts/benchmark-diarization.py` is dependency-free developer tooling. It
builds AMI RTTM references, scores candidate JSON/text output, measures
speaker-count and dominant-speaker accuracy, mixes synchronized channels, and
constructs the 60-minute test. It is not an app runtime.

The commands below are representative rerun instructions. Candidate output,
score JSON, RTTM, and `/usr/bin/time` files were temporary `/tmp` artifacts and
are not retained or hash-bound in the repository. The tables preserve normalized
measurements, not an immutable raw benchmark archive.

```bash
./Scripts/benchmark-diarization.py self-check
./Scripts/benchmark-diarization.py reference \
  --meeting ES2004a \
  --annotations Datasets/ami_public_1.6.2 \
  --output /tmp/ES2004a.rttm

# FluidAudio v0.12.4, fixed threshold selected on ES2008b/c/d.
fluidaudiocli process ES2004a.Mix-Headset.wav \
  --mode offline --threshold 0.8 --output /tmp/fluid.json
./Scripts/benchmark-diarization.py score \
  --reference /tmp/ES2004a.rttm --hypothesis /tmp/fluid.json \
  --format fluid --audio ES2004a.Mix-Headset.wav

# Sixty-minute stress input and measured run.
./Scripts/benchmark-diarization.py concat \
  --audio ES2004b.Mix-Headset.wav --rttm /tmp/ES2004b.rttm \
  --audio IS1009b.Mix-Headset.wav --rttm /tmp/IS1009b.rttm \
  --output-audio /tmp/ami-60min.wav \
  --output-rttm /tmp/ami-60min.rttm --duration 3600 --silence 30
/usr/bin/time -l fluidaudiocli process /tmp/ami-60min.wav \
  --mode offline --threshold 0.8 --output /tmp/fluid-60.json
```

Candidate revisions and downloaded model hashes:

- FluidAudio: `v0.12.4`,
  `9830ce835881c0d0d40f90aabfaae3a6da5bebfb`
- Fluid diarization model repository:
  `1ed7a662fdc7109e36d822db793ee6eebdaf8594`
- sherpa-onnx: `v1.13.6`; macOS archive SHA-256
  `a188765a80094f8505b7ba02b6b906b6bb0dd42d0281822e6c11cdeba4120b24`
- sherpa Pyannote INT8 SHA-256
  `d582f4b4c6b48205de7e0643c57df0df5615a3c176189be3fc461e9d18827b5d`
- sherpa TitaNet SHA-256
  `ad4a1802485d8b34c722d2a9d04249662f2ece5d28a7a039063ca22f515a789e`
- Sortformer model repository:
  `ae9a27ab45dc0aa3abede7d2d6bad2b7a69aa6d1`

```bash
# sherpa-onnx v1.13.6, automatic speaker count.
/usr/bin/time -l sherpa-onnx-offline-speaker-diarization \
  --clustering.cluster-threshold=0.9 \
  --segmentation.pyannote-model=model.int8.onnx \
  --embedding.model=nemo_en_titanet_small.onnx \
  ES2004a.Mix-Headset.wav > /tmp/sherpa-0.9.txt 2>&1 \
  && printf 'SHERPA_EXIT_OK\n' >> /tmp/sherpa-0.9.txt
./Scripts/benchmark-diarization.py score \
  --reference /tmp/ES2004a.rttm --hypothesis /tmp/sherpa-0.9.txt \
  --format sherpa --audio ES2004a.Mix-Headset.wav

# Oracle-count upper bound changes only the clustering argument.
/usr/bin/time -l sherpa-onnx-offline-speaker-diarization \
  --clustering.num-clusters=4 \
  --segmentation.pyannote-model=model.int8.onnx \
  --embedding.model=nemo_en_titanet_small.onnx \
  ES2004a.Mix-Headset.wav > /tmp/sherpa-oracle4.txt 2>&1 \
  && printf 'SHERPA_EXIT_OK\n' >> /tmp/sherpa-oracle4.txt

# FluidAudio v0.12.4 Sortformer NVIDIA high-latency.
/usr/bin/time -l fluidaudiocli sortformer-benchmark \
  --single-file ES2004a --nvidia-high-latency --hf --auto-download \
  --output /tmp/sortformer-es2004a.json
```

## Candidates

### FluidAudio Offline VBx

- FluidAudio `v0.12.4` (`9830ce835881c0d0d40f90aabfaae3a6da5bebfb`)
- Swift / CoreML pipeline: Pyannote segmentation, WeSpeaker embeddings, PLDA,
  VBx clustering
- SDK: Apache-2.0
- Models: CC-BY-4.0
- Runtime model cache: 36.1 MiB (manually observed with `du`)
- Benchmark CLI binary: 9.1 MiB (manually observed; not an app-size delta)
- Sources:
  - <https://github.com/FluidInference/FluidAudio>
  - <https://github.com/FluidInference/FluidAudio/blob/v0.12.4/Documentation/Diarization/BenchmarkAMISubset.md>
  - <https://huggingface.co/FluidInference/speaker-diarization-coreml/tree/1ed7a662fdc7109e36d822db793ee6eebdaf8594>

Thresholds `0.65`, `0.70`, `0.75`, and `0.80` were tuned only on ES2008b/c/d.
`0.80` won (11.4% average DER), then remained fixed for held-out and stress
runs.

#### Held-out AMI (8 meetings)

| Metric | Result |
| --- | ---: |
| Average DER | 10.45% |
| Dominant-speaker accuracy | 7 / 8 (87.5%) |
| Exact speaker count | 0 / 8 |
| Mean absolute speaker-count error | 1.5 |
| Average speed | 147.8x real time |
| Average overlap recall | 0.045% |

| Meeting | DER | Speakers | Main speaker |
| --- | ---: | ---: | --- |
| ES2004a | 11.9% | 5 / 4 | Correct |
| ES2004b | 7.8% | 6 / 4 | Correct |
| ES2004c | 8.3% | 5 / 4 | Correct |
| ES2004d | 13.2% | 5 / 4 | **Wrong** |
| IS1009a | 15.0% | 6 / 4 | Correct |
| IS1009b | 5.6% | 5 / 4 | Correct |
| IS1009c | 5.9% | 6 / 4 | Correct |
| IS1009d | 16.0% | 6 / 4 | Correct |

#### Required scenarios

| Scenario | Evidence | Result |
| --- | --- | --- |
| Dominant speaker in a meeting containing questions | ES2004a: dominant share 41.25%, 23 annotated question acts; question-to-role attribution was not evaluated | Main cluster mapped correctly; 11.95% DER; 5 / 4 speakers |
| Overlapping speech | ES2004a: 178.45 s annotated overlap | 0.062% overlap recall — **fail** |
| Room noise / distant | ES2004a Array1-01 | 18.15% DER; main correct; 5 / 4; 9.0% silence false alarms |
| Two similar voices | ES2008c A/B same-gender pair | 46.69% DER; main correct; 5 / 2 — **fail** |
| Long silence / breaks | Same pair: 105.09 s longest silence | 30.04% silence false alarms — **fail** |
| 60-minute local | 3,600 s composite, 8 speakers, 70.31 s longest silence | 25.69 s; 140.1x; 10 / 8; main correct; 6.39% DER |

The 60-minute process used a manually observed 711.6 MiB maximum RSS and
866.5 MiB peak memory footprint. Performance passes. Identity reliability does
not.

### sherpa-onnx Pyannote + TitaNet

- sherpa-onnx `v1.13.6`
- Pyannote segmentation INT8 ONNX + `nemo_en_titanet_small.onnx`
- Apache-2.0 runtime; segmentation includes its licence, but the standalone
  TitaNet asset did not co-download a licence file, so redistribution review
  remains open
- Active models: 39.9 MiB (manually observed with `stat`)
- Extracted prebuilt runtime: 57.7 MiB (manually observed with `du`)
- Prebuilt runtime carries its own ONNX Runtime; it does not reuse ZenVoice's
  pinned ORT 1.24.2
- Source: <https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/models.html>

| Configuration on ES2004a | DER | Speakers | Main | Speed | Max RSS |
| --- | ---: | ---: | --- | ---: | ---: |
| Threshold 0.9 | 24.83% | 17 / 4 | Correct | 12.2x | 509.6 MiB |
| Oracle count = 4 | 25.28% | 4 / 4 | Correct | 12.2x | 449 MiB |

Threshold 0.7 produced 67 clusters; 0.9 still produced 17. Even with the true
speaker count supplied, DER remained ~25%. Porting this pipeline onto the
existing ORT seam has no accuracy evidence and is rejected. No 60-minute run was
performed after the baseline accuracy failure.

The TitaNet weight originated from NeMo but ran as ONNX; no NeMo runtime was
installed or proposed.

### FluidAudio Sortformer (NVIDIA high-latency)

- CoreML model: `FluidInference/diar-streaming-sortformer-coreml`
- Model cache: 252.3 MiB (manually observed with `du`)
- Source: <https://github.com/FluidInference/FluidAudio/blob/v0.12.4/Documentation/Diarization/Sortformer.md>

| Meeting | DER | Miss | Speakers | Speed | Max RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| ES2004a | 33.67% | 24.58% | 4 / 4 | 170.6x | 571.2 MiB |

Correct slot count did not offset the missed speech. The candidate failed the
single-meeting accuracy gate, so broader and 60-minute runs were not justified.

## Limitations

- The held-out set contains eight AMI meetings and the tuning set contains
  three; there is one true distant-microphone run.
- The A/B stress case is a same-gender proxy, not a measured acoustic-similarity
  pair.
- Question acts were counted, but question-to-speaker routing and extraction
  were not evaluated.
- Overlap recall means only that more than one hypothesis label was active; it
  does not prove the correct overlapping identities.
- Dominant correctness uses optimal reference-cluster mapping. It is not person
  identification.
- The numerical gate is post-hoc and must be frozen before evaluating a future
  candidate.
- Fluid and Sortformer memory plus ancillary size claims are manually observed.
  Accuracy calculations were independently reviewed before the ephemeral raw
  artifacts were cleaned; the repository does not retain a raw evidence archive.

## Why the gate stops

FluidAudio Offline VBx is the only candidate near acceptable average DER, but
its failure shape is unsafe for Teacher / Students labels:

1. It over-fragments every held-out meeting.
2. It chooses the wrong dominant speaker on one of eight held-out meetings and
   one of three tuning meetings.
3. It does not represent annotated overlap.
4. It turns a two-speaker same-gender scenario into five clusters.
5. It labels speech during 30.04% of annotated silence frames in that stress
   case.

Those are not presentation defects. They are incorrect identity boundaries.
Per ADR 0015, ZenVoice must show no role view rather than manufacture one.

## Reconsideration gate

Re-open integration only when a local macOS candidate, on the same frozen
harness:

- reaches at least 95% held-out dominant-speaker accuracy,
- has no dominant-speaker miss in the required stress cases,
- keeps absolute speaker-count error at 1 or below per scenario,
- detects at least half of annotated overlap,
- keeps the 60-minute run under 1 GiB and above 10x real time,
- has a reviewable licence, pinned model revision, and local-only runtime.

Until then, Lecture v1 remains unchanged and no diarization UI, model download,
or runtime dependency ships.
