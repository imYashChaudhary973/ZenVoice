# ADR 0007 — ZenIntelligence (superseded)

## Status

Amended by Phase 2 — the `Smart` rung now uses Apple's on-device system
language model behind the existing meaning guard.

## Context

`TranscriptRefinement` already provided deterministic cleaning (`clean`) and
layout-aware formatting (`agentPrompt`) without any model. Human-annotated
evaluation showed those rules cut WER on disfluent speech from 23.2% to 7.2%,
and a downloadable language model added 0.0 on top. The model path was
therefore removed.

Phase 3 introduced `ZenIntelligence` as a richer, context-aware formatting
layer. The name implied an on-device model, but the first implementation was
a deterministic formatter plus a meaning guard. There was no model behind the
name.

## Decision (as implemented)

Keep the deterministic formatter and meaning guard as the public API, but
stop calling it artificial intelligence. In Phase 6 it becomes the **Smart**
rung of the single **Formatting** ladder:

1. `TranscriptFormattingMode`: `.off`, `.clean`, `.smart`, `.cloud`.
2. The `Smart` rung runs deterministic cleanup, then uses
   `SystemLanguageModel` for punctuation, capitalization, whitespace, and
   paragraph layout on macOS 26 or later. It uses greedy generation with no
   session history and never calls Private Cloud Compute.
3. Model output must preserve every lexical token in order and pass the
   protected quantity/negation guard. Any failure falls back to the existing
   deterministic formatter.
4. The meaning guard still rejects any candidate that adds, removes, or
   alters facts, names, numbers, dates, quantities, or negations.
5. `ZenIntelligenceMode` and `ZenIntelligencePreferences` remain internally
   for migration, but the UI no longer exposes the name.

## Consequences

- Users see one coherent control instead of two overlapping ladders.
- Supported Macs get model-backed local formatting without a separate download.
  Older, ineligible, disabled, or not-ready systems keep deterministic Smart.
- The meaning guard continues to prevent hallucination or fact drift.
- Cloud formatting is a separate, explicit rung with its own provider and key.

## Privacy

- The `Smart` rung never sends transcript text off-device.
- Cloud formatting sends only the transcript and the user-supplied prompt to
  the provider chosen by the user, using the user's own API key.
- Apple's system model is OS-managed; ZenVoice supplies no model URL or API key.
- `PrivateCloudComputeLanguageModel` is not constructed anywhere in this path.

## Related decisions

- ADR 0005 — Multi-Engine Speech Architecture
- `docs/PHASE_6.md`
