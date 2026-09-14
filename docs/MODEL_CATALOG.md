# Verified Model Catalogue

BuilderHelm Voice downloads only entries compiled into `VerifiedModelCatalog`. A
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
  [`imYChaudhary22/buildervoice-hinglish-apex-ggml`](https://huggingface.co/imYChaudhary22/buildervoice-hinglish-apex-ggml)
- Pinned revision: `0c540ce8945ef96b2880f2d2c0d05ba419621171`
- Upstream model:
  [`Oriserve/Whisper-Hindi2Hinglish-Apex`](https://huggingface.co/Oriserve/Whisper-Hindi2Hinglish-Apex)
- Specialist licence: Apache-2.0

For `whisper.cpp` GGML models, the application constructs revision-pinned
HTTPS URLs itself. It does not accept a user-supplied download URL, execute
model-repository code, deserialize Python objects, or install repository
scripts.

## Speech model catalogue

Four files, each one engine in the picker.

| Engine | Capability | File | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| Whisper Large V3 Turbo | Multilingual | `ggml-large-v3-turbo-q5_0.bin` | 574,041,195 B | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` |
| Whisper Large V3 | Multilingual | `ggml-large-v3-q5_0.bin` | 1,081,140,203 B | `d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1` |
| Distil-Whisper Large V3 | English | `ggml-distil-large-v3.bin` | 1,519,521,155 B | `2883a11b90fb10ed592d826edeaee7d2929bf1ab985109fe9e1e7b4d2b69a298` |
| Hinglish Apex | Hinglish | `ggml-hindi2hinglish-apex-q8_0.bin` | 874,188,075 B | `0b4324d2c1ad64f20883ee7fcd5d2bb0a8466287dc70d74bc47066200c28c719` |

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

The Parakeet Unified EN CoreML model was retired because it required the
closed-source FluidAudio runtime. BuilderHelm Voice now uses `whisper.cpp` and
`parakeet.cpp` as its local speech runtimes.

The catalogue metadata was verified against the official Hugging Face API on
2026-07-26 at the pinned revision. Any model revision or file replacement
requires a new review and new checksum; existing entries must not silently
follow a moving branch.

## Speech engine catalogue

Each engine is recorded with the same provenance requirements as a model:
publisher, runtime family, format, licence, attribution, and privacy posture.

| Engine | Family | Download | Internet | Format | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Whisper | `whisper` | Required | No | whisper.cpp GGML | MIT | Active |
| Parakeet TDT v3 | `parakeetTDT` | Required | No | GGUF (parakeet.cpp v0.5.0) | CC-BY-4.0 | Active |

Removed: Apple Speech, Parakeet TDT v2, Parakeet Flash, Nemotron Speech 3.5,
and Cohere Transcribe. Saved selections for those IDs are cleared.

### Measured engine accuracy (2026-08-18)

Headline for recommendation: **Parakeet TDT v3 (6.9 % whole WER, 73× real
time) beats Whisper Turbo (8.2 %, 11×) on English**. Multilingual and
Hinglish users still need Whisper-family. Full numbers:
[REAL_SPEECH_CORPUS.md §5](REAL_SPEECH_CORPUS.md).

### Active GGUF downloads

Parakeet TDT v3 ships as a quantized GGUF from
[`mudler/parakeet-cpp-gguf`](https://huggingface.co/mudler/parakeet-cpp-gguf)
using the same pinned-URL + size + SHA-256 contract as Whisper.

| Engine | Upstream | GGUF filename | Size | SHA-256 |
| --- | --- | --- | ---:|:---|
| Parakeet TDT v3 | `nvidia/parakeet-tdt-0.6b-v3` | `tdt-0.6b-v3-q8_0.gguf` | 940,663,680 B | `4d69a4a6683f4f2d952bad794c1357ca6eb628027695b4699c5a9ad4cd07d757` |

Whisper and Parakeet TDT v3 run entirely on-device using downloaded weights.

## Which engine and model get recommended

One policy, from the 2026-08-18 table. `EngineRecommendationEngine` picks the
final insert engine. `ModelRecommendationEngine.recommendedModelID(for:)` only
names the Whisper file to keep around as fallback.

| Condition | Final engine / model | Why |
| --- | --- | --- |
| English or European (TDT v3 locale list) on Apple Silicon | Parakeet TDT v3 | 6.9% WER, 73× real time |
| Auto-detect / non-European | Whisper Large V3 Turbo | 99-language coverage |
| Hinglish | Apex only | 85% English loanwords kept; Turbo/Medium keep 0/31 |
| No TDT v3 installed | Whisper Large V3 Turbo | Remaining fallback |
| Intel English | Distil-Whisper Large V3 | Faster English-only path |

Whisper Large V3 Turbo no longer carries the Recommended badge on English/European
Apple Silicon. It is the 99-language fallback. Tiny, Base, Small, and Medium stay retired.

See [REAL_SPEECH_CORPUS.md](REAL_SPEECH_CORPUS.md) §5 and
[FluidVoice_Gap_Analysis_Report.md](FluidVoice_Gap_Analysis_Report.md).

Smart text formatting can use Apple's OS-managed on-device
`SystemLanguageModel` for punctuation and layout. It is not a downloadable
BuilderHelm Voice model and therefore does not appear in this catalogue. The former
Qwen/llama.cpp refinement path remains removed after human-annotated evaluation
found no correction-accuracy gain beyond the rule engine.

## Installation contract

This contract describes the `whisper.cpp` GGML path:

1. The user explicitly starts a download.
2. BuilderHelm Voice accepts only the catalogue-generated HTTPS URL.
3. The response must be successful and remain on HTTPS.
4. The temporary file must be a regular file with the exact approved size.
5. BuilderHelm Voice streams the file through SHA-256 and compares the full digest.
6. Only a verified file is atomically moved into private Application Support.
7. Model files receive user-only filesystem permissions.

Deleting a model removes only its catalogue-derived file path. Model downloads
contain data weights only; BuilderHelm Voice never executes them.

## Hardware recommendations

Language capability and performance tier are separate choices. BuilderHelm Voice uses
physical memory only to choose the default tier:

| Memory | Default tier |
| ---: | --- |
| Less than 12 GB | Fast |
| 12–19 GB | Balanced |
| 20 GB or more | High Accuracy |

Available storage must also leave installation headroom. A model that does not
fit is not downloadable until the user frees space. Other compatible tiers
remain available as a manual override.

After a successful local transcription, BuilderHelm Voice stores only model ID, audio
duration, processing duration, and timestamp as a local benchmark sample. It
does not duplicate the transcript or audio. The Models screen reports weighted
real-time factor from up to 50 recent samples so recommendations can be judged
against evidence from the user's own Mac.

The reproducible M5 comparison across seven installed models, eight languages,
multiple voices, speaking rates, memory, and real Hinglish is recorded in
[LANGUAGE_MODEL_BENCHMARK_2026-08-06.md](LANGUAGE_MODEL_BENCHMARK_2026-08-06.md).

## Bundled runtimes

### whisper.cpp

BuilderHelm Voice uses the official `whisper.cpp` v1.9.1 XCFramework release:

- Source: [`ggml-org/whisper.cpp`](https://github.com/ggml-org/whisper.cpp)
- Release: `v1.9.1`
- Source commit: `f049fff95a089aa9969deb009cdd4892b3e74916`
- Artifact: `whisper-v1.9.1-xcframework.zip`
- SHA-256:
  `8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c`
- Licence: MIT

### parakeet.cpp

BuilderHelm Voice vendors `parakeet.cpp` v0.5.0 as a binary XCFramework for Parakeet
TDT v3:

- Source: [`mudler/parakeet.cpp`](https://github.com/mudler/parakeet.cpp)
- Release: `v0.5.0`
- Runtime licence: MIT
- Local binary target: `vendor/parakeet.xcframework`
- Build: universal `libparakeet.dylib` packaged with `xcodebuild -create-xcframework`

Swift Package Manager exposes the `parakeet` binary target from
`Package.swift`. The app embeds and signs the framework. BuilderHelm Voice calls its flat
C API in-process through `Sources/BuilderVoiceRuntime/ParakeetBridge.swift`.
