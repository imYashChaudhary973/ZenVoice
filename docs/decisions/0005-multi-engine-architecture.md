# ADR 0005 — Multi-Engine Speech Architecture

## Status

Accepted. Implemented in Phase 1.

## Context

ZenVoice started with a single transcription path: whisper.cpp. That path is
mature, but it is no longer the only runtime the app wants to offer. The roadmap
now includes eight engines/models:

- Whisper (existing)
- Apple Speech (built-in, zero-download)
- Parakeet TDT v2 / v3 / Flash (NVIDIA, Core ML / ONNX)
- Nemotron Speech 3.5 Ultra Fast / Multilingual (NVIDIA)
- Cohere Transcribe

Each engine has a different runtime family, download policy, language set,
latency profile, and privacy posture. Plugging them in ad-hoc would scatter
engine-specific code through the dictation lifecycle and the settings UI. Phase
1 therefore introduces a small abstraction layer that lets the rest of the app
treat transcription as a service while each engine owns its own setup, decode,
and availability checks.

## Decision

1. A `SpeechEngine` protocol defines the contract every transcription runtime
   must satisfy.
2. An `EngineDescriptor` carries static metadata (identifier, display name,
   supported languages, runtime family, format, provenance, privacy notes).
3. An `EngineRegistry` lists every engine the app knows about and resolves
   which one to use for a given `LanguageProfile` and user preference.
4. User engine choice is stored per `LanguageProfile` in
   `SelectedEnginePreferences`.
5. Whisper remains the universal fallback. Apple Speech is added in Phase 1 as
   a zero-download, on-device option for supported locales.
6. Fail-closed: if the preferred engine is unavailable or fails, the registry
   falls back to the next preferred engine, ending at Whisper. If Whisper is
   missing, transcription cannot start.

## Consequences

- Adding Parakeet, Nemotron, or Cohere in later phases only requires a new
  `SpeechEngine` conforming type and an `EngineDescriptor`; the rest of the app
  does not change.
- The dictation lifecycle no longer depends on `WhisperTranscriber` directly.
- Settings can render engines generically from their descriptors while still
  showing engine-specific availability reasons.
- Engine selection must be validated against the active language profile, just
  as model selection is today.
- Runtime-only engines (Whisper, Apple Speech) live in `ZenVoiceRuntime`; the
  protocol and registry interfaces live in `ZenVoiceCore`.

## SpeechEngine protocol

```swift
public protocol SpeechEngine: Sendable {
    var descriptor: EngineDescriptor { get }
    var isAvailable: Bool { get }

    /// Prepare any on-disk resources. Called once at selection or app launch.
    func prepare() async throws

    /// Transcribe the audio file at `url` for the given language profile.
    func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile
    ) async throws -> TranscriptionResult
}
```

## EngineDescriptor

```swift
public struct EngineDescriptor: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let family: EngineFamily
    public let supportedLanguages: [SupportedLanguage]
    public let requiresDownload: Bool
    public let requiresInternet: Bool
    public let format: String
    public let publisher: String
    public let license: String
    public let attribution: String
}
```

## Engine selection rules

The registry resolves an engine in this order:

1. If the user has a saved preference for the active `LanguageProfile`, and
   that engine `isAvailable`, use it.
2. Otherwise, use the app default for that profile:
   - `.english` → Apple Speech if on-device recognition is available,
     otherwise Whisper.
   - `.hinglish` → Whisper (Apple Speech does not support Hinglish).
   - other profiles → Apple Speech if available, otherwise Whisper.
3. If the selected engine fails to load or transcribe, fall back to the next
   engine in the preference list (currently Whisper).
4. Whisper is the final fallback for every profile.

## Fail-closed behavior

- An engine whose `isAvailable` returns `false` is never selected silently;
   the UI shows the reason.
- A transcription failure is surfaced to the user; fallback is automatic only for
  retry paths such as history retry or future multi-engine experiments.
- In Phase 1 the live dictation path uses the selected engine only; automatic
  runtime fallback is added in Phase 2 with Parakeet/Nemotron.

## Privacy notes

- Apple Speech is configured with `requiresOnDeviceRecognition = true`. Audio
  never leaves the Mac for this engine.
- Whisper and Parakeet run entirely on-device using downloaded weights.
- Cohere Transcribe (Phase 5, optional) will require explicit opt-in and an API
  key; it is the only engine that sends audio off-device.

## Related decisions

- ADR 0004 — Internal-use-first, defer public shipping
- ADR 0003 — Verified model catalogue and local verification
