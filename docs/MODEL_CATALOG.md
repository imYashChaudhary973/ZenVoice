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
runtime. ZenVoice now uses `whisper.cpp`, Apple Speech, `parakeet.cpp`, and
ONNX Runtime as its local speech runtimes.

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
| Parakeet TDT v2 | `parakeetTDT` | Required | No | GGUF (parakeet.cpp v0.5.0) | CC-BY-4.0 | Active |
| Parakeet TDT v3 | `parakeetTDT` | Required | No | GGUF (parakeet.cpp v0.5.0) | CC-BY-4.0 | Active |
| Parakeet Flash | `parakeetFlash` | Required | No | GGUF (parakeet.cpp v0.5.0, streaming) | CC-BY-4.0 | Active (Beta) |
| Nemotron Speech 3.5 Ultra Fast | `nemotronSpeech` | Required | No | GGUF (parakeet.cpp v0.5.0, streaming) | OpenMDW-1.1 | Active |
| Nemotron 3.5 Multilingual | `nemotronSpeech` | Required | No | GGUF (parakeet.cpp v0.5.0) | OpenMDW-1.1 | Active |
| Cohere Transcribe | `cohereTranscribe` | Required | No | ONNX INT8 (encoder-decoder, CoreML provider) | Apache-2.0 | Active (Beta / High Accuracy) |

### Active GGUF downloads

All NVIDIA engines ship as quantized GGUF files converted for `parakeet.cpp`.
They are downloaded from the community mirror
[`mudler/parakeet-cpp-gguf`](https://huggingface.co/mudler/parakeet-cpp-gguf)
using the same pinned-URL + size + SHA-256 contract as Whisper.

| Engine | Upstream | GGUF filename | Size | SHA-256 |
| --- | --- | --- | ---:|:---|
| Parakeet TDT v2 | `nvidia/parakeet-tdt-0.6b-v2` | `tdt-0.6b-v2-q8_0.gguf` | 903,835,936 B | `2027e2e1a4dc60ccdd8558f93b15e7c0db4ef8895b4e82e889f3a6275d8119c6` |
| Parakeet TDT v3 | `nvidia/parakeet-tdt-0.6b-v3` | `tdt-0.6b-v3-q8_0.gguf` | 940,663,680 B | `4d69a4a6683f4f2d952bad794c1357ca6eb628027695b4699c5a9ad4cd07d757` |
| Parakeet Flash | `nvidia/parakeet_realtime_eou_120m-v1` | `realtime_eou_120m-v1-q8_0.gguf` | 176,001,472 B | `62616b914d6f5a683a5dea672df055b57de5c49dddf871b8b44b9c814dc3d896` |
| Nemotron Speech 3.5 Ultra Fast | `nvidia/nemotron-3.5-asr-streaming-0.6b` | `nemotron-3.5-asr-streaming-0.6b-q8_0.gguf` | 983,696,512 B | `ba2f13eccd4a5245be728f77e6149bd6a4fdcdd133ff2e08ac6005bcef7a99f1` |
| Nemotron 3.5 Multilingual | `nvidia/nemotron-3.5-asr-streaming-0.6b` (same checkpoint) | `nemotron-3.5-asr-streaming-0.6b-q8_0.gguf` | 983,696,512 B | `ba2f13eccd4a5245be728f77e6149bd6a4fdcdd133ff2e08ac6005bcef7a99f1` |

### Active ONNX downloads

Cohere Transcribe ships as three verified files from
[`cstr/cohere-transcribe-onnx-int8`](https://huggingface.co/cstr/cohere-transcribe-onnx-int8):

| File | Size | SHA-256 |
|---|---|---:|:---|
| `cohere-encoder.int8.onnx` | 6,164,263 B | `27ef3d3a2352c972fa4831ae680d52937a2d4e5d62910060f140b13e2f4ccd2b` |
| `cohere-encoder.int8.onnx.data` | 2,839,314,432 B | `0a6ebd1efbaeef6d15106e33671ce73067cad862bbb20f5e2dfbcd56695fbb76` |
| `cohere-decoder.int8.onnx` | 530,119 B | `4be3bdfe855b751985dd2b53d39cca66967bdcb656a138753daf12c451900358` |
| `cohere-decoder.int8.onnx.data` | 222,937,088 B | `8e4d5d7ea5092cf0779b711c65dfef9ecd2b88df951c6c7aa334df345c2eb4d8` |
| `tokens.txt` | 207,437 B | `013ede043ae2480e3a9205cc34550d9686100cc682bacc90f702facdfbb93035` |

Total Cohere bundle size is approximately 3.07 GB; the `.onnx` files are small
graphs and the weights live in the `.onnx.data` external data files.

Apple Speech is configured with `requiresOnDeviceRecognition = true`, so
audio never leaves the Mac. Whisper, the NVIDIA engines, and Cohere Transcribe
run entirely on-device using downloaded weights. Cohere's cloud API remains an
optional later path that requires explicit opt-in and an API key.

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
[LANGUAGE_MODEL_BENCHMARK_2026-08-06.md](LANGUAGE_MODEL_BENCHMARK_2026-08-06.md).

## Bundled runtimes

### whisper.cpp

ZenVoice uses the official `whisper.cpp` v1.9.1 XCFramework release:

- Source: [`ggml-org/whisper.cpp`](https://github.com/ggml-org/whisper.cpp)
- Release: `v1.9.1`
- Source commit: `f049fff95a089aa9969deb009cdd4892b3e74916`
- Artifact: `whisper-v1.9.1-xcframework.zip`
- SHA-256:
  `8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c`
- Licence: MIT

### parakeet.cpp

ZenVoice vendors `parakeet.cpp` v0.5.0 as a binary XCFramework for the NVIDIA
Parakeet and Nemotron engines:

- Source: [`mudler/parakeet.cpp`](https://github.com/mudler/parakeet.cpp)
- Release: `v0.5.0`
- Runtime licence: MIT
- Local binary target: `vendor/parakeet.xcframework`
- Build: universal `libparakeet.dylib` packaged with `xcodebuild -create-xcframework`

Swift Package Manager exposes the `parakeet` binary target from
`Package.swift`. The app embeds and signs the framework. ZenVoice calls its flat
C API in-process through `Sources/ZenVoiceRuntime/ParakeetBridge.swift`.

### ONNX Runtime

ZenVoice links ONNX Runtime through the Swift Package Manager release for the
Cohere Transcribe engine:

- Source: [`microsoft/onnxruntime-swift-package-manager`](https://github.com/microsoft/onnxruntime-swift-package-manager)
- Swift product: `onnxruntime`
- Swift module: `OnnxRuntimeBindings`
- Licence: ONNX Runtime licence (MIT for the open-source runtime)

The CoreML execution provider is enabled when available; otherwise CPU execution
is used as a fallback.
