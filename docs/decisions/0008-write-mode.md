# ADR 0008 — Write Mode: Inline Compose and Rewrite

## Status

Accepted — Phase 3 implemented.

## Context

Normal dictation inserts at the current caret. Phase 3 adds **Write Mode**, which
has two sub-modes:

- **Compose**: same insertion behavior as dictation, but explicitly labeled as
  Write Mode and potentially using a different ZenIntelligence profile.
- **Rewrite**: read the currently selected or focused text via Accessibility,
send it through ZenIntelligence/refinement with a user prompt, and replace it.

Rewrite is the more sensitive half: it reads existing text, transforms it, and
writes it back. It must not lose user data or replace text the user did not
intend to change.

## Decision

Write Mode is an opt-in mode switch in ZenBar alongside Dictation and Command.

1. Sub-modes:
   - `.compose` — insert transcript at caret.
   - `.rewrite` — replace selected/focused text after transformation.
2. For `.rewrite`:
   - Read the selection or focused text via Accessibility.
   - Verify the selection matches what ZenVoice expects before replacing.
   - Fall back to clipboard if Accessibility cannot safely read the selection.
   - Show a diff/preview for replacements longer than 200 characters or more
     than 30% changed.
3. The user prompt is optional and defaults to "rewrite for clarity".
4. Rewrites are rejected if the meaning guard fires.
5. Write Mode respects per-app profiles: default sub-mode and allowed prompt
   hints.

## Consequences

- Users can dictate first drafts and then ask ZenVoice to polish them inline.
- The diff/preview prevents surprising replacements.
- Clipboard fallback keeps the feature usable when Accessibility access is
  missing, with explicit user consent to paste.
- Compose mode is functionally identical to dictation but signals intent and
  can use a different ZenIntelligence mode.

## Implementation notes

- `Sources/ZenVoiceCore/WriteModeEngine.swift` owns the core logic.
- Accessibility read and replace live in the `ZenVoice` app target.
- The diff/preview UI is part of the Phase 3 settings/overlay work.

## Privacy

- Rewrite reads only the current selection or focused text.
- Transformation runs on-device through ZenIntelligence or Instant Refine.
- No rewritten text is sent off-device.

## Related decisions

- ADR 0006 — ZenIntelligence
- ADR 0007 — Command Mode
- `docs/PHASE_3.md`
