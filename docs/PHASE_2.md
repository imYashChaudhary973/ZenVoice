# Phase 2 — Speed & Language Coverage

**Goal:** Add the remaining high-performance local speech engines so ZenVoice has fast, multilingual, and quality options beyond Whisper.

**Outcome:** Users can choose from Whisper, Apple Speech, Parakeet TDT v2/v3/Flash, Nemotron Speech 3.5 variants, and Cohere Transcribe. The app recommends engines per language profile and hardware, with verified provenance and benchmarks.

## Deliverables

1. Parakeet TDT v2 CoreML engine (English)
2. Parakeet TDT v3 CoreML engine (multilingual)
3. Parakeet Flash CoreML engine (experimental low-latency English)
4. Nemotron Speech 3.5 Ultra Fast CoreML engine
5. Nemotron 3.5 Multilingual CoreML engine
6. Cohere Transcribe ONNX engine (optional, high-quality)
7. Verified model catalogue entries for all engines
8. Hardware-aware recommendations and benchmark harness
9. Per-app engine/language/refinement profiles
10. Settings UI: engine recommendations, download, and removal

## Why this phase is second

- Phase 1 provides the `SpeechEngine` registry and Apple Speech proof of concept.
- These engines are the core value of the requested model list; they should be integrated before AI/control features depend on them.
- Provenance, licensing, and conversion validation are easier to manage in one focused phase.

## Detailed tasks

### 1. Provenance and licensing review

- [ ] Record source repositories, pinned revisions, and checksums for each model:
  - Parakeet TDT v2: `nvidia/parakeet-tdt-0.6b-v2` (CC-BY-4.0)
  - Parakeet TDT v3: `nvidia/parakeet-tdt-0.6b-v3` (CC-BY-4.0)
  - Parakeet Flash: verify exact NVIDIA repository and license (CC-BY-4.0 family)
  - Nemotron Speech 3.5: `nvidia/nemotron-3.5-asr-streaming-0.6b` (OpenMDW-1.1)
  - Nemotron 3.5 Multilingual: `nvidia/nemotron-3.5-asr-multilingual-*` (OpenMDW-1.1)
  - Cohere Transcribe: `CohereLabs/cohere-transcribe-03-2026` (Apache 2.0)
- [ ] Decide whether to use community CoreML ports or build a reproducible conversion pipeline.
- [ ] Document the decision in the phase notes and `docs/MODEL_CATALOG.md`.
- [ ] Update `THIRD_PARTY_NOTICES.md` with OpenMDW-1.1, CC-BY-4.0, and Apache 2.0 entries as needed.

### 2. Parakeet TDT v2/v3 CoreML engines

- [ ] Create `Sources/ZenVoiceCore/ParakeetTDTCoreMLEngine.swift` parameterized by model ID.
- [ ] Load the CoreML model package from the Application Support `Models` directory.
- [ ] Implement streaming or file-based transcription as the conversion supports.
- [ ] Map Whisper-style `TranscriptionResult` output (segments, text, language).
- [ ] v2: English-only.
- [ ] v3: Multilingual (25 languages).

### 3. Parakeet Flash CoreML engine

- [ ] Create `Sources/ZenVoiceCore/ParakeetFlashCoreMLEngine.swift`.
- [ ] Label as **Beta / Experimental** in the UI.
- [ ] Optimize for lowest-latency English dictation.
- [ ] Add a warning if accuracy is materially lower than TDT v2.

### 4. Nemotron Speech 3.5 engines

- [ ] Create `Sources/ZenVoiceCore/NemotronSpeechEngine.swift`.
- [ ] Support both Ultra Fast and Multilingual variants via model ID.
- [ ] Verify CoreML conversion parity against reference NeMo outputs before offering as recommended.
- [ ] Handle ~40 supported languages.

### 5. Cohere Transcribe ONNX engine

- [ ] Evaluate ONNX Runtime Swift package or use an MLX-based runner.
- [ ] Create `Sources/ZenVoiceCore/CohereONNXEngine.swift`.
- [ ] Download and verify ONNX weights and external data files.
- [ ] Offer as a **High Accuracy** option; warn about size (~1.4 GB) and latency.
- [ ] If ONNX integration is too large or unstable, move this engine to Phase 5 and document the blocker.

### 6. Engine selection and recommendations

- [ ] Update `ModelRecommendations` to consider engine family, not just model size.
- [ ] Add `EngineRecommendation` structure: preferred engine, fallback engine, rationale.
- [ ] Recommend:
  - English fast default: **Parakeet TDT v2**
  - English low latency (experimental): **Parakeet Flash**
  - Multilingual fast default: **Parakeet TDT v3**
  - Multilingual quality default: **Nemotron 3.5 Multilingual**
  - Broad compatibility / Intel fallback: **Whisper**
  - Zero-download: **Apple Speech**
  - High-accuracy option: **Cohere Transcribe** (if ready)
- [ ] Allow user override; never force a recommendation.

### 7. Benchmark harness

- [ ] Extend `Sources/ZenVoiceAccuracyChecks` to measure each engine:
  - Word error rate (WER) on a local evaluation corpus
  - End-to-end latency (time to first token, total decode time)
  - Peak memory
  - Disk size
- [ ] Record results in `docs/LANGUAGE_MODEL_BENCHMARK_2026-*.md`.
- [ ] Use results to validate or adjust recommendations.

### 8. Per-app engine profiles

- [ ] Extend `ApplicationProfile` with `preferredEngineID` and `preferredOutputMode`.
- [ ] Add UI in `AppProfilesScreen` to choose engine and language per app.
- [ ] Fall back to global preference when an app has no profile.

### 9. Settings UI updates

- [ ] Models screen: group engines by language capability and tier.
- [ ] Show download progress, installed size, and remove action for downloadable engines.
- [ ] Show “no download needed” for Apple Speech.
- [ ] Show “experimental” badge for Flash and Cohere until proven.

### 10. Verification

- [ ] `swift build` succeeds with all new engines.
- [ ] `ZenVoiceCoreChecks` includes engine availability and fallback tests.
- [ ] Manual QA for each engine:
  - English dictation
  - Multilingual dictation (where supported)
  - Cancel and recovery audio handling
  - Live preview (if applicable)

## Dependencies

- Phase 1 must be complete.
- CoreML model conversion pipeline or trusted community ports.
- Optional: ONNX Runtime Swift package for Cohere.
- Disk space for model downloads (up to ~1.4 GB per engine).

## Out of scope for Phase 2

- ZenIntelligence and AI post-processing (Phase 3).
- Command Mode execution beyond parser scaffold (Phase 3).
- Write Mode (Phase 3).
- Overlay redesign, Audio History, Today-Usage Stats (Phase 4).
- Cloud AI Enhancement and auto-updates (Phase 5).

## Success criteria

- At least Parakeet TDT v2 and v3 are available and benchmarked.
- Nemotron Speech 3.5 variants are available or documented why they are deferred.
- Cohere is either integrated or moved to Phase 5 with a clear rationale.
- Recommendations adapt by language profile and hardware.
- Per-app engine selection works end-to-end.
- No regression in Whisper default behavior.
