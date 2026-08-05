# Phase 1 — Foundation

**Goal:** Build the multi-engine speech architecture and add the safest new engine (Apple Speech), so every later phase has a stable platform to plug into.

**Outcome:** ZenVoice can select, load, and transcribe with more than one engine. Whisper remains the default; Apple Speech becomes an available zero-download option. The model catalogue can describe engines and their provenance, not just GGML files.

## Deliverables

1. ADR `0005-multi-engine-architecture.md`
2. `SpeechEngine` protocol and `EngineRegistry`
3. Refactor existing Whisper integration behind `SpeechEngine`
4. Apple Speech engine (`SFSpeechRecognizer` + `requiresOnDeviceRecognition`)
5. Verified model catalogue refresh: support engines, formats, and runtime families
6. Settings UI: engine selection per language profile
7. Command Mode scaffold: phrase matcher and action registry
8. Updated checks and manual QA

## Why start here

- Every other requested feature assumes a reliable transcription pipeline. Decoupling engines from the UI and recorder is the prerequisite.
- Apple Speech is the lowest-risk new engine: built into macOS, no new SwiftPM dependency, no model download.
- Building the registry first avoids a “Whisper-shaped hole” in the architecture when Parakeet/Nemotron arrive.

## Detailed tasks

### 1. Architecture decision record

- [ ] Write `docs/decisions/0005-multi-engine-architecture.md`.
- [ ] Define `SpeechEngine` protocol.
- [ ] Define `EngineDescriptor` (metadata: ID, display name, supported languages, format, runtime family, license, provenance).
- [ ] Define `EngineRegistry` and selection rules (language profile → preferred engine → fallback engine).
- [ ] Document fail-closed behavior: if an engine fails, fall back to the next engine in the user’s preference list, then to Whisper.

### 2. SpeechEngine protocol and registry

```swift
public protocol SpeechEngine: Sendable {
    var descriptor: EngineDescriptor { get }
    var isAvailable: Bool { get }

    /// Prepares any on-disk resources. Called once at selection or app launch.
    func prepare() async throws

    /// Transcribes the audio file at `url` for the given language profile.
    func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile
    ) async throws -> TranscriptionResult
}
```

- [ ] Create `Sources/ZenVoiceCore/SpeechEngine.swift`.
- [ ] Create `Sources/ZenVoiceCore/EngineRegistry.swift`.
- [ ] Add `SelectedEnginePreferences` for persisting the user’s engine choice per language capability.

### 3. Refactor Whisper behind the protocol

- [ ] Move `WhisperTranscriber` logic into a `WhisperSpeechEngine` conforming to `SpeechEngine`.
- [ ] Keep `WhisperTranscriber` as the low-level `whisper.cpp` wrapper.
- [ ] Update `AppDelegate` / dictation lifecycle to call the active engine instead of calling Whisper directly.
- [ ] Ensure model download, loading, and decoding still work exactly as before.

### 4. Apple Speech engine

- [ ] Create `Sources/ZenVoiceCore/AppleSpeechEngine.swift`.
- [ ] Use `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`.
- [ ] Check `supportsOnDeviceRecognition` for the requested locale; fail closed if unavailable.
- [ ] Convert the recorded 16 kHz mono WAV to the format `SFSpeechRecognizer` accepts.
- [ ] Return `TranscriptionResult` compatible with the rest of the pipeline.
- [ ] Add privacy note: audio never leaves the Mac when on-device mode is enforced.

### 5. Verified model catalogue refresh

- [ ] Extend `VerifiedModel` (or create `VerifiedEngine`) to describe:
  - engine family (`whisper`, `appleSpeech`, `parakeetTDT`, `parakeetFlash`, `nemotron`, `cohere`)
  - runtime identifier
  - download source / checksum / revision
  - license and attribution
- [ ] Add Apple Speech as an engine entry with no download.
- [ ] Add retired/reserved entries for Parakeet TDT v2/v3/Flash, Nemotron variants, and Cohere so later phases can fill them in without changing schema.
- [ ] Update `docs/MODEL_CATALOG.md` with engine table and license/provenance requirements.
- [ ] Update `THIRD_PARTY_NOTICES.md` if new runtime licenses are introduced (none for Apple Speech).

### 6. Engine selection UI

- [ ] Add an **Engine** section to the Models screen.
- [ ] Show available engines for the active language profile.
- [ ] Show availability reason if an engine is unavailable (e.g., Apple Speech on-device not supported for this locale).
- [ ] Default selection remains Whisper until another engine is proven in Phase 2.
- [ ] Persist selection per `LanguageProfile`.

### 7. Command Mode scaffold

- [ ] Create `Sources/ZenVoiceCore/CommandModeEngine.swift`.
- [ ] Define `CommandAction` enum: `.launchApp(bundleID:)`, `.runShortcut(name:)`, `.systemAction(_)`, `.appleScript(String)`, `.shellScript(String)`, `.none`.
- [ ] Implement deterministic phrase-to-action matching using a local command manifest.
- [ ] Add `CommandModePreferences` (enabled/disabled, command manifest storage).
- [ ] Do **not** yet wire to Shortcuts framework or `NSWorkspace`; this phase builds the parser and registry only.

### 8. Checks and QA

- [ ] Add `ZenVoiceCoreChecks` tests for:
  - Engine registry selection rules
  - Apple Speech availability mapping
  - Fallback ordering
- [ ] Ensure `swift build`, `ZenVoiceCoreChecks`, `ZenVoiceStorageChecks` pass.
- [ ] Manual QA:
  - Dictate with Whisper (unchanged behavior).
  - Select Apple Speech and dictate a short English phrase.
  - Verify on-device mode is active (no network indicator).
  - Verify fallback to Whisper when Apple Speech is unavailable.

## Dependencies

- No new SwiftPM dependencies in this phase.
- Requires `SFSpeechRecognizer` entitlement / permission handling; update Privacy docs.

## Out of scope for Phase 1

- Parakeet, Nemotron, Cohere model integrations (Phase 2).
- ZenIntelligence, Command Mode execution, Write Mode (Phase 3).
- Overlay redesign, Audio History, Today-Usage Stats (Phase 4).
- Cloud AI Enhancement, auto-updates (Phase 5).

## Success criteria

- `swift build` succeeds.
- `swift run ZenVoiceCoreChecks` passes, including new engine tests.
- Apple Speech can be selected and used for English dictation with on-device privacy enforced.
- Whisper remains fully functional as the default.
- Settings UI exposes engine selection without confusing the existing model download flow.
