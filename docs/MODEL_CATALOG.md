# Verified Model Catalogue

ZenVoice downloads only entries compiled into `VerifiedModelCatalog`. A
catalogue entry is accepted only after its publisher, source, pinned revision,
file size, format, language coverage, licence, attribution, and SHA-256 have
been reviewed.

## Approved sources

- Stock converted models:
  [`ggerganov/whisper.cpp`](https://huggingface.co/ggerganov/whisper.cpp)
- Pinned revision: `5359861c739e955e79d9a303bcbc70fb988958b1`
- Upstream model:
  [`openai/whisper`](https://github.com/openai/whisper)
- Runtime and conversion licence:
  [MIT](https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE)
- Format: `whisper.cpp` GGML
- Hinglish specialist:
  [`imYChaudhary22/zenvoice-hinglish-apex-ggml`](https://huggingface.co/imYChaudhary22/zenvoice-hinglish-apex-ggml)
- Pinned revision: `0c540ce8945ef96b2880f2d2c0d05ba419621171`
- Upstream model:
  [`Oriserve/Whisper-Hindi2Hinglish-Apex`](https://huggingface.co/Oriserve/Whisper-Hindi2Hinglish-Apex)
- Specialist licence: Apache-2.0

For `whisper.cpp` GGML models, the application constructs revision-pinned
HTTPS URLs itself. It does not accept a user-supplied download URL, execute
model-repository code, deserialize Python objects, or install repository
scripts.

## Speech model catalogue

Four models, each the measured best at one job.

| Tier | Capability | File | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| Balanced | Multilingual | `ggml-small.bin` | 487,601,967 B | `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` |
| High Accuracy | Multilingual | `ggml-large-v3-turbo-q5_0.bin` | 574,041,195 B | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` |
| High Accuracy | Hinglish | `ggml-hindi2hinglish-apex-q8_0.bin` | 874,188,075 B | `0b4324d2c1ad64f20883ee7fcd5d2bb0a8466287dc70d74bc47066200c28c719` |
| High Accuracy | Multilingual | `ggml-medium.bin` | 1,533,763,059 B | `6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208` |

### Why four and not ten

The catalogue originally offered ten models: two size ladders — tiny, base,
small, medium — on the assumption that model size buys a smooth
speed-for-accuracy trade the user can position themselves on. Benchmarked end
to end, that assumption fails.

**Multilingual is a cliff, not a curve.** Below Turbo there is no "faster with a
little less accuracy" — there is unusable:

| Model | WER | CER | p50 |
| --- | ---: | ---: | ---: |
| **Whisper Turbo** | **13.2%** | 5.1% | 1,451 ms |
| Whisper Medium | 14.5% | 5.0% | 1,173 ms |
| Whisper Small | 35.5% | 12.5% | 456 ms |
| Whisper Base | 55.1% | 27.9% | 139 ms |
| Whisper Tiny | 64.5% | 34.8% | 91 ms |

Whisper Small survives only as the fallback for Macs that cannot run Turbo well
— Intel — and is offered as that rather than as a speed tier. At 35.5% it is
European-languages-only in practice, scoring 100% word error rate on both
Japanese and Mandarin.

Whisper Base multilingual had been offered for months and was measured for the
first time when this cut was made.

### Retired

Retired from new downloads, still resolvable and verifiable: Whisper Tiny
(English and multilingual), Whisper Base (English and multilingual), Whisper
Small English, Whisper Medium English, and the Parakeet Unified EN CoreML
bundle.

Retired rather than deleted because selection is stored by identifier: a missing
catalogue entry would turn a working model on disk into "no model installed" and
send discovery down its legacy fallback path. Anything already installed keeps
working, and the Models screen offers to reclaim the disk.

The Parakeet model was retired because it required the closed-source FluidAudio
runtime. ZenVoice now uses `whisper.cpp` as its only local speech engine.

The catalogue metadata was verified against the official Hugging Face API on
2026-07-26 at the pinned revision. Any model revision or file replacement
requires a new review and new checksum; existing entries must not silently
follow a moving branch.

## Speech engine catalogue

ZenVoice now selects from a multi-engine runtime layer. Each engine is recorded
with the same provenance requirements as a model: publisher, runtime family,
format, licence, attribution, and privacy posture.

| Engine | Family | Download | Internet | Format | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Whisper | `whisper` | Required | No | whisper.cpp GGML | MIT | Active |
| Apple Speech | `appleSpeech` | None | No | SFSpeechRecognizer (on-device) | Apple Software License | Active |
| Parakeet TDT v2 | `parakeetTDT` | Planned | No | Core ML / ONNX | NVIDIA Open Model License | Reserved (Phase 2) |
| Parakeet TDT v3 | `parakeetTDT` | Planned | No | Core ML / ONNX | NVIDIA Open Model License | Reserved (Phase 2) |
| Parakeet Flash | `parakeetFlash` | Planned | No | Core ML / ONNX | NVIDIA Open Model License | Reserved (Phase 2) |
| Nemotron Speech 3.5 Ultra Fast | `nemotronSpeech` | Planned | No | Core ML / ONNX | NVIDIA Open Model License | Reserved (Phase 2) |
| Nemotron 3.5 Multilingual | `nemotronSpeech` | Planned | No | Core ML / ONNX | NVIDIA Open Model License | Reserved (Phase 2) |
| Cohere Transcribe | `cohereTranscribe` | None | Yes | Cloud API | Cohere Terms of Service | Reserved (Phase 5, opt-in) |

Reserved engines fix the identifier and family now so later phases can add
runtime implementations and download logic without renaming user preferences
or changing the catalogue schema. The source repositories above are the
intended upstreams; revision, size, and SHA-256 will be pinned when the engine
is activated.

Apple Speech is configured with `requiresOnDeviceRecognition = true`, so
audio never leaves the Mac. Whisper and the planned NVIDIA engines run
entirely on-device using downloaded weights. Cohere Transcribe is the only
engine that sends audio off-device, and it requires explicit opt-in plus an
API key in Phase 5.

## Which model gets recommended

`ModelRecommendationEngine.recommendedModelID(for:)` names exactly one model per
Mac, and only that model carries the "Recommended" badge.

| Condition | Recommendation | Why |
| --- | --- | --- |
| Hinglish profile | Hinglish Apex | Preserves code-switched English words in Latin script |
| English profile, Apple Silicon | Whisper Turbo | Best open multilingual model on the GPU |
| Apple Silicon, ≥ 8 GB | Whisper Turbo | Best measured accuracy/size trade-off on the GPU, and multilingual |
| Apple Silicon, < 8 GB | Whisper Small (multilingual) | Keeps memory pressure down; the only smaller multilingual option that works at all |
| Intel, any memory | Whisper Small (multilingual) | No Metal path; large models are too slow without GPU transcription |

Two rules were replaced here. The first picked a tier from installed memory
alone, which sent capable 16 GB Apple Silicon Macs to Whisper Base — measured at
roughly one word in three wrong when the speaker is fast. Memory says nothing
about whether a Mac can transcribe quickly; the presence of a Metal path does.

The second sent small Intel Macs to Whisper Tiny multilingual on the theory that
responsiveness has to win. At 64.5% word error rate Tiny is not a faster option,
it is a broken one, so those Macs now get Small and a slower answer that is
actually usable. Recommending a model that cannot do the job is worse than
recommending one that is merely slow.

English users were previously sent to multilingual Turbo; now they remain on
Turbo on Apple Silicon and Small on Intel. See
[ACCURACY_HARNESS.md](ACCURACY_HARNESS.md) for how the underlying numbers are
produced.

Text refinement is deterministic. The former Qwen/llama.cpp path was removed
after human-annotated evaluation found no accuracy gain beyond the rule engine.

## Installation contract

This contract describes the `whisper.cpp` GGML path:

1. The user explicitly starts a download.
2. ZenVoice accepts only the catalogue-generated HTTPS URL.
3. The response must be successful and remain on HTTPS.
4. The temporary file must be a regular file with the exact approved size.
5. ZenVoice streams the file through SHA-256 and compares the full digest.
6. Only a verified file is atomically moved into private Application Support.
7. Model files receive user-only filesystem permissions.

Deleting a model removes only its catalogue-derived file path. Model downloads
contain data weights only; ZenVoice never executes them.

## Hardware recommendations

Language capability and performance tier are separate choices. ZenVoice uses
physical memory only to choose the default tier:

| Memory | Default tier |
| ---: | --- |
| Less than 12 GB | Fast |
| 12–19 GB | Balanced |
| 20 GB or more | High Accuracy |

Available storage must also leave installation headroom. A model that does not
fit is not downloadable until the user frees space. Other compatible tiers
remain available as a manual override.

After a successful local transcription, ZenVoice stores only model ID, audio
duration, processing duration, and timestamp as a local benchmark sample. It
does not duplicate the transcript or audio. The Models screen reports weighted
real-time factor from up to 50 recent samples so recommendations can be judged
against evidence from the user's own Mac.

The reproducible M5 comparison across seven installed models, eight languages,
multiple voices, speaking rates, memory, and real Hinglish is recorded in
[LANGUAGE_MODEL_BENCHMARK_2026-07-26.md](LANGUAGE_MODEL_BENCHMARK_2026-07-26.md).

## Bundled runtime

ZenVoice uses the official `whisper.cpp` v1.9.1 XCFramework release:

- Source: [`ggml-org/whisper.cpp`](https://github.com/ggml-org/whisper.cpp)
- Release: `v1.9.1`
- Source commit: `f049fff95a089aa9969deb009cdd4892b3e74916`
- Artifact: `whisper-v1.9.1-xcframework.zip`
- SHA-256:
  `8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c`
- Licence: MIT

Swift Package Manager verifies that checksum before exposing the binary target.
The packaged app embeds and signs `whisper.framework`. ZenVoice calls its C API
in-process and retains one model context until the selected model changes or
the application exits.
