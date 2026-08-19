# ZenVoice documentation

The index below points to documents that describe ZenVoice as it is now.
Delivery plans for finished phases and superseded R&D are removed rather than
archived: git history keeps them, and a document that no longer describes the
product is a liability in a directory people read for current guidance.
Accepted decisions and their rationale live in [`decisions/`](decisions/), and
runtime truth lives in the code and executable checks.

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
| [Real-speech corpus](REAL_SPEECH_CORPUS.md) | Public and consented evaluation corpora, licences, and baseline procedure. |
| [Consented dictation model cycle](CONSENTED_DICTATION_MODEL_CYCLE.md) | The training-and-promotion cycle for product-specific models, and its gates. |
| [Cloud providers](CLOUD_PROVIDERS.md) | Cloud refinement providers, wire shapes, and the privacy boundary. |
| [PR and merge policy](PR_AND_MERGE_POLICY.md) | How changes get reviewed and landed. |
| [Build order](BUILD_ORDER.md) | Milestone ledger and verification gates. |
| [UI redesign](REDESIGN.md) | Working plan for the dark-only redesign. |
| [Phased plan](PHASED_PLAN.md) | Feature phases and their status. |
| [Phase 6](PHASE_6.md) | The phase currently in progress. |
| [Engine gap analysis](FluidVoice_Gap_Analysis_Report.md) | Which engine wins each language, and the rules that keep the catalogue honest. |

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

## Agentic Command Mode

Command Mode v2 is **built** and ships off by default: a dictated multi-step
goal becomes a reviewable plan that runs only after the user approves those
exact steps ([ADR 0013](decisions/0013-agentic-command-mode.md)). Command Mode
v1 — built-in app launches and system actions — is documented by
[ADR 0008](decisions/0008-command-mode.md). These documents are the design of
record for the shipped implementation.

| Document | What it covers |
| --- | --- |
| [Agentic Command Mode](AGENTIC_COMMAND_MODE.md) | Master design for Command Mode v2: flow, components, trust model, sequencing. |
| [Agentic planner](AGENTIC_PLANNER.md) | Hybrid deterministic→local-LLM planner, JSON plan schema, validation. |
| [Agentic approval gate](AGENTIC_APPROVAL_GATE.md) | Risk classes, approval modes, decision records, UI contract. |
| [Agentic orchestrator](AGENTIC_ORCHESTRATOR.md) | Execution state machine, executors, failure and cancellation policy. |
| [Agentic status streaming](AGENTIC_STATUS_STREAMING.md) | Live-status event envelope for Mac HUD and the future iPhone consumer. |

## Decisions

[`decisions/`](decisions/) holds the architecture decision records, numbered in
the order they were accepted. An ADR states what was decided and why, and is
not rewritten when the code moves on — a superseding ADR is added instead.
