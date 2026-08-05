
# ZenVoice vs FluidVoice Gap Analysis Report

## Executive Summary

FluidVoice is a mature, GPLv3 open-source macOS dictation app with 9.3k GitHub stars. It ships a wide model catalog, real-time live preview with notch support, command/rewrite modes, optional cloud AI providers, analytics, and automatic updates.

ZenVoice is currently a private-source macOS dictation app at v0.2.0 with strong privacy engineering (encrypted history, no accounts, no cloud). The user's goal is to pivot ZenVoice into a **fully free, open-source, developer-first** dictation product that competes with FluidVoice while keeping a stronger multilingual focus (not English-first).

This report highlights what ZenVoice is missing, where FluidVoice has weaknesses ZenVoice can exploit, and recommended feature priorities.

---

## 1. What ZenVoice Currently Has (Strengths)

- Native macOS menu-bar app with global hotkey and hold-to-dictate
- Encrypted local transcript history (AES-GCM + Keychain)
- Private local insights / stats
- Verified model catalog with SHA-256 validation
- Parakeet/CoreML + whisper.cpp runtimes
- 64 language profiles, Hinglish Latin/native/translation modes
- Deterministic Instant Refine (filler/repetition cleanup + meaning guard)
- Per-application language/refinement profiles
- Memory-only context box
- Recovery Inbox for failed/partial dictations
- First-run onboarding
- M9 security review + release-readiness framework
- No accounts, no analytics, no cloud transcription

---

## 2. Major Gaps vs FluidVoice

### 2.1 Model & Runtime Diversity

| Capability | FluidVoice | ZenVoice | ZenVoice Gap |
|---|---|---|---|
| Parakeet TDT v3 | Yes | Yes | — |
| Parakeet TDT v2 / Flash | Yes | Partial (Parakeet Unified English only) | Add Parakeet Flash/v2 specialized models |
| Nemotron Speech 3.5 (streaming + offline) | Yes | No | Add Nemotron for fast multilingual streaming |
| Cohere Transcribe | Yes | No | Add Cohere CoreML path for 14-language accuracy |
| Apple Speech (legacy + analyzer) | Yes | No | Add zero-download native macOS fallback |
| Whisper tiny/base/small/medium/large/turbo | Yes (transcribe.cpp GGUF) | Yes (whisper.cpp XCFramework) | Consider GGUF/quantized Whisper for smaller downloads |
| Qwen3 ASR | Hidden/beta | No | Optional future exploration |
| Streaming real-time preview | Yes, fast | Stable partial preview exists but not as polished | Improve streaming latency and UI |

### 2.2 User Interface / Experience

| Capability | FluidVoice | ZenVoice | Gap |
|---|---|---|---|
| Notch-aware live overlay | Yes | No (ZenBar is bottom-edge only) | Add notch/top overlay option |
| Configurable overlay sizes | Yes (pill/large) | No | Add size presets |
| Command Mode (agentic Mac control) | Yes | No | Add voice commands for system actions |
| Rewrite Mode (selected-text AI rewrite) | Yes | No | Add inline rewrite/improve mode |
| Real-time word appearance as you speak | Yes ("insanely fast Parakeet") | Partial | Optimize streaming pipeline |
| Today-usage stats toolbar pill | Yes | Yes (Insights exists) | Surface stats in ZenBar/menu bar |
| Meeting / file transcription | Yes | No | Add file/meeting transcription |
| Custom themes / light-dark compact switcher | Yes | In progress (uncommitted redesign) | Complete redesign, add theme toggle |

### 2.3 AI Enhancement Layer

| Capability | FluidVoice | ZenVoice | Gap |
|---|---|---|---|
| Local on-device enhancement model ("Fluid Intelligence") | Private/proprietary runtime | No | ZenVoice deliberately removed generative refinement; decide if a fully open local model is wanted |
| Cloud AI providers (OpenAI, Groq, custom) | Yes | No | Optional bring-your-own-key enhancement |
| Per-app prompt sets | Yes | Per-app profiles exist but simpler | Add prompt-based per-app routing |
| Smart formatting / context-aware capitalization | Yes (via Fluid Intelligence or cloud) | Instant Refine is deterministic | Add optional local or BYO-cloud enhancement |

### 2.4 Distribution & Open Source

| Capability | FluidVoice | ZenVoice | Gap |
|---|---|---|---|
| Open source license | GPLv3 | Proprietary source-visible | Must relicense to an OSI-approved license (e.g. MIT/Apache/GPLv3) |
| Homebrew cask | Yes | No | Add brew cask after public release |
| Auto-updater (AppUpdater) | Yes | No | Add Sparkle or AppUpdater |
| GitHub Sponsors / community | Yes | No | Build public repo, issues, Discord |
| Public release downloads | Yes | Private beta only | Complete notarization + clean-device QA |
| Analytics (opt-in) | PostHog, enabled by default | None | Decide whether anonymous opt-in analytics are acceptable |

### 2.5 Engineering / Code Quality

| Capability | FluidVoice | ZenVoice | Gap |
|---|---|---|---|
| Deterministic executable checks (core/storage/runtime) | Limited (xcodebuild tests only) | Yes (3 check executables) | ZenVoice is stronger here |
| Architecture | Single app target (~77k LOC) | Modular (ZenVoice/Storage/Core/Runtime) | ZenVoice is cleaner for contributors |
| Swift Package Manager only | Yes | Yes | Both good |
| Minimum macOS | 15.0 | 14.0 | ZenVoice supports older Macs |
| Model provenance / checksum manifest | Partial | Stronger (SHA-256 + pinned revisions) | ZenVoice is stronger |
| Security review doc | Not visible | M9 review exists | ZenVoice stronger |
| Encrypted transcript storage | Keychain for API keys only; history likely unencrypted | AES-GCM + Keychain | ZenVoice is far stronger on privacy |

---

## 3. FluidVoice Weaknesses ZenVoice Can Exploit

1. **Privacy posture is weaker**: FluidVoice collects opt-in analytics by default, has optional cloud AI providers, and its "Fluid Intelligence" local model is a closed/private runtime. ZenVoice can differentiate as **100% local, no telemetry, no cloud, no closed runtimes**.
2. **No encrypted transcript history**: FluidVoice stores transcription history; ZenVoice encrypts it at rest.
3. **Closed enhancement runtime**: "Fluid Intelligence" is privately maintained. ZenVoice can either skip generative enhancement or use fully open models.
4. **English-first marketing**: Parakeet Flash/TDT v2 and Nemotron are promoted for English/low-latency. ZenVoice can lead with **multilingual-first onboarding** and Hinglish/indic support.
5. **Single massive target**: ~77k LOC in one app target makes contributor onboarding harder. ZenVoice's modular targets are easier to extend.
6. **GPLv3 copyleft**: Some commercial/enterprise users avoid GPLv3. ZenVoice could choose MIT/Apache for broader adoption.
7. **Analytics default-on**: Privacy-conscious developers dislike opt-out analytics. ZenVoice can default-off or omit entirely.

---

## 4. Recommended ZenVoice Feature Roadmap (Free, Open Source)

### Phase 1: Open-source foundation (must do before competing)
- [ ] Pick open-source license (MIT/Apache recommended for developer adoption; GPLv3 if copyleft is intentional)
- [ ] Make GitHub repo public, add CONTRIBUTING.md, issue templates, CI
- [ ] Add README quick-start with Homebrew path (future)
- [ ] Remove proprietary license and closed branding decisions

### Phase 2: Catch up to core dictation parity
- [ ] Add Nemotron Speech 3.5 streaming/offline model path (fast multilingual)
- [ ] Add Cohere Transcribe CoreML path (high-accuracy 14-language)
- [ ] Add Apple Speech Analyzer fallback (zero-download, macOS 26+)
- [ ] Add Parakeet Flash/TDT v2 specialized English models
- [ ] Add real-time live preview notch/top overlay option
- [ ] Improve streaming transcription latency to match FluidVoice

### Phase 3: Differentiating features
- [ ] **Multilingual-first onboarding**: language selection before model selection
- [ ] **Hinglish + Indic-first improvements**: better transliteration, code-mixed handling
- [ ] **Encrypted local transcription history** (already done; market it)
- [ ] **Open local enhancement**: use fully open small LLM (e.g. Qwen2.5/Phi) for optional deterministic formatting, or skip enhancement entirely
- [ ] **Command mode**: simple deterministic voice commands (no LLM required)
- [ ] **Rewrite mode**: optional selected-text rewrite using local or BYO-cloud provider
- [ ] **Meeting/file transcription**: drag-and-drop audio/video transcription
- [ ] **Plugin/script extensibility**: let developers add custom post-processing scripts

### Phase 4: Distribution & community
- [ ] Notarized public beta/release
- [ ] Homebrew cask
- [ ] Auto-updater (Sparkle/AppUpdater)
- [ ] Public analytics opt-in (or none)
- [ ] Discord / GitHub Discussions

---

## 5. Model Strategy Recommendation

For a free multilingual-focused dictation app, prioritize:

1. **Nemotron Speech 3.5 Streaming** — fastest multilingual streaming, ~40 languages, ~670 MB
2. **Nemotron 3.5 Offline** — higher accuracy multilingual, ~530 MB
3. **Parakeet TDT v3** — fast European/multilingual, ~500 MB
4. **Cohere Transcribe** — high-accuracy 14-language, ~1.4 GB
5. **Whisper Small/Large Turbo** — broad 99-language fallback, GGUF for smaller size
6. **Apple Speech Analyzer** — zero-download native fallback for macOS 26+

Keep English models (Parakeet v2/Flash) available but not the default.

---

## 6. Risk Assessment

| Risk | Level | Mitigation |
|---|---|---|
| Relicensing ZenVoice from proprietary | Medium | Need author consent; replace LICENSE; check no third-party GPL contamination |
| FluidAudio dependency is closed-source / branch-based | Medium | FluidVoice uses branch-based FluidAudio; ZenVoice should pin exact revisions or use open alternatives |
| Model download bandwidth/cost | Medium | Use Hugging Face direct downloads; no central server |
| Maintaining multiple ASR backends | High | Start with 2–3 backends, add incrementally |
| GPLv3 if copying FluidVoice code | High | Do not copy FluidVoice code directly; design independently to avoid license contamination |
| macOS 14 vs 15 minimum | Low | Keep macOS 14 target for broader reach |

---

## 7. Conclusion

ZenVoice already has a stronger privacy and modular architecture foundation than FluidVoice. Its main gaps are:
- Open-source licensing and public community
- Model diversity (especially Nemotron, Cohere, Apple Speech)
- Real-time streaming UX and overlay design
- Command/rewrite/meeting modes
- Distribution channels (Homebrew, auto-updater)

The biggest competitive advantage ZenVoice can build is **"FluidVoice but fully open, privacy-first, and multilingual-first"**. If ZenVoice keeps every byte local by default, avoids closed runtimes, and leads with Hinglish/Indic/multilingual quality, it can carve out a distinct developer audience.
