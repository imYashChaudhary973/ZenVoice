
# ZenVoice Open-Source Counter-Strategy Plan

## Document Purpose

This plan turns the FluidVoice gap analysis into an actionable roadmap for building **ZenVoice** as a fully free, open-source, privacy-first, multilingual-first dictation app for macOS. It covers brand positioning, legal/authorship cleanup, model integration, feature implementation, and a phased delivery schedule. The work will be done with **fully independent code** — no copying from FluidVoice.

---

## 1. Brand Foundation

### 1.1 Brand Positioning

| Element | Decision |
|---|---|
| **Name** | ZenVoice (keep existing name; reframe around calm, focused, local-first voice) |
| **Tagline** | "Speak freely. Stay private." |
| **Positioning** | The open-source, privacy-first, multilingual-first dictation app for developers and power users. |
| **Differentiator vs FluidVoice** | 100% local by default, no telemetry, no closed runtimes, multilingual-first, fully open source. |
| **Target audience** | Developers, writers, multilingual professionals, privacy-conscious Mac users. |
| **Personality** | Calm, precise, respectful, transparent, developer-friendly. |
| **Voice** | Clear, concise, no hype, no dark patterns, honest about limitations. |

### 1.2 Brand Promise

1. **Privacy by design**: your voice, transcripts, and models stay on your Mac unless you explicitly choose otherwise.
2. **Open by default**: source code, model provenance, and build pipeline are public and auditable.
3. **Multilingual-first**: we optimize for non-English languages and code-mixed speech from day one.
4. **Developer-friendly**: modular code, documented architecture, welcoming contributions.
5. **Forever free**: no subscriptions, no pricing tiers, no feature gates.

### 1.3 Visual Identity Direction

| Element | Direction |
|---|---|
| Primary color | Calm electric blue (#3B82F6) — action and live state |
| Secondary color | Warm graphite neutrals — surfaces and text |
| Accent | Success green (#22C55E), warning amber, danger red |
| Typography | System fonts (SF Pro / Inter) for native feel |
| Logo | Refined Zen mark; keep circular/wave motif; add "open" feel |
| UI theme | Clean devtool aesthetic (Graphite v4 redesign already in progress) |

### 1.4 Domain / Repo / Community

- Public GitHub repository: `github.com/imYashChaudhary973/ZenVoice`
- Website: simple landing page + docs (reuse existing `ZenVoice-Website` project or rebuild)
- Community: GitHub Discussions first; Discord later if demand grows
- Distribution: GitHub Releases + Homebrew cask

---

## 2. Legal & Authorship Plan

### 2.1 Author Consent & License Selection

| Step | Action | Owner |
|---|---|---|
| 1 | Confirm sole author / copyright holder of all ZenVoice source code | You |
| 2 | Audit third-party dependencies for license compatibility | Legal/Engineering |
| 3 | Choose open-source license (recommendation: **MIT** or **Apache-2.0** for broad adoption; **GPLv3** only if copyleft is intentional) | You |
| 4 | Replace `LICENSE` file and update `README.md`, `Package.swift`, headers | Engineering |
| 5 | Add `CONTRIBUTING.md` with CLA or DCO (Developer Certificate of Origin) | Engineering |
| 6 | Add `CODE_OF_CONDUCT.md` | Community |
| 7 | Re-sign all commits if necessary; ensure clean provenance | Engineering |

### 2.2 License Comparison

| License | Pros | Cons | Recommendation |
|---|---|---|---|
| MIT | Very permissive, commercial-friendly, easy to understand | No patent grant, no copyleft | **Strong candidate** |
| Apache-2.0 | Patent grant, permissive, corporate-friendly | Slightly longer license | **Strong candidate** |
| GPLv3 | Strong copyleft, protects openness | Deters some commercial users, incompatible with some App Store models | Use only if intentional |

**Recommendation:** Use **Apache-2.0** for ZenVoice. It gives patent protection, is corporate-friendly, and still requires attribution. It avoids the GPLv3 "viral" concerns while keeping the project truly open.

### 2.3 Avoiding License Contamination from FluidVoice

- Do **not** copy FluidVoice source code into ZenVoice.
- Do **not** run FluidVoice code through AI to generate ZenVoice code.
- Use FluidVoice only as a **functional reference** (what features exist, what models are used, how the UI behaves).
- Document design decisions in `docs/decisions/` with original rationale.
- For model integration, read public model cards and Hugging Face documentation, not FluidVoice's wrapper code.

---

## 3. Model Integration Plan

ZenVoice will support the same model categories as FluidVoice, but with a multilingual-first default.

### 3.1 Target Model Catalog

| Model | FluidVoice Name | ZenVoice Catalog ID | Runtime | Languages | Size | Priority |
|---|---|---|---|---|---|---|
| Parakeet TDT v3 | parakeet-tdt | `parakeet-tdt-v3` | CoreML / FluidAudio | 25 European + RU/UK | ~460 MB | P1 |
| Parakeet TDT v2 | parakeet-tdt-v2 | `parakeet-tdt-v2` | CoreML / FluidAudio | English | ~440 MB | P2 |
| Parakeet Flash | parakeet-realtime | `parakeet-flash` | CoreML / FluidAudio | English (streaming) | ~430 MB | P2 |
| Nemotron 3.5 Multilingual | nemotron-3.5-offline | `nemotron-3.5-offline` | CoreML | ~40 languages | ~530 MB | **P1** |
| Nemotron Speech 3.5 | nemotron-3.5-streaming | `nemotron-3.5-streaming` | CoreML | ~40 languages | ~670 MB | **P1** |
| Cohere Transcribe | cohere-transcribe-6bit | `cohere-transcribe` | CoreML | 14 languages | ~1.5 GB | P2 |
| Apple Speech (legacy) | apple-speech | `apple-speech-legacy` | SFSpeechRecognizer | System languages | Built-in | P2 |
| Apple Speech Analyzer | apple-speech-analyzer | `apple-speech-analyzer` | SF Speech Analytics | EN, ES, FR, DE, IT, JA, KO, PT, ZH | Built-in | P3 (macOS 26+) |
| Whisper Tiny | whisper-tiny | `whisper-tiny` | whisper.cpp | 99 languages | ~44 MB | P1 (fallback) |
| Whisper Base | whisper-base | `whisper-base` | whisper.cpp | 99 languages | ~81 MB | P1 |
| Whisper Small | whisper-small | `whisper-small` | whisper.cpp | 99 languages | ~257 MB | P2 |
| Whisper Medium | whisper-medium | `whisper-medium` | whisper.cpp | 99 languages | ~793 MB | P3 |
| Whisper Large Turbo | whisper-large-turbo | `whisper-large-turbo` | whisper.cpp | 99 languages | ~845 MB | P3 |
| Whisper Large | whisper-large | `whisper-large` | whisper.cpp | 99 languages | ~1.5 GB | P3 |

### 3.2 Integration Architecture

ZenVoice already has a clean `TranscriptionProvider` abstraction in `ZenVoiceRuntime`. Extend it:

```text
ZenVoiceRuntime/
├── TranscriptionProvider.swift        (existing protocol)
├── WhisperTranscriber.swift           (existing)
├── ParakeetTranscriberEngine.swift    (existing)
├── NemotronTranscriberEngine.swift    (new)
├── CohereTranscriberEngine.swift      (new)
├── AppleSpeechTranscriber.swift       (new)
└── ModelDownloadManager.swift         (extend existing)
```

### 3.3 Model Download & Verification

Reuse ZenVoice's existing `VerifiedModelCatalog` pattern:

1. Each model entry records: publisher, source URL, revision/branch, SHA-256, expected size, format, languages, license.
2. Downloads are HTTPS-only from pinned Hugging Face URLs.
3. Atomic install: download to staging directory, verify checksum, swap atomically.
4. Cancellation isolated from new downloads.
5. License notice carried in `THIRD_PARTY_NOTICES.md`.

### 3.4 Per-Model Implementation Notes

#### Parakeet TDT v3 / v2 / Flash
- Reuse existing `FluidAudio` dependency (already pinned in Package.swift).
- Add `AsrModelVersion` mapping: v3, v2, realtime.
- Verify model download URLs from Hugging Face (`nvidia/parakeet-tdt-1.1b-v3`, etc.).
- Record exact model files, sizes, and SHA-256.

#### Nemotron Speech 3.5
- Add dependency on CoreML-compatible Nemotron artifacts.
- Reference model: `BarathwajAnandan/nemotron-3.5-asr-streaming320-int8-CoreML` and offline variant.
- Implement streaming buffer management with bounded sample windows.
- Handle compute-unit fallback (ANE → GPU → CPU).

#### Cohere Transcribe
- Use FluidAudio branch or direct CoreML model loading.
- Reference model: Cohere ASR CoreML conversion on Hugging Face.
- Map 14 language tokens explicitly.

#### Apple Speech
- Wrap `SFSpeechRecognizer` for legacy path.
- Wrap `SFSpeechAnalytics` (macOS 26+) for analyzer path.
- Requires user permission; no model download.

#### Whisper
- Already integrated via `whisper.cpp` XCFramework.
- Add GGUF support optionally for smaller quantized downloads.
- Keep existing SHA-256 verification.

---

## 4. Feature Counter-Plan

### 4.1 Features to Match / Exceed FluidVoice

| FluidVoice Feature | ZenVoice Independent Implementation | Notes |
|---|---|---|
| Real-time live preview | Add top/notch overlay option alongside ZenBar; improve streaming latency | Use own overlay manager |
| Notch-aware overlay | Implement `NotchOverlayController` with dynamic notch detection | Independent design |
| Command Mode | Add deterministic local command engine + optional script extensibility | Avoid FluidVoice's LLM agent approach |
| Write/Rewrite Mode | Add selected-text capture + local deterministic rewrite | Optional BYO-cloud provider later |
| Audio history | Already exists (encrypted); add optional WAV export | Extend existing storage |
| Today-usage stats | Surface in ZenBar and menu bar; keep content-free | Use existing insights |
| Per-app configuration | Already exists; add prompt/script routing | Extend `ApplicationProfilePreferences` |
| Auto-updates | Add Sparkle or AppUpdater integration | P3 |
| Homebrew cask | Add after first public release | P3 |
| Custom dictionary / word boost | Already exists (correction rules); add pronunciation dictionary UI | Extend voice profile |
| Meeting/file transcription | Add drag-and-drop file transcription service | New feature |
| Multiple overlay sizes | Configurable ZenBar heights + notch sizes | UI work |
| Adaptive theming | Complete v4 Graphite redesign; add light/dark toggle | In progress |

### 4.2 ZenVoice-Only Differentiators

| Feature | Description |
|---|---|
| **Encrypted everything** | AES-GCM encrypted transcripts, correction rules, and recovery audio |
| **No telemetry by default** | Opt-in analytics only; no cloud unless user adds keys |
| **Multilingual-first onboarding** | Language selected before model; non-English defaults |
| **Hinglish/Indic-first** | Latin-script Hinglish, native-script output, English translation |
| **Developer extensibility** | Custom post-processing scripts, open model catalog, plugin API |
| **Meaning guard** | Deterministic refinement that never changes meaning |
| **Open build pipeline** | CI builds, signed releases, reproducible checksums |

---

## 5. Technical Foundation Improvements

### 5.1 Architecture Cleanups

- Convert uncommitted v4 Graphite redesign into clean, committed design system.
- Add a true `TranscriptionProvider` protocol and registry.
- Split `ZenVoiceStorage` further if needed (history vs. settings vs. model cache metadata).
- Add a model-download coordinator separate from UI.

### 5.2 CI / Release Pipeline

| Item | Action |
|---|---|
| GitHub Actions CI | Build, run core/storage/runtime checks, package app |
| Deterministic checks | Expand to cover new providers (Nemotron, Cohere, Apple Speech) |
| Model download tests | Weekly scheduled real-speech gate |
| Release readiness gate | Keep existing `check-release-readiness.sh` |
| Public signing | Use GitHub-hosted Developer ID + notarization secrets (protected env) |
| Homebrew formula | Create `homebrew-tap` repo |

### 5.3 Documentation

- Rewrite README for open-source contributors.
- Add `docs/MODEL_CATALOG.md` for every new model.
- Add `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md` updates.
- Add `docs/PRIVACY.md` reaffirming no telemetry.

---

## 6. Phased Execution Roadmap

### Phase 1 — Open Source Foundation (Weeks 1–4)

**Goal:** Make ZenVoice public, trustworthy, and contributor-ready. Ship the first open-source release with parity on core dictation.

| # | Work Item | Effort | Deliverable |
|---|---|---|---|
| 1.1 | Finalize license (Apache-2.0 recommended) and author consent | 1 day | Updated `LICENSE` |
| 1.2 | Audit/replace proprietary branding and closed-source decisions | 2 days | Clean repo, public README |
| 1.3 | Commit or revert v4 Graphite redesign; finalize design tokens | 3 days | Merged design system |
| 1.4 | Add `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, issue/PR templates | 2 days | Community docs |
| 1.5 | Set up public GitHub repo and CI | 2 days | Public repo + Actions |
| 1.6 | Expand model catalog: Parakeet TDT v3 + Whisper Base/Small | 1 week | Verified catalog entries |
| 1.7 | Multilingual-first onboarding refactor | 4 days | New onboarding flow |
| 1.8 | Release v0.3.0 open-source alpha | 2 days | GitHub Release + notarized build |

**Phase 1 total effort:** ~4 weeks (1 person full-time)

---

### Phase 2 — Multilingual Powerhouse (Weeks 5–10)

**Goal:** Match FluidVoice's model diversity and become the best multilingual dictation app. Add Nemotron, Cohere, Apple Speech, and real-time streaming UX.

| # | Work Item | Effort | Deliverable |
|---|---|---|---|
| 2.1 | Integrate Nemotron 3.5 Offline + Streaming | 2 weeks | Nemotron transcription provider |
| 2.2 | Integrate Parakeet TDT v2 + Flash (English fast paths) | 1 week | Parakeet v2/Flash provider |
| 2.3 | Integrate Cohere Transcribe | 1 week | Cohere provider |
| 2.4 | Integrate Apple Speech legacy + analyzer fallback | 1 week | Apple provider |
| 2.5 | Real-time live preview + top overlay / notch support | 2 weeks | New overlay system |
| 2.6 | Hinglish/Indic quality improvements and benchmarks | 1 week | Benchmark report |
| 2.7 | Audio history export + meeting/file transcription MVP | 1 week | File transcription view |
| 2.8 | Release v0.4.0 | 3 days | GitHub Release |

**Phase 2 total effort:** ~6 weeks (1 person full-time)

---

### Phase 3 — Distribution & Advanced Features (Weeks 11–16)

**Goal:** Ship a polished, competitive product with distribution channels and advanced modes.

| # | Work Item | Effort | Deliverable |
|---|---|---|---|
| 3.1 | Command Mode (deterministic local commands + script plugins) | 2 weeks | Command mode |
| 3.2 | Rewrite/Write Mode (selected-text rewrite) | 2 weeks | Rewrite mode |
| 3.3 | Optional local enhancement model (open Qwen/Phi) or BYO-cloud provider | 2 weeks | Enhancement settings |
| 3.4 | Auto-updater (Sparkle or AppUpdater) | 1 week | Auto-update |
| 3.5 | Homebrew cask + website landing page | 1 week | `brew install --cask zenvoice` |
| 3.6 | Custom dictionary / pronunciation dictionary UI | 1 week | Dictionary view |
| 3.7 | Full accessibility audit, clean-device QA, notarized stable release | 2 weeks | v1.0.0 release |
| 3.8 | Community: Discord/Discussions, contributor onboarding | ongoing | Active community |

**Phase 3 total effort:** ~6 weeks + ongoing community work

---

## 7. Effort Summary

| Phase | Duration | Focus | Approx. Person-Weeks |
|---|---|---|---|
| Phase 1 | Weeks 1–4 | Open-source foundation, core parity | 4 |
| Phase 2 | Weeks 5–10 | Multilingual models, streaming UX | 6 |
| Phase 3 | Weeks 11–16 | Distribution, command/rewrite, stable v1.0 | 6 |
| **Total to v1.0** | **~16 weeks** | | **16** |

With 2 engineers, this can compress to ~8–10 weeks. With part-time work, expect 6–9 months.

---

## 8. Risk Register & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Relicensing from proprietary | Medium | Confirm sole authorship; replace LICENSE; check dependency compatibility |
| FluidAudio closed-source dependency | Medium | Pin exact revisions; document license; prepare fallback to whisper.cpp |
| Nemotron/Cohere model availability | Medium | Verify Hugging Face repositories before committing; keep Whisper fallback |
| macOS version fragmentation | Low | Keep macOS 14 minimum; gate newer APIs behind availability checks |
| Contributor licensing | Low | Use DCO in CONTRIBUTING.md; no CLA complexity needed |
| GPLv3 contamination from reading FluidVoice | High | Treat FluidVoice as functional reference only; write independent code |
| Build/signing complexity | Medium | Use existing scripts; protect secrets in GitHub Actions |

---

## 9. Success Metrics

| Metric | Target |
|---|---|
| GitHub stars (6 months) | 1,000+ |
| Supported languages at v1.0 | 40+ with first-class UX |
| Dictation latency (Nemotron streaming) | ≤ 300 ms word appearance |
| Release cycle | Monthly alpha/beta, quarterly stable |
| Homebrew installs (6 months) | 500+ |
| Zero telemetry complaints | 100% opt-in or none |

---

## 10. Immediate Next Actions (This Week)

1. **Decide license**: confirm Apache-2.0 vs MIT vs GPLv3.
2. **Confirm sole authorship**: review all commits and third-party code in ZenVoice.
3. **Clean uncommitted redesign**: commit or revert the v4 Graphite changes.
4. **Make repo public** after license change.
5. **Start Phase 1.6**: expand `VerifiedModelCatalog` with Parakeet TDT v3 + Whisper Small.
6. **Schedule model research**: identify exact Hugging Face URLs for Nemotron, Cohere, and Parakeet v2/Flash.

---

## Conclusion

ZenVoice can become a credible open-source alternative to FluidVoice by leaning into its existing strengths (privacy, modularity, encrypted history) and aggressively closing the model-diversity and UX gaps. The plan is ambitious but feasible in ~16 weeks of focused work, starting with legal/open-source cleanup and ending with a stable v1.0 release.
