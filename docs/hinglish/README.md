# Hinglish Speech-to-Text: Research & Improvement Plan

> Historical R&D hub. This directory records the investigation that led to the
> current Hinglish implementation; it does not describe the current app state.
> ZenVoice now offers the verified Apex Hinglish specialist, enforces
> model/profile compatibility, and includes language and accuracy benchmarks.
> See [Verified Model Catalogue](../MODEL_CATALOG.md),
> [Language and Model Benchmark](../LANGUAGE_MODEL_BENCHMARK_2026-07-26.md), and
> [the July implementation update](05-update-2026-07.md).

The original investigation found that general multilingual Whisper followed by
mechanical Devanagari-to-Latin conversion could not produce natural Hinglish.
The documents below preserve that diagnosis, the alternatives considered, and
the measurements that led to adopting a Hinglish-native acoustic model.

## The one-paragraph version

At the time of the original diagnosis, ZenVoice's Hinglish profile ran Whisper
with `language=hi`, emitted Devanagari, then romanized it with ICU's `.toLatin`
transform. Two things broke.
Hindi orthography carries an implicit vowel that speakers do not pronounce, and
ICU spells it out, so `हाल` becomes `hala` instead of `haal`. Worse, an English
word spoken mid-sentence is written by Whisper in Devanagari and then romanized
back by a transform that has no idea it was ever English, so `computer` returns
as `kampyutara`. Every English word in a Hinglish sentence is destroyed this way.
On a sample of eight ordinary sentences, **8 out of 8** came back wrong. The
machine also had `whisper-medium-en`, an English-only checkpoint, selected
during that historical investigation. Neither condition is the current product
default.

## Documents

| Document | What it covers |
|---|---|
| [01-diagnosis.md](01-diagnosis.md) | What is broken, with measurements from this codebase |
| [02-research.md](02-research.md) | Literature and tooling survey, with sources |
| [03-plan.md](03-plan.md) | Phased implementation plan, effort and risk |
| [04-evaluation.md](04-evaluation.md) | How to measure Hinglish quality before changing anything |
| [05-update-2026-07.md](05-update-2026-07.md) | Apex implementation, measurements, and published state |

## Findings at a glance

| # | Historical finding | Current status | Evidence |
|---|---|---|---|
| 1 | Romanization cannot produce natural Hinglish by construction | Avoided by the Apex-native Hinglish path; still relevant to multilingual fallbacks | 8/8 historical sample sentences wrong ([01](01-diagnosis.md#f1)) |
| 2 | English loanwords destroyed by Devanagari round-trip | Avoided by Apex; fallback limitation remains documented | `computer → कंप्यूटर → kampyutara` ([01](01-diagnosis.md#f2)) |
| 3 | Active model was English-only | Fixed by atomic model/profile compatibility enforcement | [`VerifiedModelCatalog.swift`](../../Sources/ZenVoiceCore/VerifiedModelCatalog.swift) |
| 4 | Catalogue stopped at `medium` | Superseded by the measured five-model catalogue | [Current catalogue](../MODEL_CATALOG.md) |
| 5 | Greedy decoding only | Measured; beam search on Apex was rejected | [July update](05-update-2026-07.md#9-beam-search-on-apex--tested-rejected) |
| 6 | The former LLM refinement guard could not repair Hinglish | Closed; the entire Qwen/llama.cpp path was removed | [`TranscriptRefinement.swift`](../../Sources/ZenVoiceCore/TranscriptRefinement.swift) |
| 7 | No Hinglish evaluation harness | Fixed by `ZenVoiceLanguageBench` and accuracy checks | [Benchmark](../LANGUAGE_MODEL_BENCHMARK_2026-07-26.md) |
| 8 | `initial_prompt` unused for vocabulary | Fixed for Whisper paths; Parakeet has no decoder-prompt API | [Voice Profile](../VOICE_PROFILE.md) |

## Recommended direction

Adopt a **Hinglish-native acoustic model** that emits Latin script directly, and
delete the transliteration step rather than trying to improve it. Oriserve's
Apache-2.0 `Whisper-Hindi2Hinglish` family was built for exactly this and reports
roughly half the word error rate of Whisper large-v3 on Hindi benchmarks.

Before any of that, build the evaluation harness in
[04-evaluation.md](04-evaluation.md). Every claim in these documents about what
will help is a hypothesis until it is measured on real audio.

## Status

The original diagnosis, research, plan, and evaluation documents are historical.
Application code changed afterward: Apex, compatibility enforcement, vocabulary
prompting, and benchmark targets shipped as recorded in
[05-update-2026-07.md](05-update-2026-07.md). Broader real-speaker evidence and
real-microphone QA remain separate from those implementation results.
