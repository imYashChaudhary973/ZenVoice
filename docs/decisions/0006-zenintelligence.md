# ADR 0006 — ZenIntelligence: On-Device AI Enhancement

## Status

Accepted — Phase 3 implemented.

## Context

`TranscriptRefinement` already provides deterministic cleaning (`clean`) and
layout-aware formatting (`agentPrompt`) without any model. Human-annotated
evaluation showed those rules cut WER on disfluent speech from 23.2% to 7.2%,
and a downloadable language model added 0.0 on top. The model path was
therefore removed.

Phase 3 wants a richer, context-aware formatting layer: smart capitalization,
number/date normalization, and lightweight sentence restructuring, while still
keeping all processing on the Mac and never changing the meaning of what was
said. Because the deterministic rule engine already handles disfluencies, the
new layer can be smaller and more focused: a "meaning guard" plus a tiny local
model (or rule set) for formatting only.

## Decision

Introduce **ZenIntelligence**, an opt-in, local-only enhancement stage that sits
after `TranscriptRefinement`.

1. `ZenIntelligenceMode`: `.off`, `.format`, `.contextAware`.
2. Input: the already refined transcript, the active `LanguageProfile`, and an
   optional short context box (e.g., preceding paragraph or document title).
3. Output: a `ZenIntelligenceResult` with `text`, `wasRejected`, and
   `changeDescription`.
4. A **meaning guard** must reject any candidate that:
   - adds new facts, names, numbers, or vocabulary not present in the input,
   - changes dates, quantities, or negations,
   - reorders content in a way that alters intent.
5. The default model is a permissively licensed 1–3 B parameter language model
   converted to Core ML or run via a local Swift runner (MLX, if available).
6. ZenIntelligence is off by default. When enabled it is per-app selectable via
   `ApplicationProfile`.
7. All model weights are verified, pinned, and loaded from the same private
   Application Support `Models` directory used by speech engines.
8. No cloud call is ever made by ZenIntelligence.

## Consequences

- Users who only need disfluency removal can keep Instant Refine and leave
  ZenIntelligence off, preserving the current privacy footprint.
- Users who want richer formatting can enable a local model without sending
  text to a server.
- The meaning guard adds a fail-safe against model hallucination. A rejected
  candidate falls back to the Instant Refine output unchanged.
- Model size and memory use are bounded by the chosen 1–3 B checkpoint.
- Adding new languages requires a compatible model checkpoint and tokenizer.

## Implementation notes

- `Sources/ZenVoiceCore/ZenIntelligence.swift` owns the public API.
- The first implementation uses a rule-based meaning guard plus a small
  deterministic formatter. A local model can replace the formatter later without
  changing the API or guard contract.
- Model loading is lazy; preparation is triggered on first use and may report
  an error if the model is missing or incompatible with the hardware.

## Privacy

- ZenIntelligence never sends transcript text off-device.
- The model weights are verified with SHA-256 before load, same as speech
  models.
- No telemetry about input or output is collected.

## Related decisions

- ADR 0005 — Multi-Engine Speech Architecture
- `docs/PHASE_3.md`
- `docs/REFINEMENT_RD.md`
