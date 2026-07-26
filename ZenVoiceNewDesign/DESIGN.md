# ZenVoice — Ledger Design System (v3)

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

## 2. Color — "Ledger", editorial warmth
Accent is used for primary actions, current selection, and live-state indicators only.
Everything else is neutral. Success/danger are reserved for true state.

| Token            | Light                      | Dark                       |
|------------------|----------------------------|----------------------------|
| canvas           | `#F7F5F0`                  | `#201E1B`                   |
| sidebar          | `#F7F5F0`                  | `#201E1B`                   |
| surface          | `#FCFBF7`                  | `#262421`                   |
| surface-raised   | `#F1EEE7`                  | `#2C2A25`                   |
| border           | warm ink @ 9%              | warm white @ 7%             |
| border-strong    | warm ink @ 16%             | warm white @ 14%            |
| text             | `#1F1D1A`                  | `#EDE7DC`                   |
| text-2           | `#5C564C`                  | `#ADA595`                   |
| text-3           | `#8B8377`                  | `#7D7568`                   |
| accent           | `#A6492E`                  | `#D68A62`                   |
| accent-soft      | rust @ 8%                  | rust @ 12%                  |
| success          | `#33713F`                  | `#7FB689`                   |
| danger           | `#AC3A2A`                  | `#D97B66`                   |
| on-accent        | `#FBF6F0`                  | `#221510`                   |

Contrast verified: body text ≥ 4.5:1 on canvas/surface in both modes; accent-on-canvas
≥ 4.5:1 light, ≥ 8:1 dark.

## 3. Typography
Ledger pairs the system stack (`-apple-system, "SF Pro Text"…`) with New York's
serif voice for titles, brand moments, and metrics:

| Step     | Size / weight       | Use                          |
|----------|---------------------|------------------------------|
| display  | 30px / 600 serif    | Onboarding headlines         |
| title    | 26px / 600 serif    | Screen titles                |
| heading  | 10px / 600, tracked | Uppercase section labels     |
| body     | 13px / 400, lh 1.55 | Default                      |
| label    | 13px / 590          | Buttons, control labels      |
| caption  | 11.5px / 400        | Helper text, meta            |
| mono     | 12px SF Mono        | Checksums, revisions, kbd    |

## 4. Spacing & shape
- Scale: 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48.
- Window: 1180×760 ideal. Sidebar 224px fixed; content column max 760px,
  full width for tables.
- Radius: control 4px · panel 4px · ZenBar 9px. No radius above 10px.
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
│   └── Instant Refine      ← Off/Clean/Agent Prompt, commit-on-pause,
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
Floating paper-like 9px-radius chip, bottom-center, matching the chosen appearance. Runtime states:
ready → listening (live dot + waveform + Cancel/Finish only) → processing →
inserting → success / error. Success shows "Inserted with ZenVoice", word count,
and WPM. Error names the failure and offers Try again / Dismiss. Processing reads
"Refining…" and insertion reads "Inserting…". The actual
dictation workflow drives the cycle; prototype-only state controls do not ship.

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
