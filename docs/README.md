# ZenVoice documentation

The index below points to documents that describe ZenVoice as it is now.
Delivery plans for finished phases, superseded R&D, and retired benchmarks are
retained as historical evidence but are not current product guidance. Accepted
decisions and their rationale live in [`decisions/`](decisions/), and runtime
truth lives in the code and executable checks.

## The product

| Document | What it covers |
| --- | --- |
| [Architecture](ARCHITECTURE.md) | Targets, layering, memory, and how audio becomes inserted text. |
| [Design](DESIGN.md) | The visual system: tokens, components, window shell, menu bar. |
| [Privacy](PRIVACY.md) | What leaves this Mac, what never does, and where data is stored. |
| [Roadmap](ROADMAP.md) | Direction. Not a release promise. |

## Behaviour

| Document | What it covers |
| --- | --- |
| [Languages](LANGUAGES.md) | Language profiles and why English is the default. |
| [Model catalogue](MODEL_CATALOG.md) | Every model ZenVoice will download, with pinned revisions and hashes. |
| [Instant Refine](INSTANT_REFINE.md) | The local text stage between transcription and insertion. |
| [Live dictation](LIVE_DICTATION.md) | Stable-phrase preview and commit-on-pause. |
| [Transcription accuracy](TRANSCRIPTION_ACCURACY.md) | Where remaining errors come from, and what has been ruled out. |
| [Audio](AUDIO.md) | Microphone selection and the Audio Doctor. |
| [Voice profile](VOICE_PROFILE.md) | Local language summary and correction rules. |
| [Hinglish spelling](HINGLISH_SPELLING.md) | Romanized-Hindi spelling personalization. |
| [Sharing](SHARING.md) | Private highlight cards. |

## Working on ZenVoice

| Document | What it covers |
| --- | --- |
| [Development](DEVELOPMENT.md) | Prerequisites, build, run, check suites, and measuring memory. |
| [Accuracy harness](ACCURACY_HARNESS.md) | How to measure a change to the dictation path. |
| [PR and merge policy](PR_AND_MERGE_POLICY.md) | How changes get reviewed and landed. |
| [Build order](BUILD_ORDER.md) | Milestone ledger and verification gates. |
| [Phased plan](PHASED_PLAN.md) | Feature phases and their status. |
| [Phase 6](PHASE_6.md) | The phase currently in progress. |

## Shipping

| Document | What it covers |
| --- | --- |
| [Release readiness](RELEASE_READINESS.md) | Gates that must pass before any public distribution. |
| [Release QA record](RELEASE_QA_RECORD.md) | Template to copy per release candidate. |
| [Security review](SECURITY_REVIEW.md) | Engineering review of the release controls. |

## Measurements

| Document | What it covers |
| --- | --- |
| [Multi-engine benchmark, 2026-08-06](LANGUAGE_MODEL_BENCHMARK_2026-08-06.md) | The current comparison across local speech engines. |

## Decisions

[`decisions/`](decisions/) holds the architecture decision records, numbered in
the order they were accepted. An ADR states what was decided and why, and is
not rewritten when the code moves on — a superseding ADR is added instead.
