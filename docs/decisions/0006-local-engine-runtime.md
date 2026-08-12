# ADR 0006 — Local Engine Runtime for Parakeet, Nemotron, and Cohere

## Status

Accepted — implemented 2026-08-06. Parakeet TDT v2/v3, Parakeet Flash,
Nemotron Speech 3.5 variants, and Cohere Transcribe are wired into the
`SpeechEngine` registry. Parakeet/Nemotron use `parakeet.cpp` v0.5.0; Cohere
uses ONNX Runtime Swift with the CoreML execution provider.

## Context

Phase 1 built the multi-engine registry (`SpeechEngine`, `EngineRegistry`,
`EngineDescriptor`) and added Apple Speech as a zero-download, on-device
engine. Phase 2 wanted to add:

- Parakeet TDT v2 / v3 / Flash (NVIDIA)
- Nemotron Speech 3.5 Ultra Fast / Multilingual (NVIDIA)
- Cohere Transcribe (Cohere Labs)

The model weights are available on Hugging Face, but ZenVoice removed the
closed-source `FluidAudio` runtime in Phase 1. We need an open-source execution
layer that can load and run these checkpoints on macOS without sending audio
off-device.

## Research findings

### Parakeet and Nemotron

| Runtime | License | Supports | Maturity | Notes |
|---|---|---|---|---|
| `mudler/parakeet.cpp` | MIT | Parakeet TDT v2/v3, Nemotron 3.5 ASR streaming, Parakeet Flash | Active community project | C++17/ggml runtime, flat C API, CMake build, no official XCFramework. |
| `mweinbach/parakeet-coreml-swift` | Apache-2.0 (code), CC-BY-4.0 (weights) | Parakeet TDT v3 only | Early (v0.1.1) | Ready Swift package, auto-downloads CoreML model, macOS 14+. |
| Community CoreML ports | Various | Nemotron, Parakeet v3 | Unofficial | e.g. `aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8`, `mweinbach1/parakeet-tdt-0.6b-v3-coreml`. |
| `k2-fsa/sherpa-onnx` | Apache-2.0 | Nemotron ONNX export scripts | Mature | Provides Python export scripts; we'd still need ONNX Runtime Swift. |

`parakeet.cpp` is the only open runtime that covers Parakeet and Nemotron with
one dependency. It uses ggml (same backend family as whisper.cpp), so the build
and Metal/ANE path is conceptually similar to what ZenVoice already ships.

We vendored `parakeet.cpp` v0.5.0 as a universal `libparakeet.dylib`, packaged
it into `vendor/parakeet.xcframework`, and exposed it as a SwiftPM binary
target named `parakeet`. The C API imports into Swift as an `OpaquePointer`-
based flat interface.

### Cohere Transcribe

| Runtime | License | Supports | Notes |
|---|---|---|---|
| ONNX Runtime + CoreML provider | ONNX Runtime license / Cohere Apache-2.0 weights | `CohereLabs/cohere-transcribe-03-2026` | `cstr/cohere-transcribe-onnx-int8` is a 2B parameter INT8 encoder-decoder ONNX export with a `tokens.txt` tokenizer. |
| `FluidInference/cohere-transcribe-03-2026-coreml` | Proprietary runtime | CoreML INT8 | Used by FluidAudio; not open-source. |

The practical path for Cohere is ONNX Runtime Swift with the CoreML execution
provider. The chosen export uses an encoder-decoder split: the encoder accepts
raw 16 kHz mono float PCM and contains the mel frontend internally; the
decoder performs greedy autoregressive generation with self-attention and
cross-attention KV caches. The Swift side implements the tokenizer and greedy
loop in `CohereTranscribeEngine`.

## Decision

**Adopt `parakeet.cpp` for Parakeet and Nemotron, and ONNX Runtime Swift for Cohere Transcribe.**

Integration order executed:

1. Parakeet TDT v3 (`tdt-0.6b-v3-q8_0.gguf`)
2. Parakeet TDT v2 (`tdt-0.6b-v2-q8_0.gguf`)
3. Nemotron Speech 3.5 variants (`nemotron-3.5-asr-streaming-0.6b-q8_0.gguf`)
4. Parakeet Flash (`realtime_eou_120m-v1-q8_0.gguf`)
5. Cohere Transcribe (`cohere-encoder.int8.onnx`, `cohere-decoder.int8.onnx`, `tokens.txt`)

Each engine is a separate `SpeechEngine` conforming type in `ZenVoiceRuntime`:

- `ParakeetTDTv3Engine`
- `ParakeetTDTv2Engine`
- `NemotronSpeechUltraFastEngine`
- `NemotronSpeechMultilingualEngine`
- `ParakeetFlashEngine`
- `CohereTranscribeEngine`

They share `ParakeetBridge.swift`, which wraps the flat C API and provides both
whole-file (`transcribe(url:languageCode:)`) and streaming
(`transcribeStreaming(samples:sampleRate:languageCode:)`) paths. Audio is
converted to 16 kHz mono float PCM using `AVAudioConverter`
(`AudioSampleLoader.swift`).

## Consequences

- We maintain a CMake-built XCFramework in `vendor/parakeet.xcframework`. CI
  will need to build or cache it.
- We pin the `parakeet.cpp` v0.5.0 release and verify GGUF checksums before
  offering downloads.
- The `SpeechEngine` abstraction remains intact: new engines are just new
  conforming types.
- Cohere Transcribe is integrated via the `onnxruntime-swift-package-manager`
  package (product `onnxruntime`, Swift module `OnnxRuntimeBindings`). The
  encoder ONNX graph includes the mel frontend, so the Swift side only needs
  to normalize 16 kHz mono float PCM and feed it to the encoder. A greedy
  decoder with KV-cache update drives the `cohere-decoder.int8.onnx` model
  using the `tokens.txt` tokenizer.
- Model downloads now include four verified GGUF files from
  `mudler/parakeet-cpp-gguf` instead of CoreML packages.

## Verified artefacts

| Engine | Source repository | Download source | Filename | Size | SHA-256 |
|---|---|---|---|---:|:---|
| Parakeet TDT v2 | `nvidia/parakeet-tdt-0.6b-v2` | `mudler/parakeet-cpp-gguf` | `tdt-0.6b-v2-q8_0.gguf` | 903,835,936 B | `2027e2e1a4dc60ccdd8558f93b15e7c0db4ef8895b4e82e889f3a6275d8119c6` |
| Parakeet TDT v3 | `nvidia/parakeet-tdt-0.6b-v3` | `mudler/parakeet-cpp-gguf` | `tdt-0.6b-v3-q8_0.gguf` | 940,663,680 B | `4d69a4a6683f4f2d952bad794c1357ca6eb628027695b4699c5a9ad4cd07d757` |
| Parakeet Flash | `nvidia/parakeet_realtime_eou_120m-v1` | `mudler/parakeet-cpp-gguf` | `realtime_eou_120m-v1-q8_0.gguf` | 176,001,472 B | `62616b914d6f5a683a5dea672df055b57de5c49dddf871b8b44b9c814dc3d896` |
| Nemotron Speech 3.5 | `nvidia/nemotron-3.5-asr-streaming-0.6b` | `mudler/parakeet-cpp-gguf` | `nemotron-3.5-asr-streaming-0.6b-q8_0.gguf` | 983,696,512 B | `ba2f13eccd4a5245be728f77e6149bd6a4fdcdd133ff2e08ac6005bcef7a99f1` |
| Cohere Transcribe | `cstr/cohere-transcribe-onnx-int8` | `cstr/cohere-transcribe-onnx-int8` | `cohere-encoder.int8.onnx` | 6,164,263 B | `27ef3d3a2352c972fa4831ae680d52937a2d4e5d62910060f140b13e2f4ccd2b` |
| Cohere Transcribe | `cstr/cohere-transcribe-onnx-int8` | `cstr/cohere-transcribe-onnx-int8` | `cohere-encoder.int8.onnx.data` | 2,839,314,432 B | `0a6ebd1efbaeef6d15106e33671ce73067cad862bbb20f5e2dfbcd56695fbb76` |
| Cohere Transcribe | `cstr/cohere-transcribe-onnx-int8` | `cstr/cohere-transcribe-onnx-int8` | `cohere-decoder.int8.onnx` | 530,119 B | `4be3bdfe855b751985dd2b53d39cca66967bdcb656a138753daf12c451900358` |
| Cohere Transcribe | `cstr/cohere-transcribe-onnx-int8` | `cstr/cohere-transcribe-onnx-int8` | `cohere-decoder.int8.onnx.data` | 222,937,088 B | `8e4d5d7ea5092cf0779b711c65dfef9ecd2b88df951c6c7aa334df345c2eb4d8` |
| Cohere Transcribe | `cstr/cohere-transcribe-onnx-int8` | `cstr/cohere-transcribe-onnx-int8` | `tokens.txt` | 207,437 B | `013ede043ae2480e3a9205cc34550d9686100cc682bacc90f702facdfbb93035` |

## Related decisions

- ADR 0005 — Multi-Engine Speech Architecture
- ADR 0003 — Verified Model Catalogue and Local Verification
- `docs/LANGUAGE_MODEL_BENCHMARK_2026-08-06.md`
