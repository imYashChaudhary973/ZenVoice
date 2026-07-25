# Verified Model Catalogue

ZenVoice downloads only entries compiled into `VerifiedModelCatalog`. A
catalogue entry is accepted only after its publisher, source, pinned revision,
file size, format, language coverage, licence, attribution, and SHA-256 have
been reviewed.

## Approved source

- Converted models:
  [`ggerganov/whisper.cpp`](https://huggingface.co/ggerganov/whisper.cpp)
- Pinned revision: `5359861c739e955e79d9a303bcbc70fb988958b1`
- Upstream model:
  [`openai/whisper`](https://github.com/openai/whisper)
- Runtime and conversion licence:
  [MIT](https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE)
- Format: `whisper.cpp` GGML

The application constructs revision-pinned HTTPS URLs itself. It does not
accept a user-supplied download URL, execute model-repository code, deserialize
Python objects, or install repository scripts.

## M3 catalogue

| Tier | Capability | File | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| Fast | English | `ggml-tiny.en.bin` | 77,704,715 B | `921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f` |
| Fast | Multilingual | `ggml-tiny.bin` | 77,691,713 B | `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` |
| Balanced | English | `ggml-base.en.bin` | 147,964,211 B | `a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002` |
| Balanced | Multilingual | `ggml-base.bin` | 147,951,465 B | `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe` |
| Balanced | English | `ggml-small.en.bin` | 487,614,201 B | `c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d` |
| Balanced | Multilingual | `ggml-small.bin` | 487,601,967 B | `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` |
| High Accuracy | Multilingual | `ggml-large-v3-turbo-q5_0.bin` | 574,041,195 B | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` |
| High Accuracy | English | `ggml-medium.en.bin` | 1,533,774,781 B | `cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356` |
| High Accuracy | Multilingual | `ggml-medium.bin` | 1,533,763,059 B | `6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208` |

The catalogue metadata was verified against the official Hugging Face API on
2026-07-25 at the pinned revision. Any model revision or file replacement
requires a new review and new checksum; existing entries must not silently
follow a moving branch.

## Which model gets recommended

`ModelRecommendationEngine.recommendedModelID(for:)` names exactly one model per
Mac, and only that model carries the "Recommended" badge.

| Mac | Recommendation | Why |
| --- | --- | --- |
| Apple Silicon, ≥ 8 GB | Whisper Turbo | Matches Whisper Medium's accuracy at about a third of the download, and is multilingual |
| Apple Silicon, < 8 GB | Whisper Small (multilingual) | Keeps memory pressure down without falling back to Base |
| Intel, ≥ 16 GB | Whisper Small (multilingual) | No Metal path, so size turns directly into waiting |
| Intel, < 16 GB | Whisper Tiny (multilingual) | Responsiveness has to win |

This replaced a rule that picked a tier from installed memory alone, which sent
capable 16 GB Apple Silicon Macs to Whisper Base — measured at roughly one word
in three wrong when the speaker is fast. Memory says nothing about whether a Mac
can transcribe quickly; the presence of a Metal path does. See
[ACCURACY_HARNESS.md](ACCURACY_HARNESS.md) for how the underlying numbers are
produced.

## M14 refinement catalogue

Text refinement has a separate allowlist in
`VerifiedRefinementModelCatalog`. ZenVoice offers only Qwen-published,
Apache-2.0 GGUF artifacts:

| Tier | Model | File | Size | Minimum memory | SHA-256 |
| --- | --- | --- | ---: | ---: | --- |
| Fast | Qwen2.5 0.5B Instruct | `qwen2.5-0.5b-instruct-q4_k_m.gguf` | 491,400,032 B | 8 GB | `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db` |
| Balanced | Qwen2.5 1.5B Instruct | `qwen2.5-1.5b-instruct-q4_k_m.gguf` | 1,117,320,736 B | 16 GB | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` |

Pinned revisions:

- Fast: `9217f5db79a29953eb74d5343926648285ec7e67`
- Balanced: `91cad51170dc346986eccefdc2dd33a9da36ead9`

Qwen documents the Qwen2.5 family as supporting more than 29 languages,
including English, Chinese, French, Spanish, Portuguese, German, Italian,
Russian, Japanese, Korean, Vietnamese, Thai, and Arabic. Language support is
not a promise of equal quality; ZenVoice still needs per-language evaluation.

The Qwen 3B repository was not admitted because its published licence marker
differs from the Apache-2.0 entries above. A model is never included merely
because it is technically compatible.

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

The local refinement runtime uses the official `llama.cpp` b9637 XCFramework:

- Source: [`ggml-org/llama.cpp`](https://github.com/ggml-org/llama.cpp)
- Release: `b9637`
- Source commit: `aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3`
- Artifact: `llama-b9637-xcframework.zip`
- SHA-256:
  `46c7dad871f804d82399ddcfeb54d23b6469888801fc35124d7e33e543a9bef7`
- Licence: MIT

This version is newer than the fix boundary for the
[2025 GGUF vocabulary buffer-overflow advisory](https://github.com/ggml-org/llama.cpp/security/advisories/GHSA-8wwf-w4qm-gpqr).
ZenVoice still accepts only exact catalogue files with verified size and
checksum. The packaged app embeds and signs `llama.framework`.
