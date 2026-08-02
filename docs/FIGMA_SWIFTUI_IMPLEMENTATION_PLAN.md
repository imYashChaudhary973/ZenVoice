# ZenVoice Figma-to-SwiftUI Implementation Plan

> Completed historical implementation plan from July 2026. The model counts,
> refinement modes, and screen details below describe the approved design at
> implementation time, not the current product contract. Current behavior is
> defined by the application source, [Architecture](ARCHITECTURE.md),
> [Instant Refine](INSTANT_REFINE.md), and
> [Verified Model Catalogue](MODEL_CATALOG.md).

## Approved design

- Figma file: `2J4wUxWlsMSI0gsMxbLuIM`
- Page: `06 Full Feature Prototype`
- Dark start: `23:2`
- Light start: `24:2407`
- Approved prototype: 106 screens, 53 per theme

## Implementation principles

1. Preserve the existing local-first product behavior, view models, storage,
   permissions, model verification, and runtime services.
2. Replace presentation incrementally; do not duplicate business logic in
   views.
3. Use native macOS SwiftUI controls for buttons, toggles, menus, pickers,
   text fields, alerts, sheets, and scrolling.
4. Map Figma semantic variables into adaptive SwiftUI colors so Light and Dark
   modes share one component implementation.
5. Keep the verified speech/refinement catalogues authoritative. The UI must
   never invent a downloadable model or omit license, revision, checksum,
   size, compatibility, or hardware-fit information already provided by the
   source.
6. Maintain minimum 44-point interactive controls and an 11-point minimum
   type size for supporting text.

## Phase 1 — Foundation and shell

- Expand the settings window to the approved 1200 × 800 canvas and retain a
  practical resizable minimum.
- Add adaptive Light/Dark semantic colors matching the Figma variables.
- Persist the selected appearance locally.
- Rebuild the 210-point sidebar with:
  - exact ten-section order;
  - 44-point rows;
  - selected gold leading rail;
  - Welcome tour;
  - appearance switch;
  - local-processing status.
- Align page padding, headings, cards, status pills, buttons, and typography
  with the approved reusable components.

## Phase 2 — Primary sections

Migrate the ten existing screens without replacing their observable models:

1. Overview — five readiness facts, shortcut entry, usage steps.
2. Audio — microphone states, selection, Audio Doctor, recovery guidance.
3. Models — six verified Whisper entries, recommendation, lifecycle actions.
4. Languages — profiles, output modes, searchable 64-language catalogue.
5. Instant Refine — four modes, context, profiles, verified local models,
   meaning guard, live-preview controls.
6. History — consent, All/Recovery, search, record actions, deletion states.
7. Insights — metrics, activity, categories, applications, sharing.
8. Voice Profile — rules, review, patterns, paused/empty states.
9. Shortcuts — capture, collision handling, reset, hold-to-dictate.
10. Privacy — inventory, permissions, history/recovery/private controls.

## Phase 3 — Supporting flows

- Preserve the four-step onboarding sheet in both appearances.
- Restyle ZenBar Ready, Listening, Processing, Success, and Error states using
  the same adaptive tokens.
- Preserve native confirmation alerts and sheets for destructive operations,
  model lifecycle actions, History consent, and highlight sharing.
- Retain real application behavior where Figma used simulated states.

## Phase 4 — Verification

Run:

1. `swift build`
2. `swift run ZenVoiceCoreChecks`
3. `swift run ZenVoiceStorageChecks`
4. `swift run ZenVoiceRuntimeChecks`
5. Focused source checks for:
   - exact navigation order;
   - Light/Dark appearance support;
   - minimum window size;
   - verified model catalogue usage;
   - no production feature/view-model removal.
6. Launch the executable and inspect the settings window when the environment
   permits GUI validation.

## Completion criteria

- All ten sections remain functional.
- Both appearances use the approved semantic palette.
- Existing local-only privacy behavior is unchanged.
- Model legal and verification metadata remains source-driven.
- All automated checks pass.
- No unrelated source files are changed.
