# Design

The ZenVoice interface is one window: a translucent navigation rail on the
left, a content column of cards on the right. Everything the app can do is
reachable from that rail, and the window opens when the app launches.

This document is the contract for the visual system. It describes what the
tokens mean and when to reach for each component, not every pixel — the pixels
live in [`ZenDesignTokens.swift`](../Sources/ZenVoice/ZenDesignTokens.swift),
[`ZenChrome.swift`](../Sources/ZenVoice/ZenChrome.swift), and
[`ZenV2Components.swift`](../Sources/ZenVoice/ZenV2Components.swift).

## Principles

**Ink, one jade, real materials.** A cool near-black canvas, translucent
columns over vibrancy, and one jade accent. The accent is spent on exactly
three jobs: the selected navigation row, the primary action, and live state.
Everything else is monochrome. Nine jade glyphs on a screen is the same as
zero — none of them is a signal.

**Depth from light, not boxes.** A card is a surface with a shadow and a
bright top edge (light catching the lip). Hairlines survive only as the
faintest fallback. Nested `ZenInsetRow`s draw no border; a stack of 1px
rectangles is what the previous revision shipped.

**Type carries the hierarchy.** The scale spans 11 to 34 with per-size
tracking: negative on display sizes, slightly positive at the floor. Four
sizes inside five points is how the old window had no lead.

**Native controls stay native.** Switches, pop-up buttons, and text fields are
the system's, tinted once at the window root. There is no hand-drawn switch.


## Colour

### The two accent weights

The accent exists twice because one green cannot do both jobs:

| Token | Use | Contrast |
| --- | --- | --- |
| `Semantic.accent` | Accent *text*, selected-row icon, live meters | ≥ 4.5:1 on ink |
| `Semantic.accentFill` | Primary buttons — anything carrying a white label | white on it ≥ 4.5:1 |

Using one mid-green for both is the specific mistake this split prevents: a
single mid-green lands near 3.8:1 in each direction, so accent text on the
canvas and white text on the button are *simultaneously* too faint. Nothing in
the window should use a raw green — pick the weight that matches the job.

`accentStrong` is the pressed state for a filled control. It always moves away
from the label colour: darker in light mode, brighter in dark.

In light mode both weights resolve to the same deep jade. On a white canvas a
light green cannot clear 4.5:1 as text, and does not need lightening to carry
white as a fill. Selected navigation uses `accentMuted` plus an accent icon,
never a filled `accentFill` pill — the fill weight is for buttons that carry
a white label, not for a row that stays selected all day.


### Surfaces

`canvas` → `surface` (cards) → `surfaceRaised` (inset rows) → `surfaceSunken`
(tracks and wells). The sidebar is not in this family: it is an
`NSVisualEffectView` with `behindWindow` blending, with `Semantic.sidebar`
painted over it at low alpha to settle navigation text against a bright
wallpaper.

The root view deliberately paints **no** window-wide background. An opaque fill
there sits behind the sidebar's material and flattens it to a plain grey panel.
Each column paints its own surface instead, and the window's
`backgroundColor` is `.clear` for the same reason.

## Type

| Token | Size / weight | Use |
| --- | --- | --- |
| `display` | 32 semibold, tracking −0.7 | The one hero word on a page |
| `pageTitle` | 24 semibold, tracking −0.5 | Page heading |
| `sectionTitle` | 17 semibold, tracking −0.3 | Card heading |
| `metric` | 34 semibold, monospaced digits | The number in a stat tile |
| `body` / `bodyStrong` | 13 | Everything else |
| `caption` | 11.5, tracking 0.05 | Supporting text under a label |
| `eyebrow` | 11 semibold, tracking 0.9 | Uppercase label *above a number* |
| `badge` | 11 medium | Pill text |


**11pt is the floor.** Nothing in the window renders type smaller;
`Scripts/check-ui-invariants.sh` enforces it. The exported share card is not
window chrome and has its own canvas scale.

**Uppercase tracking is for eyebrows only** — the label above a metric, where
it says what the number is. Used as a section heading it reads as a system
warning rather than as a title. Section headings are sentence case at body
weight.

## Layout

| Token | Value | Note |
| --- | --- | --- |
| `Layout.sidebarWidth` | 224 | One named value. The title bar used to hand-copy it and the two drifted apart. |
| `Layout.titleBar` | 52 | Clears the traffic lights, which the window draws over the sidebar. |
| `Layout.navRow` | 34 | Painted height of a navigation row. |
| `Layout.navIcon` | 22 | Icon slot in a navigation row, so labels share a baseline. |
| `Layout.hitTarget` | 44 | Clickable frame of anything interactive. |
| `Layout.control` | 30 | Painted height of a compact control inside a row that already meets the hit target. |
| `Layout.proseColumn` | 620 | Measure for running prose. Cards are **not** capped — see below. |


**Cards fill the window; only prose is capped.** The page used to hold its
whole stack inside a fixed column and centre it, which is invisible in a small
window and obvious in full screen — the content floated in the middle of the
pane behind margins that lined up with neither the sidebar nor the top bar.
Cards now stretch, and the page heading caps its own subtitle at
`proseColumn` so long sentences still have a measure.

**A button label never wraps.** `ZenButtonShape` sets `lineLimit(1)` and
`fixedSize(horizontal:)`. The painted background is a fixed height, so a label
allowed onto a second line is drawn straight through the button's own border —
which is exactly what "Replay setup guide" did.

A painted control is compact; the frame the user can hit is 44pt. Drawing 44pt
boxes would make a dense settings window look like a touch UI, and making only
the *painted* box 30pt is hostile to trackpad users, anyone with a tremor, and
every assistive technology that targets by frame.


## The window shell

```
┌─────────────┬──────────────────────────────────────┐
│             │  ZenVoice        ( status ⌘ ☾ ) Dictate│  ← top bar, 52pt
│  ● Home     ├──────────────────────────────────────┤
│             │                                      │
│  Configure  │           Page title                 │
│    Dictation│           Page subtitle              │
│    …        │                                      │
│             │   ┌────────────────────────────────┐ │
│  Use        │   │ card                           │ │
│  Activity   │   └────────────────────────────────┘ │
│  Help       │                                      │
└─────────────┴──────────────────────────────────────┘
   vibrancy                     canvas
```


The sidebar runs the **full height** of the window, under the traffic lights,
and the content column carries its own top bar. A single title bar spanning
both would cut the sidebar material off below the window's rounded top
corners.

Navigation is four labelled groups plus an unlabelled Home: what you set up
(Configure), what you use (Use), what it recorded (Activity), and where to get
help (Help). Every entry previously had its own one-item heading, so the
headings carried no information — each label was just the row beneath it,
restated.

The selected row is `accentMuted` with an accent icon and a semibold label.
Unselected icons are monochrome. Colouring every glyph jade made the selected
row invisible among nine green marks; one tinted icon is now the signal.

**The rail is scanned by its icons, not read.** Glyphs sit at 13pt in a 22pt
slot, matching the 13pt label beside them. Group headings sit at 11pt in
`textSecondary` — tertiary vanished against a light wallpaper showing through
the material.

The painted row is 34pt against a 44pt clickable frame. Tighter than a touch
UI, loose enough that consecutive hit targets do not collide.

Appearance cycles System → Light → Dark from one toolbar button that names both
its current value and its next one. A three-way segmented control used to sit
in the sidebar footer, spending a permanent 44pt of navigation space on a
setting most people touch once.

## Components

Compose screens from these. If a screen needs something new, add it here rather
than hand-rolling it locally.

| Component | Use |
| --- | --- |
| `ZenScreen` | The one page scaffold: title, subtitle, optional tab strip, content. |
| `ZenCard` | A card that heads itself: title, subtitle, content. |
| `ZenPanel` | A bare card, for content that supplies its own heading or none. |
| `ZenInsetRow` | A row nested inside a card, on its own inset surface. No border. |
| `ZenRow` | A flat row in a divided list. |
| `ZenCardHeader` / `ZenIconChip` | The heading block, and a monochrome glyph. Pass `tint` only when colour encodes state. |
| `ZenStatTile` | Uppercase eyebrow, then the number, then one line of context. |
| `ZenBadge` | Sentence-case capsule pill. Not uppercase — these carry proper nouns. |
| `ZenBanner` | Coloured glyph, body-contrast text, tinted background. |
| `ZenTabStrip` | Views *within* a section. Its underline hugs its label. |
| `ZenSegmentedControl` | A choice between ranges or modes, on a sunken track. |
| `ZenToolbarCluster` | The capsule of global actions in the top bar. |
| `ZenChoiceCard` | Mutually exclusive picker cards. |


### One scaffold per section

A screen shown as a tab supplies **content only**; its container owns the
`ZenScreen`. Without that rule a section grows a second title, a second rule,
and a nested scroll view. `Scripts/check-ui-invariants.sh` enforces it in both
directions: tab children must not construct a `ZenScreen`, and every container
must construct exactly one and carry a tab strip.

## The menu bar

ZenVoice installs a real `NSApp.mainMenu` — App, Edit, Window — in
`AppDelegate.configureMainMenu()`.

It had none. Running as an accessory with only a status-item menu is fine while
the app is invisible, but the window flips it to `.regular`, and AppKit routes
every standard key equivalent through the main menu. With no main menu there
was nothing to route to: ⌘Q, ⌘W and ⌘M did nothing, and neither did ⌘C, ⌘V or
⌘A inside the app's own text fields.

The Edit menu is not decoration. Every text field in the window — the Cloud AI
key field included — depends on those responder actions existing somewhere in
the menu bar.

Closing is not quitting, and a menu-bar app has to be able to say so:

- **⌘W** closes the window. `windowWillClose` drops the app back to
  `.accessory`, so the status item and the global shortcut survive.
- **⌘Q** quits.

`NSApp.windowsMenu` is set to the Window menu so AppKit contributes Enter Full
Screen and the window list itself.

## Waiting on the user

The cloud review panel is deliberately non-activating — it must not take focus,
because taking it would move the caret the enhanced text is about to replace.
That makes it easy to miss, and it holds the dictation open while it waits, so
three things keep it from being a dead end:

- the ZenBar switches to `.awaitingCloudReview` and says what it is waiting for,
  rather than sitting on "transcribing…" while nothing happens;
- pressing the dictation shortcut dismisses it and keeps the local transcript,
  so the way out is the key the user already pressed;
- it resolves itself after two minutes.

`awaitingCloudReview` is a phase of its own precisely so `isBusy` stays false
and that shortcut still reaches the app.

## Motion

Springs, never durations. A fixed-duration curve cannot be interrupted without
a jump; a spring starts from the current on-screen value and carries velocity
through a re-target. `Motion.standard` is critically damped (`response` 0.34,
`dampingFraction` 1.0). `Motion.fast` is the same shape at 0.2, for press and
hover. `Motion.momentum` adds overshoot (`dampingFraction` 0.78) only when a
gesture threw the motion — the ZenBar width morph. Controls scale to 0.97 on
pointer-down via `ZenPressableStyle`. Every helper in `ZenDesign.Motion`
returns `nil` when Reduce Motion is on, so call sites pass
`@Environment(\.accessibilityReduceMotion)` straight through.


## Checking the work

```sh
swift build
./Scripts/check-ui-invariants.sh
```

The invariant script encodes decisions the compiler cannot see, each of which
was a real defect at some point: a tab child growing its own scaffold, the
sidebar width drifting between two files, the cloud preview stealing focus from
the app a transcript was about to be inserted into, and type below the 11pt
floor.
