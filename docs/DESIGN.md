# Design

The ZenVoice interface is one native macOS window: a `NavigationSplitView`
sidebar, a unified titlebar toolbar, and a scrolling preference pane. The
graphite/violet identity stays intact, while navigation, toolbar placement,
segmented controls, focus, and window behavior follow familiar Apple patterns.

This document is the contract for the visual system. It describes what the
tokens mean and when to reach for each component, not every pixel — the pixels
live in [`ZenDesignTokens.swift`](../Sources/ZenVoice/ZenDesignTokens.swift),
[`ZenChrome.swift`](../Sources/ZenVoice/ZenChrome.swift), and
[`ZenV2Components.swift`](../Sources/ZenVoice/ZenV2Components.swift).

## Principles

**Graphite and violet.** The approved reference supplies the visual anchor:
`#39393B` for the main surface, `#444348` for selected and raised rows,
`#FEFEFF` for primary text, `#B9B9BB` for secondary text, and `#543EF5` for
compact badges and filled actions. The content canvas extends the same neutral
ramp at `#303033`.

**Familiarity before invention.** Navigation uses `NavigationSplitView`, tabs
use a native segmented `Picker`, controls use SwiftUI/AppKit components, and
the toolbar belongs to the window rather than being painted inside content.

**Depth by nesting.** A card holds inset rows on a lighter surface. Radius
tightens as you nest (16 → 12 → 8) so the stack reads as depth rather than as
one blurry shape.

**Native controls stay native.** Switches, pop-up buttons, and text fields are
the system's, tinted once at the window root. There is no hand-drawn switch.

**Behavior over animation.** Interactive transitions use critically damped,
interruptible springs. Feedback begins on press, never locks input, and follows
the same path in both directions. Bounce is reserved for waveform motion that
actually carries momentum.

**Materials are structural.** Translucency separates the sidebar and floating
chrome; content groups remain solid graphite. Reduce Transparency replaces the
material with the same solid palette, and Increased Contrast strengthens
boundaries without changing layout.

## Colour

### The two accent weights

The accent exists twice because the sampled violet cannot do both jobs:

| Token | Use | Contrast |
| --- | --- | --- |
| `Semantic.accent` | Accent *text*, icons, meters, hairlines drawn on the canvas | ≥ 4.5:1 on ink |
| `Semantic.accentFill` | Primary buttons, segmented selection, focus and count badges | white on it ≥ 4.5:1 |

Using the sampled violet for both is the specific mistake this split prevents:
`#543EF5` carries white at 6.16:1, but does not clear the body-text floor as a
small foreground on graphite. Nothing should use a raw violet without first
choosing the foreground or fill role.

`accentStrong` is the pressed state for a filled control. ZenVoice follows the
system appearance instead of forcing Dark Aqua. Semantic AppKit colours provide
the canvas, surfaces, labels, and separators; violet remains the single product
tint in both light and dark appearances.

### Surfaces and Liquid Glass

`canvas` → `surface` → `surfaceRaised` → `surfaceSunken` still communicates
content depth. These are semantic system colours, so increased contrast and
appearance changes do not require a second hard-coded palette.

On macOS 26 and newer, `ZenGlassSurfaceModifier` applies Liquid Glass only to
functional floating layers: toolbar controls, ZenBar, and live preview. Nearby
toolbar controls share `ZenGlassContainer` for one render group. Content cards
remain normal surfaces; applying glass to every card would obscure hierarchy
and waste render time.

macOS 14 and 15 use `ZenMaterialSurface`. Reduce Transparency and Increased
Contrast replace either material with a solid semantic surface. The unified
titlebar remains native, and scrolling content never draws readable labels
through toolbar controls.

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
| `Layout.sidebarWidth` | 248 | Ideal native split-view width; users can resize it from 220–300pt. |
| `Layout.titleBar` | 48 | Reference value for overlays; the main window uses the native unified titlebar. |
| `Layout.navRow` | 44 | Minimum accessible target for custom navigation controls. |
| `Layout.navIcon` | 24 | Stable icon slot outside native `Label` rows. |
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
┌──────────────── unified macOS toolbar ─────────────┐
│ ◫                ● Ready      ⌘      Dictate       │
├──────────────┬─────────────────────────────────────┤
│ ZenVoice     │ [chip]  Preference title            │
│ Overview     │         Supporting context           │
│ Configure    │  [native segmented control]         │
│  Dictation   │  ┌───────────────────────────────┐  │
│  …           │  │ grouped preference content    │  │
│ Activity     │  └───────────────────────────────┘  │
└──────────────┴─────────────────────────────────────┘
  sidebar material              graphite canvas
```

`NavigationSplitView` owns collapse, resize, restoration, and the standard
toolbar sidebar button. The detail pane expands from its live width, so the
motion is interruptible and spatially symmetric.

The sidebar has seven flat destinations with no category headings: Home,
Dictation, Language, Models, Personalisation, History, and Settings. Formatting,
vocabulary, app rules, and commands are peer views inside Personalisation;
transcripts, recordings, and insights are peer views inside History.

Sidebar rows use native `List` spacing and SF Symbols. Selection is a quiet
semantic raised row with a violet icon. The standard toolbar sidebar control
remains visible and exposes “Hide Sidebar” / “Show Sidebar” to accessibility.

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
| `ZenTabStrip` | Native segmented `Picker` for views within a section. |
| `ZenMaterialSurface` | Structural AppKit material with a solid accessibility fallback. |
| `ZenGlassSurfaceModifier` / `ZenGlassContainer` | Versioned Liquid Glass for functional floating controls, with material and solid fallbacks. |
| `ZenMenuPicker` | Shared 44-point menu selector for languages, providers, models, and scopes. |
| `ZenTextInput` | Shared icon-led text field for replacement, vocabulary, model, and endpoint inputs. |
| `ZenPressButtonStyle` | Immediate, interruptible press feedback plus visible keyboard focus and disabled-state contrast for custom controls. |
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

Small interactive state changes use a critically damped spring with response
`0.28`; larger retargetable changes use response `0.35`, also critically
damped. The ZenBar waveform alone uses damping `0.8` because it represents
physical speech energy. Reduce Motion replaces spatial springs with 0.12–0.16s
opacity/color feedback rather than removing feedback entirely.

## Checking the work

```sh
swift build
swift run ZenVoiceCoreChecks
swift run ZenVoiceStorageChecks
swift run ZenVoiceLinkChecks
ZENVOICE_MODEL_PATH=/path/to/model swift run ZenVoiceRuntimeChecks
./Scripts/check-ui-invariants.sh
ZENVOICE_MODEL_PATH=/path/to/model ./Scripts/check-dictation-e2e.sh
```

The gates cover scaffold ownership, compact width, Liquid Glass availability,
permission polling, model/engine selection consistency, process execution,
link ordering and teardown, preview cancellation, and real short-utterance
stop-to-complete latency.
