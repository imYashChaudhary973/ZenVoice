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

**Moss on ink.** A near-black canvas, layered surfaces, and one muted green
accent. The accent is deliberately desaturated: a saturated green filling
selected navigation and primary buttons on an almost-black canvas glows, and
this is an app people leave open all day.

**Cards, not rules.** Content sits in large softly-rounded cards with a single
hairline edge. Horizontal rules between sections are not used — a card already
has an edge, and adding a rule above it draws two boundaries a few points
apart.

**Depth by nesting.** A card holds inset rows on a lighter surface. Radius
tightens as you nest (16 → 12 → 8) so the stack reads as depth rather than as
one blurry shape.

**Native controls stay native.** Switches, pop-up buttons, and text fields are
the system's, tinted once at the window root. There is no hand-drawn switch.

## Colour

### The two accent weights

The accent exists twice because one green cannot do both jobs:

| Token | Use | Contrast |
| --- | --- | --- |
| `Semantic.accent` | Accent *text*, icons, meters, hairlines drawn on the canvas | ≥ 4.5:1 on ink |
| `Semantic.accentFill` | Selected navigation, primary buttons — anything carrying a white label | white on it ≥ 4.5:1 |

Using one mid-green for both is the specific mistake this split prevents: a
single mid-green lands near 3.8:1 in each direction, so accent text on the
canvas and white text on the button are *simultaneously* too faint. Nothing in
the window should use a raw green — pick the weight that matches the job.

`accentStrong` is the pressed state for a filled control. It always moves away
from the label colour: darker in light mode, brighter in dark.

In light mode both weights resolve to the same deep moss. On a white canvas a
light green cannot clear 4.5:1 as text, and does not need lightening to carry
white as a fill.

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
| `display` | 34 bold | The one hero number or word on a page |
| `pageTitle` | 24 bold | Page heading, beside its icon chip |
| `metric` | 34 bold | The number in a stat tile |
| `body` / `bodyStrong` | 13 | Everything else |
| `caption` | 11.5 | Supporting text under a label |
| `eyebrow` | 11 semibold, tracked 1.0 | Uppercase label *above a number* |
| `badge` | 11 semibold | Pill text |

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
| `Layout.sidebarWidth` | 240 | One named value. The title bar used to hand-copy it and the two drifted apart. |
| `Layout.titleBar` | 52 | Clears the traffic lights, which the window draws over the sidebar. |
| `Layout.navRow` | 40 | Painted height of a navigation row. |
| `Layout.navIcon` | 26 | Icon slot in a navigation row, so labels share a baseline. |
| `Layout.hitTarget` | 44 | Clickable frame of anything interactive. |
| `Layout.control` | 32 | Painted height of a compact control inside a row that already meets the hit target. |
| `Layout.proseColumn` | 720 | Measure for running prose. Cards are **not** capped — see below. |

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
the *painted* box 32pt is hostile to trackpad users, anyone with a tremor, and
every assistive technology that targets by frame.

## The window shell

```
┌─────────────┬──────────────────────────────────────┐
│             │  ZenVoice        ( status ⌘ ☾ ) Dictate│  ← top bar, 52pt
│  ● Home     ├──────────────────────────────────────┤
│             │                                      │
│  Configure  │   [chip]  Page title                 │
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

The selected row is a filled `accentFill` pill with a white label: the
strongest single mark in the window, and the only place the fill weight appears
at rest. Unselected icons are accent-tinted, because grey icons on a
translucent panel disappear against a busy wallpaper.

**The rail is scanned by its icons, not read.** Glyphs are drawn at 19pt in a
26pt slot, larger than the 15pt label beside them. At 13pt they were *smaller*
than their own label and read as decoration. Group headings sit at 12pt in
`textSecondary` — tertiary vanished against a light wallpaper showing through
the material.

The painted pill is 40pt against a 44pt clickable frame, so consecutive rows
nearly touch. The approved design packs them tighter still, at roughly 36pt
pitch; ZenVoice does not follow it that far, because a 36pt row cannot hold a
44pt hit target and the rail is the most-clicked surface in the app.

Appearance cycles System → Light → Dark from one toolbar button that names both
its current value and its next one. A three-way segmented control used to sit
in the sidebar footer, spending a permanent 44pt of navigation space on a
setting most people touch once.

## Components

Compose screens from these. If a screen needs something new, add it here rather
than hand-rolling it locally.

| Component | Use |
| --- | --- |
| `ZenScreen` | The one page scaffold: icon chip, title, subtitle, optional tab strip, content. |
| `ZenCard` | A card that heads itself: icon chip, title, subtitle, content. |
| `ZenPanel` | A bare card, for content that supplies its own heading or none. |
| `ZenInsetRow` | A row nested inside a card, on its own inset surface. |
| `ZenRow` | A flat row in a divided list. |
| `ZenCardHeader` / `ZenIconChip` | The heading block and its tinted glyph container. |
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

Quick `easeOut` fades and slides everywhere: 0.15s for state flips, 0.22s for
anything that moves. The single spring is reserved for the ZenBar waveform, the
one living element in the app. Every helper in `ZenDesign.Motion` returns `nil`
when Reduce Motion is on, so call sites pass
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
