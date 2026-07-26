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

The application constructs revision-pinned HTTPS URLs itself. It does not
accept a user-supplied download URL, execute model-repository code, deserialize
Python objects, or install repository scripts.

## Speech model catalogue

| Tier | Capability | File | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| Fast | English | `ggml-tiny.en.bin` | 77,704,715 B | `921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f` |
| Fast | Multilingual | `ggml-tiny.bin` | 77,691,713 B | `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` |
| Balanced | English | `ggml-base.en.bin` | 147,964,211 B | `a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002` |
| Balanced | Multilingual | `ggml-base.bin` | 147,951,465 B | `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe` |
| Balanced | English | `ggml-small.en.bin` | 487,614,201 B | `c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d` |
| Balanced | Multilingual | `ggml-small.bin` | 487,601,967 B | `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` |
| High Accuracy | Multilingual | `ggml-large-v3-turbo-q5_0.bin` | 574,041,195 B | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` |
| High Accuracy | Hinglish | `ggml-hindi2hinglish-apex-q8_0.bin` | 874,188,075 B | `0b4324d2c1ad64f20883ee7fcd5d2bb0a8466287dc70d74bc47066200c28c719` |
| High Accuracy | Multilingual | `ggml-medium.bin` | 1,533,763,059 B | `6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208` |

Whisper Medium English-only is retired from new downloads. Existing verified
installs remain resolvable so an upgrade does not silently disable a working
selection.

The catalogue metadata was verified against the official Hugging Face API on
2026-07-26 at the pinned revision. Any model revision or file replacement
requires a new review and new checksum; existing entries must not silently
follow a moving branch.

## Which model gets recommended

`ModelRecommendationEngine.recommendedModelID(for:)` names exactly one model per
Mac, and only that model carries the "Recommended" badge.

| Condition | Recommendation | Why |
| --- | --- | --- |
| Hinglish profile | Hinglish Apex | Preserves code-switched English words in Latin script |
| Apple Silicon, ≥ 8 GB | Whisper Turbo | Best measured accuracy/size trade-off on the GPU and multilingual |
| Apple Silicon, < 8 GB | Whisper Small (multilingual) | Keeps memory pressure down without falling back to Base |
| Intel, ≥ 16 GB | Whisper Small (multilingual) | No Metal path, so size turns directly into waiting |
| Intel, < 16 GB | Whisper Tiny (multilingual) | Responsiveness has to win |

This replaced a rule that picked a tier from installed memory alone, which sent
capable 16 GB Apple Silicon Macs to Whisper Base — measured at roughly one word
in three wrong when the speaker is fast. Memory says nothing about whether a Mac
can transcribe quickly; the presence of a Metal path does. See
[ACCURACY_HARNESS.md](ACCURACY_HARNESS.md) for how the underlying numbers are
produced.

Text refinement is deterministic. The former Qwen/llama.cpp path was removed
after human-annotated evaluation found no accuracy gain beyond the rule engine.

## Installation contract

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
