# Phase 2 — Speed & Language Coverage

**Goal:** Add the remaining high-performance local speech engines so ZenVoice has fast, multilingual, and quality options beyond Whisper.

**Outcome:** Users can choose from Whisper, Apple Speech, Parakeet TDT v2/v3/Flash, Nemotron Speech 3.5 variants, and Cohere Transcribe. The app recommends engines per language profile and hardware, with verified provenance and benchmarks.

## Deliverables

1. [x] Parakeet TDT v2 local engine (English)
2. [x] Parakeet TDT v3 local engine (multilingual)
3. [x] Parakeet Flash local engine (experimental low-latency English)
4. [x] Nemotron Speech 3.5 Ultra Fast local engine
5. [x] Nemotron 3.5 Multilingual local engine
6. [x] Cohere Transcribe ONNX engine (encoder-decoder INT8, ONNX Runtime Swift)
7. [x] Verified model catalogue entries for all engines
8. [x] Hardware-aware recommendations and benchmark harness
9. [x] Per-app engine/language/refinement profiles
10. [x] Settings UI: engine recommendations, download, and removal

## Why this phase is second

- Phase 1 provides the `SpeechEngine` registry and Apple Speech proof of concept.
- These engines are the core value of the requested model list; they should be integrated before AI/control features depend on them.
- Provenance, licensing, and conversion validation are easier to manage in one focused phase.

## Detailed tasks

### 1. Provenance and licensing review

- [x] Record source repositories, pinned revisions, and checksums for each model:
  - Parakeet TDT v2: `nvidia/parakeet-tdt-0.6b-v2` (CC-BY-4.0)
  - Parakeet TDT v3: `nvidia/parakeet-tdt-0.6b-v3` (CC-BY-4.0)
  - Parakeet Flash: `nvidia/parakeet_realtime_eou_120m-v1` (CC-BY-4.0)
  - Nemotron Speech 3.5: `nvidia/nemotron-3.5-asr-streaming-0.6b` (OpenMDW-1.1)
  - Nemotron 3.5 Multilingual: same checkpoint, run in offline/whole-file mode (OpenMDW-1.1)
  - Cohere Transcribe: `cstr/cohere-transcribe-onnx-int8` export of `CohereLabs/cohere-transcribe-03-2026` (Apache 2.0)
- [x] Decide runtime path: `parakeet.cpp` v0.5.0 for Parakeet and Nemotron; ONNX Runtime Swift for Cohere.
- [x] Document the decision in `docs/decisions/0006-local-engine-runtime.md` and `docs/MODEL_CATALOG.md`.
- [x] Update `THIRD_PARTY_NOTICES.md` with MIT (parakeet.cpp runtime), OpenMDW-1.1, CC-BY-4.0, and Apache 2.0 entries.

### 2. Parakeet TDT v2/v3 engines

- [x] Create `Sources/ZenVoiceRuntime/ParakeetTDTv2Engine.swift` and `ParakeetTDTv3Engine.swift`.
- [x] Load the GGUF model from the Application Support `Models` directory via `ParakeetBridge`.
- [x] Implement whole-file transcription using `ParakeetContext.transcribe(url:languageCode:)`.
- [x] Map output to `TranscriptionResult` (text only; no segment timestamps yet).
- [x] v2: English-only.
- [x] v3: Multilingual (25 languages).

### 3. Parakeet Flash engine

- [x] Create `Sources/ZenVoiceRuntime/ParakeetFlashEngine.swift`.
- [x] Label as **Beta / Experimental** in the UI.
- [x] Use the streaming path for lowest-latency live English transcription.
- [x] Add a warning if accuracy is materially lower than TDT v2.

### 4. Nemotron Speech 3.5 engines

- [x] Create `Sources/ZenVoiceRuntime/NemotronSpeechEngine.swift`.
- [x] Support both Ultra Fast (streaming) and Multilingual (whole-file) variants via model ID.
- [x] Map 40 supported locales from BCP-47 codes to the exact locale strings expected by the model.
- [x] Verify parity against reference NeMo outputs through the multi-engine benchmark harness.

### 5. Cohere Transcribe ONNX engine

- [x] Adopt ONNX Runtime Swift package (`microsoft/onnxruntime-swift-package-manager`).
- [x] Create `Sources/ZenVoiceRuntime/CohereTranscribeEngine.swift` and `CohereTokenizer.swift`.
- [x] Download and verify ONNX encoder, decoder, and `tokens.txt` from `cstr/cohere-transcribe-onnx-int8`.
- [x] Offer as a **High Accuracy** option; warn about size (~3 GB total) and latency.
- [x] Feed raw 16 kHz mono float PCM to the encoder; the ONNX graph contains the mel frontend. Implement greedy decoding with KV-cache update on the Swift side.

### 6. Engine selection and recommendations

- [x] Update `EngineRecommendationEngine` to consider engine family, not just model size.
- [x] Add `EngineRecommendation` structure: preferred engine, fallback engine, rationale.
- [x] Recommend:
  - English fast default: **Parakeet TDT v3** (if installed) or **Parakeet TDT v2**
  - English low latency (experimental): **Parakeet Flash**
  - Multilingual fast default: **Parakeet TDT v3**
  - Multilingual quality default: **Nemotron 3.5 Multilingual**
  - Broad compatibility / Intel fallback: **Whisper**
  - Zero-download: **Apple Speech**
  - High-accuracy option: **Cohere Transcribe**
- [x] Allow user override; never force a recommendation.

### 7. Benchmark harness

- [x] Extend `Sources/ZenVoiceAccuracyChecks` to measure each engine:
  - Word error rate (WER) on a local evaluation corpus
  - End-to-end latency (time to first token, total decode time)
  - Peak memory
  - Disk size

  Infrastructure is in place (`measureEngines`). The harness now benchmarks
  Whisper, Apple Speech (when authorized), Parakeet TDT v2/v3, Parakeet Flash,
  Nemotron Speech 3.5 variants, and Cohere Transcribe as they are wired into
  `EngineRegistry`.
- [x] Record results in `docs/LANGUAGE_MODEL_BENCHMARK_2026-08-06.md`.
- [x] Use results to validate or adjust recommendations.

### 8. Per-app engine profiles

- [x] Extend `ApplicationProfile` with `preferredEngineID` and `preferredOutputMode`.
- [x] Add UI in `AppProfilesScreen` to choose engine and language per app.
- [x] Fall back to global preference when an app has no profile.

### 9. Settings UI updates

- [x] Models screen: group engines by language capability and tier.
- [x] Show download progress, installed size, and remove action for downloadable engines.
- [x] Show “no download needed” for Apple Speech.
- [x] Show “experimental” badge for Flash and Cohere until proven.

### 10. Verification

- [x] `swift build` succeeds with all new engines.
- [x] `ZenVoiceCoreChecks` includes engine availability and fallback tests.
- [x] Manual QA for each engine:
  - [x] English dictation via accuracy harness
  - [x] Multilingual dictation (where supported) in live UI (Parakeet TDT v3, Nemotron 3.5 Multilingual, Cohere)
  - [ ] Cancel and recovery audio handling
  - [ ] Live preview (if applicable)

## Dependencies

- Phase 1 must be complete.
- `parakeet.cpp` v0.5.0 vendored as `vendor/parakeet.xcframework`.
- ONNX Runtime Swift package for Cohere (`microsoft/onnxruntime-swift-package-manager`).
- Disk space for model downloads (up to ~1 GB per engine; ~3 GB total for Cohere, including external ONNX data files).

## Out of scope for Phase 2

- Cohere cloud API path (Phase 5).
- ZenIntelligence and AI post-processing (Phase 3).
- Command Mode execution beyond parser scaffold (Phase 3).
- Write Mode (Phase 3).
- Overlay redesign, Audio History, Today-Usage Stats (Phase 4).
- Cloud AI Enhancement and auto-updates (Phase 5).

## Success criteria

- [x] At least Parakeet TDT v2 and v3 are available and benchmarked.
- [x] Nemotron Speech 3.5 variants are available or documented why they are deferred.
- [x] Cohere Transcribe is integrated and available as a high-accuracy option.
- [x] Recommendations adapt by language profile and hardware.
- [x] Per-app engine selection works end-to-end.
- [x] No regression in Whisper default behavior.
