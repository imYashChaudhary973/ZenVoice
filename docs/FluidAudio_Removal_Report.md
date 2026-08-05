# ZenVoice FluidAudio Removal Report

**Date:** 2026-08-05
**Status:** Phase 1 completed
**Author:** ZenVoice engineering

---

## 1. Executive Summary

ZenVoice previously depended on the closed-source `FluidAudio` Swift package to
run the NVIDIA Parakeet Unified English CoreML model. Because FluidAudio is a
proprietary competitor dependency, and because ZenVoice is moving to a fully
open-source Apache-2.0 project, every FluidAudio reference has been removed.

The **Parakeet model weights themselves are not legally bound to FluidAudio**.
They are published by NVIDIA on Hugging Face under the NVIDIA Open Model License.
What *is* bound to FluidAudio is the **inference engine code** that knows how to
load and execute the converted CoreML `.mlmodelc` bundle.

This report documents:
- exactly which FluidAudio components ZenVoice was using,
- which files were changed or deleted,
- which models are now retired vs. reusable,
- and the legal boundary between FluidAudio code and NVIDIA/Parakeet weights.

---

## 2. What was FluidAudio providing?

FluidAudio was a Swift package hosted at
`https://github.com/FluidInference/FluidAudio.git`, pinned in ZenVoice's
`Package.swift` at revision `88d6d8166880dee1ac7c32c80f8e10cd782f8ca8`.

ZenVoice used exactly one product from that package:

| ZenVoice file | Imported symbol | Purpose |
|---|---|---|
| `Sources/ZenVoiceRuntime/ParakeetModelSupport.swift` | `FluidAudio.UnifiedAsrManager` | Load the Parakeet CoreML bundle and run inference on 16 kHz mono audio samples. |

`UnifiedAsrManager` is a closed-source class. It wrapped the following work:
- loading the Parakeet Unified EN CoreML `.mlmodelc` directory,
- running the encoder (INT8 FastConformer),
- running the decoder + joint-decision transducer loop,
- returning text and per-token timings.

ZenVoice did **not** use any other FluidAudio product (no text-normalization
runtime, no speaker diarization, no clustering wrapper) in its current code.
Those extra components were only noticed in `THIRD_PARTY_NOTICES.md` because
they were compiled into the `FluidAudio` binary and therefore redistributed with
ZenVoice.

---

## 3. What Parakeet / NVIDIA assets were involved?

| Asset | Source | License | Bound to FluidAudio? |
|---|---|---|---|
| `nvidia/parakeet-unified-en-0.6b` base weights | NVIDIA on Hugging Face | NVIDIA Open Model License | **No** |
| `FluidInference/parakeet-unified-en-0.6b-coreml` CoreML conversion | FluidInference on Hugging Face | Declared CC-BY-4.0, but artifact metadata says NVIDIA Open Model License | **No** (it is a model file; the license applies to the weights, not to FluidAudio code) |
| `FluidAudio.UnifiedAsrManager` runtime | `FluidInference/FluidAudio` | Closed-source / proprietary | **Yes** — this is the only thing ZenVoice could not legally redistribute |

The Parakeet model was offered in ZenVoice under the catalogue ID
`parakeet-unified-en-int8`. Its runtime metadata was `.parakeetCoreML`. The
model was a multi-file directory (`parakeet-unified-en-0.6b`) containing:

- `config.json`
- `metadata.json`
- `vocab.json`
- `parakeet_unified_decoder.mlmodelc`
- `parakeet_unified_encoder_int8.mlmodelc`
- `parakeet_unified_joint_decision_single_step.mlmodelc`

ZenVoice downloaded these files file-by-file from Hugging Face, verified them
against a pinned manifest, and then handed the local directory to
`UnifiedAsrManager.loadModels(from:)`.

---

## 4. Which files were changed or deleted, and why?

### 4.1 Deleted files

| File | Why deleted |
|---|---|
| `Sources/ZenVoiceRuntime/ParakeetModelSupport.swift` | Entire file was glue code to `FluidAudio.UnifiedAsrManager`. It contained no model weights and no independent inference logic. It could not exist without the FluidAudio import. |
| `Package.resolved` | SwiftPM regenerates this file. Deleting it forced a clean resolution that no longer includes FluidAudio. |

### 4.2 Modified files — code

| File | What changed |
|---|---|
| `Package.swift` | Removed the `FluidAudio` dependency and the `.product(name: "FluidAudio", package: "FluidAudio")` product from `ZenVoiceRuntime`. |
| `Sources/ZenVoiceRuntime/WhisperTranscriber.swift` | Removed the `parakeetEngine` property, the `transcribeWithParakeet` method, and all Parakeet warm-up branching. All transcription now goes through `whisper.cpp`. |
| `Sources/ZenVoiceCore/VerifiedModelCatalog.swift` | Removed `SpeechModelRuntime.parakeetCoreML`, `VerifiedModelFile`, bundle URL logic, manifest digest, and bundle verification. Moved `parakeet-unified-en-int8` from active `models` to `retiredModels`. |
| `Sources/ZenVoiceCore/ModelRecommendations.swift` | English recommendation on Apple Silicon changed from `parakeet-unified-en-int8` to `whisper-large-v3-turbo`. |
| `Sources/ZenVoice/ModelManagerViewModel.swift` | Removed the `downloadParakeet` and `downloadBundleFile` methods. All downloads are now single-file GGML downloads. |
| `Sources/ZenVoiceCoreChecks/main.swift` | Updated model counts, recommendation assertions, and removed bundle-verification tests. |

### 4.3 Modified files — license and documentation

| File | What changed |
|---|---|
| `LICENSE` | Replaced proprietary/source-visible license text with Apache License, Version 2.0. |
| All `Sources/**/*.swift` | Added Apache-2.0 license header (mechanical change). |
| `THIRD_PARTY_NOTICES.md` | Removed FluidAudio, fastcluster, VBx, and NemoTextProcessing notices. Kept `whisper.cpp`, OpenAI Whisper weights, and Hinglish Apex weights. Added a "Retired NVIDIA Parakeet" notice explaining the model is no longer used. |
| `README.md`, `docs/*.md`, `CHANGELOG.md` | Updated every reference that described Parakeet/FluidAudio as active. Replaced with `whisper.cpp`-only descriptions and Apache-2.0 project status. |

---

## 5. Why the Parakeet model was retired, not deleted

The `parakeet-unified-en-int8` entry was moved to `retiredModels` instead of
being removed entirely. This is a **user-safety** decision, not a legal one.

- ZenVoice stores the user's selected model by catalogue ID in `UserDefaults`.
- If a user had already downloaded and selected Parakeet, deleting the catalogue
  entry would make that installed model become "no model installed" on next
  launch.
- A retired entry stays resolvable, so the app can still display it, verify it,
  and offer to remove it — but it is no longer offered for new downloads.

---

## 6. Can ZenVoice use Parakeet models again in the future?

**Yes.** The model weights are not bound to FluidAudio. To re-offer Parakeet,
ZenVoice must provide its own open-source inference engine. Realistic paths:

| Path | Description | Complexity |
|---|---|---|
| A. Native CoreML loader | Write Swift code that loads the existing `.mlmodelc` encoder, decoder, and joint-decision models directly with `CoreML.MLModel` and implements the transducer beam loop. | High — the bundle has three interdependent models and a custom tokenizer. |
| B. NeMo / ONNX bridge | Convert or run the Parakeet checkpoint using NVIDIA NeMo or an ONNX runtime, invoked from Swift. | Medium-High — adds a runtime dependency and conversion step. |
| C. Whisper-only for now | Keep Parakeet retired and focus on better Whisper models (turbo, distillation, fine-tunes) that run on `whisper.cpp`. | Low — current path. |

None of these paths require FluidAudio's permission, because none of them use
FluidAudio's source code.

---

## 7. What models are legally reusable today?

| Model | Publisher | License | Reusable? |
|---|---|---|---|
| Whisper Tiny/Base/Small/Medium/Large/Turbo (GGML) | OpenAI weights, ggml-org conversion | MIT | **Yes** — already in use. |
| Whisper-Hindi2Hinglish-Apex (GGML) | Oriserve weights, ZenVoice conversion | Apache-2.0 | **Yes** — already in use. |
| Parakeet TDT / Unified / Realtime weights | NVIDIA | CC-BY-4.0 / NVIDIA Open Model License | **Yes** — weights can be downloaded and used with any engine. |
| Parakeet `.mlmodelc` conversion by FluidInference | FluidInference | CC-BY-4.0 declared | **Yes** as a model file, but ZenVoice has no open engine for it. |
| FluidAudio runtime code | FluidInference | Proprietary/closed-source | **No** — removed. |

---

## 8. Legal conclusion

ZenVoice's removal of FluidAudio was necessary because:

1. The `FluidAudio` Swift package is closed-source/proprietary.
2. An Apache-2.0 project cannot ship a binary dependency whose license does not
   permit redistribution under Apache-2.0 terms.
3. The only part of the Parakeet pipeline that had this problem was the
   **FluidAudio inference engine**, not the **NVIDIA model weights**.
4. The Parakeet model was therefore retired from active use until ZenVoice has
   its own open-source engine for it.

The NVIDIA Parakeet models remain available on Hugging Face and can be reused in
ZenVoice the moment the project builds or integrates a compatible open-source
runtime.

---

## 9. Verification

After removal, the project builds and all checks pass:

```text
swift build                         → Build complete
swift run ZenVoiceCoreChecks        → all checks passed
swift run ZenVoiceRuntimeChecks     → Whisper path passed
swift run ZenVoiceStorageChecks     → 17 checks passed
```

The only local speech runtime now embedded in ZenVoice is the
`whisper.cpp` v1.9.1 XCFramework, licensed under MIT.
