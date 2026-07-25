# ZenVoice — Redesign Design System (v2)

The visual + UX contract for the redesigned app. The prototype in this directory
implements it; the SwiftUI rebuild copies it.

## 1. Principles
1. **The tool disappears into the task.** Dictation is the product; settings are a
   quiet control room, not a dashboard performance.
2. **Trust through specificity.** Privacy claims are always concrete: named files,
   checksums, sizes, revisions.
3. **One idea per screen.** Each screen answers one question. Advanced options fold
   away behind progressive disclosure, never deleted.
4. **States are designed, not defaulted.** Every control ships default / hover /
   focus / active / disabled / loading / error / empty.

## 2. Color — "Ink & Gold", restrained strategy
Accent is used for primary actions, current selection, and live-state indicators only.
Everything else is neutral. Success/danger are reserved for true state.

| Token            | Light                      | Dark                       |
|------------------|----------------------------|----------------------------|
| canvas           | oklch(0.972 0.002 260)     | oklch(0.145 0.008 265)     |
| sidebar          | oklch(0.946 0.003 260)     | oklch(0.168 0.009 265)     |
| surface          | white                      | oklch(0.195 0.010 265)     |
| surface-raised   | oklch(0.958 0.003 260)     | oklch(0.225 0.011 265)     |
| border           | ink @ 9%                   | white @ 8%                 |
| border-strong    | ink @ 17%                  | white @ 15%                |
| text             | oklch(0.205 0.012 265)     | white @ 95%                |
| text-2           | oklch(0.42 0.010 265)      | white @ 64%                |
| text-3           | oklch(0.54 0.008 265)      | white @ 42%                |
| accent           | oklch(0.52 0.085 75) gold-700 | oklch(0.81 0.075 80) gold-300 |
| accent-soft      | gold @ 12%                 | gold @ 14%                 |
| success          | oklch(0.50 0.13 155)       | oklch(0.78 0.15 155)       |
| danger           | oklch(0.53 0.19 22)        | oklch(0.70 0.17 20)        |
| on-accent        | white                      | oklch(0.16 0.01 265)       |

Contrast verified: body text ≥ 4.5:1 on canvas/surface in both modes; accent-on-canvas
≥ 4.5:1 light, ≥ 8:1 dark.

## 3. Typography
Single family: system stack (`-apple-system, "SF Pro Text"…`) — native to macOS,
correct for a product register. Fixed rem scale, ratio ≈ 1.2:

| Step     | Size / weight       | Use                          |
|----------|---------------------|------------------------------|
| display  | 26px / 700, -0.02em | Onboarding headlines         |
| title    | 20px / 700, -0.015em| Screen titles                |
| heading  | 15px / 600          | Section headings             |
| body     | 13px / 400, lh 1.55 | Default                      |
| label    | 13px / 590          | Buttons, control labels      |
| caption  | 11.5px / 400        | Helper text, meta            |
| mono     | 12px SF Mono        | Checksums, revisions, kbd    |

## 4. Spacing & shape
- Scale: 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48.
- Window: 1080×700 min. Sidebar 224px fixed; content column max 640px for prose,
  full width for tables.
- Radius: control 7px · panel 12px · HUD pill 999px. No radius above 16px.
- Depth: borders first. Shadows only on floating layers (HUD, menus, dialogs),
  ≤ 24px blur, low alpha.

## 5. Motion
- 150–220ms, `cubic-bezier(0.22, 1, 0.36, 1)` (ease-out-quint family).
- Screen change: 140ms fade + 4px rise. No page-load choreography.
- Waveform: canvas-driven from simulated loudness; paused entirely under
  `prefers-reduced-motion` (replaced by a static level bar — mirrors the app's
  Reduce Motion behavior).
- State changes (download %, doctor pass) animate value, never layout.

## 6. Navigation model (the big IA change)
```
ZenVoice window
├── Home                    ← status + quick actions + recent activity
├── DICTATION
│   ├── Shortcuts           ← all key bindings + hold-to-dictate
│   ├── Audio               ← mics + Audio Doctor
│   ├── Languages           ← 64 languages, Hinglish modes
│   └── Instant Refine      ← modes, refinement models, commit-on-pause,
│                              voice commands, context box
├── PERSONAL
│   ├── Voice Profile       ← phrases + correction rules + pattern controls
│   └── App Profiles        ← per-app language/refine/commands
├── YOUR DATA
│   ├── History             ← search/copy/retry/delete + Recovery Inbox tab
│   └── Insights            ← words, WPM, streaks, apps, categories
└── SYSTEM
    ├── Models              ← speech model catalog + recommendations
    ├── Privacy             ← inventory, toggles, permissions
    └── Help & FAQ          ← searchable FAQ, cheat-sheet, replay setup
```
Footer of sidebar: appearance toggle + "Processing stays local" beacon.

## 7. First-run flow (replaces the sheet-based setup guide)
Full-window, 7 steps, skippable at any point, replayable from Help & FAQ:
1. Welcome — brand moment, three concrete promises
2. Privacy — what is stored, encrypted, never sent
3. Permissions — mic + accessibility with live status and graceful skip
4. Shortcut — try the default or record another (conflict-checked)
5. Language — English / Hinglish / auto / 64 more
6. Model — recommended-for-this-Mac download with %, size, SHA-256
7. Test drive — dictate a sentence into a sandbox field; success state → Finish

Rules: shown only when `onboarded == false`; closing the window mid-flow resumes on
next launch; **never** rendered above the settings window.

## 8. ZenBar HUD
Floating pill, bottom-center, dark glass in both appearances (matches screen
recording aesthetics), 5 states:
ready → listening (waveform + live phrase preview + Cancel/Done) → processing
(indeterminate shimmer) → success (word count + "Inserted into <app>") / error
(reason + Retry). Private Dictation adds a slashed-eye badge. Optional status line
"Dictating with ZenVoice".

## 9. Component vocabulary
Switch (macOS-style), segmented control, select, kbd chip, shortcut recorder,
progress bar (determinate + shimmer), status dot, badge, list row (icon · title ·
meta · trailing control), search field, empty state (teaches the screen), toast,
inline banner (info/warn/danger), tab strip (History ↔ Recovery Inbox), stat tile,
bar/spark charts (CSS-only), FAQ accordion.
Icons: single set of inline SVG strokes (Lucide-derived), 16/18px, 1.75 stroke.

## 10. Slop guards applied
No gradient text, no glassmorphism cards inside content, no side-stripe callouts,
no hero-metric template, no identical icon-card grids, no 24px+ radii, no
border+mega-shadow pairing, group labels ≤ 10.5px and only in the sidebar.
