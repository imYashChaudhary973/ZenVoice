# ZenVoice — New Design Prototype

Fully interactive HTML/CSS/JS prototype of the redesigned ZenVoice app.
No build step, no dependencies, works offline.

## Open it

```bash
open ZenVoiceNewDesign/index.html
```

## What to try

- **First-run flow** — appears automatically on first open (7 steps: welcome,
  privacy, permissions, shortcut recorder, language, model download, live test).
  Replay it anytime from the “First-run” button in the floating prototype bar,
  or from Help & FAQ inside the app.
- **Dictate demo / Private / Error** (prototype bar) — plays the full ZenBar HUD
  sequence: listening with live waveform + phrase preview → transcribing →
  inserted / recovery error.
- **Menu bar** (prototype bar) — the menu-bar popover mock.
- **Light/dark** — toggle in the prototype bar or the sidebar footer.
- Every screen is functional: record real shortcut combos, search 53+ languages,
  simulate checksum-verified model downloads with cancel, run the Audio Doctor,
  add/delete correction rules, search history, preview highlight cards, manage
  the Recovery Inbox, search the FAQ.

## Files

```
index.html          shell: window chrome, sidebar, HUD, onboarding mounts
css/tokens.css      design tokens (light + dark, OKLCH)
css/base.css        reset + component vocabulary
css/app.css         layout: window, sidebar, onboarding, ZenBar, menu bar
js/icons.js         single inline-SVG icon set (Lucide-derived)
js/data.js          mock catalogs & records mirroring the real app
js/app.js           router, theme, HUD simulation, menu bar
js/onboarding.js    first-run flow
js/screens/*.js     one file per screen (12 screens)
PRODUCT.md          product context + non-negotiable feature inventory
DESIGN.md           the design system contract for the SwiftUI rebuild
```

## Design docs

- `PRODUCT.md` — every feature the redesign must keep (nothing dropped).
- `DESIGN.md` — tokens, type scale, motion, navigation model, onboarding rules,
  ZenBar states. This is the contract for implementing the redesign in SwiftUI.
