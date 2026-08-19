# UI redesign — Ink & Brass (dark-only)

Working plan for the `redesign/dark-ui` branch. The design contract is
[Design](DESIGN.md) (v3, Ink & Brass); the product register is
[Product](../PRODUCT.md). Remove this document when the phase ships — the
durable visual contract stays in `DESIGN.md`.

Replaces the v2 graphite+green system entirely: new warm-ink palette, brass
accent, green reserved for live voice, serif transcript typography, ripple
motif. **No light mode, no appearance switcher.**

Survey facts that shape the plan: no code references `ZenDesign.Primitive`
directly — every color flows through `Semantic` tokens, so the palette cutover
is centralized; `ZenAppearance` (System/Light/Dark) lives in exactly four
files; one hardcoded gradient in `ShareHighlightCard.swift`.

## Phase 1 — Tokens + dark-only cutover

- `Sources/ZenVoice/ZenDesignTokens.swift`: rewrite `Primitive`/`Semantic` to
  the v3 palette (ink ramp, white 8%/16% hairlines, paper text ramp, brass
  fg/fill/hover/pressed/muted + `inkOnBrass`, live set, warn/danger) as static
  dark constants; delete the `adaptive(light:dark:)` helper and every light
  value; new fixed type scale (12/13/15/17/20/24), New York via
  `.fontDesign(.serif)` for transcripts and page titles, SF Mono for
  retypable strings; motion 150–220ms quart, waveform-only spring; radii
  cards 12 / rows 8 / controls 6 / pills full.
- Delete `Sources/ZenVoice/AppearancePreference.swift` and all `ZenAppearance`
  usages: `ZenBarView.swift`, `ZenVoiceSettingsView.swift` (appearance picker,
  command-palette entry, cycle shortcut), `Overlay/LivePreviewOverlayView.swift`.
  Window controllers set `NSAppearance(named: .darkAqua)`; SwiftUI roots pin
  `.preferredColorScheme(.dark)`.
- Gate: `swift build` clean; `grep -r "ZenAppearance\|zenvoice\.appearance\|adaptive("`
  over `Sources/` returns nothing.

## Phase 2 — Chrome and shared components

- `ZenV2Components.swift`, `ZenChrome.swift`, `ZenCommandPalette.swift`:
  restyle the existing vocabulary (same names, same semantics) — primary =
  `brassFill` + `inkOnBrass`, secondary = `inkRaised` + hairline,
  destructive = `dangerFill`; focus ring 2pt brass @ 60%; the "Dictate"
  control is the single `liveFill` element per screen.
- Ripple motif primitives: brass ripple-tick selection for active sidebar row,
  thin-arc progress for downloads/agentic steps, brass ripple empty-state
  glyph (28pt).
- Hardcoded colors → tokens: `ShareHighlightCard.swift` gradient,
  `Overlay/OverlayBarButton.swift`, `Overlay/BrandLogo.swift`, `BrandAssets.swift`.
- Gate: build clean; every visual constant resolves through `ZenDesign`.

## Phase 3 — Screens and overlays

- All of `Screens/` (Onboarding, Models, Privacy, Shortcuts, AppProfiles, …):
  `ZenScreen` scaffold per page; page titles and transcript surfaces move to
  New York; empty states get the ripple glyph.
- `ZenBarView`: waveform in `live`, faint ripple ring expanding once per
  phrase commit (240ms scale+fade, off under Reduce Motion).
- `AgenticModeScreen`, `CloudAIPreviewWindowController`,
  `AgenticApprovalWindowController`: same tokens, arc progress for steps.
- Gate: build clean; screenshot pass over every screen with the Mac set to
  Light — nothing renders light chrome, including ZenBar and overlays.

## Phase 4 — Docs + polish

- `DESIGN.md` stays the contract; reconcile any drift between it and shipped
  `ZenDesignTokens.swift` (hex values must match exactly).
- Drop this plan and its docs-index row; `CHANGELOG.md` entry.
- Accessibility pass: contrast pairs re-verified against shipped hex (≥4.5:1
  body, ≥3:1 glyphs), keyboard path + focus rings intact, VoiceOver labels on
  icon-only controls.

## Verification

1. `swift build` in the worktree after each phase.
2. Launch the built app with macOS Appearance = Light: settings window,
   ZenBar, live preview, onboarding, approval windows all render dark.
3. Keyboard-nav + focus-ring pass on settings and the command palette.
4. Contrast audit: shipped token hexes match the `DESIGN.md` table.
