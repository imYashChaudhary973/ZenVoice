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
| High Accuracy | English | `ggml-medium.en.bin` | 1,533,774,781 B | `cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356` |
| High Accuracy | Multilingual | `ggml-medium.bin` | 1,533,763,059 B | `6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208` |

The catalogue metadata was verified against the official Hugging Face API on
2026-07-23. Any model revision or file replacement requires a new review and
new checksum; existing entries must not silently follow a moving branch.

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
