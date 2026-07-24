# Hinglish Speech-to-Text: Research & Improvement Plan

Hinglish dictation in ZenVoice produces output no Hindi-English speaker would
write. This is not a tuning problem. The current design converts Devanagari to
Latin with a mechanical Unicode transform, and that path cannot reach natural
Hinglish no matter how good the acoustic model becomes.

## The one-paragraph version

ZenVoice's Hinglish profile runs Whisper with `language=hi`, which emits
Devanagari, then romanizes it with ICU's `.toLatin` transform. Two things break.
Hindi orthography carries an implicit vowel that speakers do not pronounce, and
ICU spells it out, so `हाल` becomes `hala` instead of `haal`. Worse, an English
word spoken mid-sentence is written by Whisper in Devanagari and then romanized
back by a transform that has no idea it was ever English, so `computer` returns
as `kampyutara`. Every English word in a Hinglish sentence is destroyed this way.
On a sample of eight ordinary sentences, **8 out of 8** came back wrong.

Separately, the model currently selected on this machine is `whisper-medium-en`,
an English-only checkpoint that cannot emit Devanagari at all.

## Documents

| Document | What it covers |
|---|---|
| [01-diagnosis.md](01-diagnosis.md) | What is broken, with measurements from this codebase |
| [02-research.md](02-research.md) | Literature and tooling survey, with sources |
| [03-plan.md](03-plan.md) | Phased implementation plan, effort and risk |
| [04-evaluation.md](04-evaluation.md) | How to measure Hinglish quality before changing anything |

## Findings at a glance

| # | Finding | Severity | Evidence |
|---|---|---|---|
| 1 | Romanization cannot produce natural Hinglish by construction | **Critical** | 8/8 sample sentences wrong ([01](01-diagnosis.md#f1)) |
| 2 | English loanwords destroyed by Devanagari round-trip | **Critical** | `computer → कंप्यूटर → kampyutara` ([01](01-diagnosis.md#f2)) |
| 3 | Active model is English-only, cannot transcribe Hindi | **Critical** | `selectedModelID = whisper-medium-en` ([01](01-diagnosis.md#f3)) |
| 4 | Model catalog stops at `medium`; no `large-v3` | High | [`VerifiedModelCatalog.swift`](../../Sources/ZenVoiceCore/VerifiedModelCatalog.swift) ([01](01-diagnosis.md#f4)) |
| 5 | Greedy decoding only; no beam search or temperature fallback | High | [`WhisperTranscriber.swift`](../../Sources/ZenVoiceRuntime/WhisperTranscriber.swift) ([01](01-diagnosis.md#f5)) |
| 6 | LLM refinement guard forbids word changes, so it cannot repair Hinglish | High | [`VerifiedRefinementModelCatalog.swift`](../../Sources/ZenVoiceCore/VerifiedRefinementModelCatalog.swift) ([01](01-diagnosis.md#f6)) |
| 7 | No Hinglish evaluation harness | High | No benchmark exists ([01](01-diagnosis.md#f7)) |
| 8 | `initial_prompt` unused for script/style priming | Medium | ([01](01-diagnosis.md#f8)) |

## Recommended direction

Adopt a **Hinglish-native acoustic model** that emits Latin script directly, and
delete the transliteration step rather than trying to improve it. Oriserve's
Apache-2.0 `Whisper-Hindi2Hinglish` family was built for exactly this and reports
roughly half the word error rate of Whisper large-v3 on Hindi benchmarks.

Before any of that, build the evaluation harness in
[04-evaluation.md](04-evaluation.md). Every claim in these documents about what
will help is a hypothesis until it is measured on real audio.

## Status

Research and planning only. **No application code has been changed.** The
measurements in [01-diagnosis.md](01-diagnosis.md) came from standalone scripts
that reproduce ZenVoice's logic, not from modifying the app.
