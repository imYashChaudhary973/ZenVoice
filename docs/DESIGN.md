# ZenVoice v3 — "Ink & Brass" Design System

Dark-only. Derived from the actual brand mark (`Resources/Brand/ZenLogo.png`):
antique-brass voice ripples on warm ink. Replaces the v2 graphite+green
system (`ZenDesign` in `Sources/ZenVoice/ZenDesignTokens.swift`).

## Theme

One theme: **Ink & Brass**, forced dark. There is no light token set and no
appearance switcher. Windows set `NSAppearance(named: .darkAqua)` so native
controls never render light chrome.

Physical scene: a developer at 11pm, dark room, warm desk lamp. The canvas
is the warm near-black of the logo's own background — not grey graphite,
not blue "dark mode". Warmth comes from the ink itself and the brass
accent; nothing else is warm.

Color strategy: **Restrained with a two-role accent.** Brass (the brand
metal) carries affordance; green appears only for live voice. Everything
else is warm ink and paper-white text.

## Palette

Warm ink ramp (hue drifts toward 60–80°, chroma ≤0.01 — barely tinted,
never olive):

| Token | Hex | Role |
|---|---|---|
| `ink` | `#12100C` | window canvas |
| `inkSunken` | `#161310` | wells, code blocks, sunken panels |
| `inkSurface` | `#1A1712` | cards, panels |
| `inkRaised` | `#221E17` | nested rows, hover fills, inputs |
| `border` | white @ 8% | hairlines |
| `borderStrong` | white @ 16% | input focus edges, dividers that must read |

Text (warm paper ramp):

| Token | Hex | Contrast on `inkRaised` |
|---|---|---|
| `textPrimary` | `#EDE7DC` | 12.6:1 |
| `textSecondary` | `#A8A093` | 5.9:1 |
| `textTertiary` | `#948C7D` | 4.98:1 (the floor; verified on raised, the worst case) |

Accent — brass, two weights plus pressed:

| Token | Hex | Use |
|---|---|---|
| `brass` (fg) | `#C9A874` | accent text, icons, meters, active nav glyph — 7.9:1 on surface |
| `brassFill` | `#A98A5C` | primary buttons; label is `inkLabel` |
| `brassHover` | `#B4956A` | primary-button hover |
| `brassPressed` | `#9C7E52` | primary-button pressed |
| `brassMuted` | brass @ 14% | selected-row fills, quiet badges |
| `inkOnBrass` | `#141109` | label on any brass fill — 4.96–6.7:1 across states |

Voice — the only green in the system:

| Token | Hex | Use |
|---|---|---|
| `live` | `#4ADE8C` | listening/processing text, waveform, live dot — 10.3:1 |
| `liveFill` | `#2E6B47` | "Dictate" button fill; white label 6.3:1 |
| `liveMuted` | live @ 14% | live-state chips and banners |

Functional (bright enough to read, hue-separated from muted brass):

| Token | Hex | Muted fill |
|---|---|---|
| `warn` | `#F0B13E` | @14% on ink |
| `danger` | `#F27070` | `#8C3A3A` fill (white label 7.6:1), @14% muted |

## Typography

One family — the system face — in weights, plus two deliberate guests:

- **UI text**: SF Pro, fixed 12/13/15/17/20/24 scale, ratio ≈1.2. No fluid
  sizes; product UI viewed at fixed DPI.
- **Transcript & page titles**: New York (`.fontDesign(.serif)`), where
  dictated words and screen titles read like print. Never in labels,
  buttons, or data — product-register ban holds.
- **Retypable strings**: SF Mono — shortcuts, model IDs, error rates,
  checksums, sizes. Existing v2 discipline, kept.

Tracking: display titles −0.01em; nothing tighter below 20pt.

## Signature motif — the ripple

The logo's concentric voice ripples become the system's mark:

- **Selection**: active sidebar row carries a 2pt brass ripple-tick (three
  short concentric arcs) instead of a plain bar.
- **Live states**: the ZenBar waveform sits inside a faint ripple ring that
  expands once per phrase commit (state change, not decoration).
- **Progress**: model downloads and agentic steps draw a thin arc, not a
  bar.
- **Empty states**: one brass ripple glyph, 28pt, above teaching copy.

## Components

v2 component vocabulary survives structurally (`ZenScreen`, `ZenCard`,
`ZenRow`, `ZenKbd`, `ZenBadge`, `ZenStatTile`, `ZenTabStrip`,
`ZenChoiceCard`, `ZenSwitch`, `ZenSearchField`, …) — same names, same
semantics, restyled onto ink & brass. Buttons: `primary` = brassFill +
inkLabel; `secondary` = inkRaised + hairline; `destructive` = dangerFill.
Focus ring: 2pt brass @ 60% outside the hairline. Radii: cards 12, rows 8,
controls 6, pills full. Switches/tint use brass; the "Dictate" control is
the single liveFill element per screen.

## Layout

Existing geometry holds: sidebar 232, title bar 52, content max 720 with
`.zen-content` padding 28. One page scaffold per screen (`ZenScreen`),
cards stack in one column, groups labelled in sentence case.

## Motion

Quick ease-out 150–220ms (quart), no springs except the ZenBar waveform.
Ripple commits: 240ms scale + fade, disabled under Reduce Motion. Nothing
animates layout properties; overlays crossfade.

## Bans carried from the shared rules

No side-stripe accents, no gradient text, no glass, no hero-metric
templates, no identical card grids, no tracked-uppercase eyebrows, no
border+wide-shadow pairs, radius ceiling 12, no decorative grid overlays.
