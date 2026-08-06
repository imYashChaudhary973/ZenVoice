# ZenVoice Phased Development Plan

**Status:** Draft — 2026-08-06  
**Scope:** All new features and speech models requested for ZenVoice, organized into implementation phases.  
**Guiding principles:**

- Build for our own daily use first; public shipping remains deferred per [ADR 0004](decisions/0004-internal-use-first-defer-shipping.md).
- Local-first by default. Cloud AI is opt-in only and requires a separate privacy/security review.
- Everything is optional: every new feature ships off-by-default unless it is core to dictation.
- No telemetry, no accounts, no mandatory cloud services.

## Feature inventory

The list below combines the feature requests from 2026-08-06 with the current ZenVoice capabilities.

### Existing capabilities (keep, polish, extend)

| Feature | Current state |
|---|---|
| Global Hotkey | Implemented. Configurable dictation shortcut. |
| Smart Typing / Accessibility insertion | Implemented with clipboard fallback and secure-input handling. |
| Menu Bar Integration | Implemented with quick language switch and status. |
| Adaptive Theming | Implemented: system / light / dark. |
| Live Preview | Implemented inside ZenBar; needs dedicated overlay expansion. |
| Per-App Configuration | Application profiles exist for language, refinement, voice commands; needs prompt-set/engine expansion. |
| Local-First / Privacy | Core architecture. No cloud transcription or analytics. |
| Whisper speech models | Implemented via `whisper.cpp`. |

### New speech models to add

| Model | Best for | Languages | Size | Hardware | License |
|---|---|---|---|---|---|
| Apple Speech | Zero-download native macOS speech | System languages | Built-in | Apple Silicon + Intel | macOS system framework |
| Parakeet TDT v2 | Fast English-only dictation | English | ~500 MB | Apple Silicon | CC-BY-4.0 |
| Parakeet TDT v3 | Fast multilingual dictation | 25 languages | ~500 MB | Apple Silicon | CC-BY-4.0 |
| Parakeet Flash (Beta) | Lowest-latency live English | English | ~250 MB | Apple Silicon | CC-BY-4.0 family |
| Nemotron Speech 3.5 Ultra Fast | Streaming-capable multilingual | ~40 languages | ~670 MB | Apple Silicon | OpenMDW-1.1 |
| Nemotron 3.5 Multilingual | Higher-accuracy multilingual | ~40 languages | ~530 MB | Apple Silicon | OpenMDW-1.1 |
| Cohere Transcribe | High-accuracy multilingual | 14 languages | ~1.4 GB | Apple Silicon | Apache 2.0 |

### New features to build

| Feature | Description |
|---|---|
| **ZenIntelligence** | On-device AI enhancement for smart formatting, context-aware capitalization, and post-processing. |
| **Command Mode** | Control the Mac by voice: launch apps, run Shortcuts, trigger system actions, automate workflows. |
| **Write Mode** | Write or rewrite text directly in any text field. Replace selected text or dictate inline. |
| **Notch-Aware / Configurable Overlay** | Real-time transcription overlay with pill / large sizes and MacBook notch support. |
| **Audio History** | Optional local recording archive with budget controls and ZIP export. |
| **Today-Usage Stats** | Daily usage header card / toolbar pill. |
| **Auto-Updates** | Seamless updates with optional beta channel. |
| **AI Enhancement (cloud)** | Optional post-processing via OpenAI, Groq, or custom providers. Explicit opt-in only. |

## Phase summary

| Phase | Theme | Primary deliverables |
|---|---|---|
| **Phase 1** | Foundation | Multi-engine architecture; Apple Speech; model catalogue refresh; engine registry; command parsing scaffold. |
| **Phase 2** | Speed & language coverage | Parakeet TDT v2/v3/Flash; Nemotron Speech 3.5 variants; engine selection UI; per-app engine profiles; benchmarks. |
| **Phase 3** | Intelligence & control | ZenIntelligence on-device AI; Command Mode; Write Mode. |
| **Phase 4** | Experience polish | Notch-aware configurable overlay; Audio History; Today-Usage Stats. |
| **Phase 5** | Distribution & cloud opt-in | Auto-updates; optional cloud AI Enhancement; remaining release gates when shipping is reconsidered. |
| **Phase 6** | Product & interface | Remove borrowed UI; 19 → 9 navigation entries; new indigo/navy design system; finish cloud refinement; real-dictation evaluation corpus. |

## Phase selection rationale

- **Phase 1** unlocks every later engine feature. It is pure architecture and the lowest-risk new engine (Apple Speech).
- **Phase 2** delivers the core speed and language value of the model list before any AI/control features are layered on top.
- **Phase 3** is the largest user-facing capability jump. It depends on the transcription pipeline being stable across engines.
- **Phase 4** improves daily experience without changing the core speech path.
- **Phase 5** is intentionally last because it touches distribution, cloud services, and trust boundaries.

## Documentation

Each phase has its own detailed plan:

- [Phase 1 — Foundation](PHASE_1.md)
- [Phase 2 — Speed & Languages](PHASE_2.md)
- [Phase 3 — Intelligence & Control](PHASE_3.md)
- [Phase 4 — Experience](PHASE_4.md)
- [Phase 5 — Distribution & Cloud Opt-In](PHASE_5.md)
- [Phase 6 — Product & Interface](PHASE_6.md)

## Cross-cutting requirements

Every phase must:

1. Update the verified model catalogue, licence notices, and source provenance when new models or runtimes are introduced.
2. Add or extend a dedicated ADR before a cross-cutting architecture change lands.
3. Pass `swift build`, `ZenVoiceCoreChecks`, and `ZenVoiceStorageChecks`.
4. Add manual QA evidence for any user-facing behavior change.
5. Keep all new features opt-in unless they replace an existing default with clear UX consent.

## Deferral notes

- Auto-updates and cloud AI Enhancement are in Phase 5 because they require network, trust, and distribution decisions.
- Public shipping remains out of scope per [ADR 0004](decisions/0004-internal-use-first-defer-shipping.md); Phase 5 prepares the technical pieces without activating them.
