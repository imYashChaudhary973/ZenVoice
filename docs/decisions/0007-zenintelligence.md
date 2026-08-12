# ADR 0007 — ZenIntelligence (superseded)

## Status

Superseded by Phase 6 — merged into **Formatting** as the `Smart` rung.

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
2. The `Smart` rung currently runs deterministic cleanup plus formatting
   (capitalisation, number formatting, spacing, and a conservative context
   join). A local model can replace the formatter later without changing the
   API or the meaning-guard contract.
3. The meaning guard still rejects any candidate that adds, removes, or
   alters facts, names, numbers, dates, quantities, or negations.
4. `ZenIntelligenceMode` and `ZenIntelligencePreferences` remain internally
   for migration, but the UI no longer exposes the name.

## Consequences

- Users see one coherent control instead of two overlapping ladders.
- The `Smart` rung is reserved for a future local model; until then it is
  deterministic and stays on the Mac.
- The meaning guard continues to prevent hallucination or fact drift.
- Cloud formatting is a separate, explicit rung with its own provider and key.

## Privacy

- The `Smart` rung never sends transcript text off-device.
- Cloud formatting sends only the transcript and the user-supplied prompt to
  the provider chosen by the user, using the user's own API key.

## Related decisions

- ADR 0005 — Multi-Engine Speech Architecture
- `docs/PHASE_6.md`
