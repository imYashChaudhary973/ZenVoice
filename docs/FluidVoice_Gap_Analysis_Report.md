# ZenVoice vs FluidVoice Gap Analysis Report

**Status:** Updated 2026-08-19. The previous version of this file was stale
and told agents to add engines that already exist. Do not re-implement
Nemotron, Cohere, Apple Speech, Parakeet Flash/v2, or FluidAudio.

## Executive Summary

FluidVoice ships a wide model catalog and polished live preview. ZenVoice
already has the same local ASR engines. Competing by adding more weights
loses. The product sentence that is true today:

> English dictation: Parakeet TDT v3, 6.9% WER, 73× real time. Everything
> else is fallback. Hindi-English: Apex. Privacy: on-device, encrypted
> history, no telemetry.

## 1. Engines already in ZenVoice

Do **not** rebuild these. They live in `VerifiedEngineCatalog` and
`ZenVoiceRuntime`.

| Engine | ID | Runtime | Role after 2026-08-19 |
|---|---|---|---|
| Parakeet TDT v3 | `parakeet-tdt-v3` | parakeet.cpp GGUF | **Default** for English / 25 European languages |
| Whisper Turbo | `whisper` + `whisper-large-v3-turbo` | whisper.cpp GGML | **Default** for auto-detect / 99 languages |
| Hinglish Apex | `hindi2hinglish-apex` | whisper.cpp GGML | **Only** Hinglish engine |
| Apple Speech | `apple-speech` | SFSpeechRecognizer | Zero-download fallback. Unmeasured. |
| Whisper Small | `whisper-small-multilingual` | whisper.cpp GGML | Intel compromise (no Metal) |
| Parakeet TDT v2 | `parakeet-tdt-v2` | parakeet.cpp GGUF | Advanced, English-only |
| Parakeet Flash | `parakeet-flash` | parakeet.cpp streaming | **Preview only** (14.1% WER) |
| Nemotron 3.5 | one GGUF, Streaming / Offline toggle | parakeet.cpp | Streaming = preview only (23.8% WER) |
| Cohere Transcribe | `cohere-transcribe` | ONNX INT8, local | Local, off by default, ~3 GB, slower. Not cloud. |

Whisper Tiny and Base stay **retired**. Restoring them to match FluidVoice's
ladder would ship 55–65% WER.

Nemotron Ultra Fast and Nemotron Multilingual are the **same checkpoint**.
The UI is one row. Do not add a second Nemotron download.

FluidAudio / Fluid Intelligence stay **gone**: the closed-source dependency
and the Parakeet CoreML runtime were removed in the Apache-2.0 transition, and
the NVIDIA engines now run on open `parakeet.cpp`.

## 2. Measured table (authoritative)

Frozen Common Voice Spontaneous test, 262 clips, 2026-08-18, M5, through
`SpeechEngine.transcribe(audioURL:)`:

| Engine | Whole WER | Real time |
|---|---:|---:|
| Parakeet TDT v3 | **6.9%** | **73×** |
| Parakeet TDT v2 | 7.3% | 73× |
| Whisper Turbo | 8.2% | 11× |
| Cohere Transcribe | 10.8% | 5× |
| Nemotron Multilingual | 13.8% | 45× |
| Parakeet Flash | 14.1% | 16× |
| Nemotron Ultra Fast | 23.8% | 12× |
| Apple Speech | not measured | manual QA |

Source: [REAL_SPEECH_CORPUS.md](REAL_SPEECH_CORPUS.md) §5.

`EngineRecommendationEngine` and `ModelRecommendationEngine` must follow this
table. Do not prefer Cohere or Nemotron Ultra Fast because FluidVoice lists
them first.

## 3. Remaining gaps (not engines)

These are still real. They are UX and evidence, not missing models.

| Gap | Notes |
|---|---|
| Consented session 001 | Zero recordings. Public WER is a floor, not dictation. Cycle forbids fabricating consent. |
| Live preview polish | Overlay kinds exist; Flash/Nemotron can preview. Notch UX still thinner than FluidVoice. |
| Rewrite-selected-text | FluidVoice has it. ZenVoice does not. |
| Meeting / file transcription | Not built. |
| Cohere CoreML EP | Broken on ORT 1.24 external-data. Today Cohere is a slow CPU 3 GB model. |
| Apple Speech WER | Unmeasured. Treat as convenience. |
| TDT v3 language ceiling | 25 European languages. Hindi / Japanese / Mandarin stay on Whisper. |

## 4. What not to do

- Do not re-add FluidAudio or Fluid Intelligence.
- Do not put a local LLM on Smart formatting (DISCO: rules 23.2% → 7.2%, LLM +0.0).
- Do not shrink Whisper's 30 s encoder window (41% faster, ~8× worse WER).
- Do not fine-tune Whisper on AMI/public data and ship it.
- Do not download every FluidVoice weight "for parity."
- Do not restore Tiny/Base.

## 5. How to counter FluidVoice

Out-default them. Do not out-catalogue them.

| Their move | ZenVoice counter |
|---|---|
| 10-model picker | 3 defaults + advanced. WER table on the Models screen. |
| Nemotron Ultra Fast as hero | 23.8% WER. Preview only. |
| Whisper Tiny→Large ladder | Cliff, already measured. Tiny/Base retired. |
| Fluid Intelligence (closed) | Deterministic Clean/Smart + meaning guard. |
| Analytics default-on | None. |
| English-first | Apex keeps 85% English loanwords; Turbo keeps 0/31. |
| Closed FluidAudio runtime | Open parakeet.cpp + whisper.cpp + ORT. |

## 6. Strengths to keep

- Encrypted local history (AES-GCM + Keychain)
- No accounts, no telemetry, no cloud transcription by default
- Verified catalogue (URL, size, SHA-256, licence)
- Modular SPM targets
- Hinglish specialist
- Apache-2.0, no FluidAudio
