# Product

## Register

product

## Platform

macOS

Native SwiftUI/AppKit app (macOS 14+). No web surface; the impeccable
web-only tooling does not apply. Product-register rules govern.

## Users

A developer or heavy keyboard user at the end of the day: terminal and
editor already open, room light low, dictating into whichever window has
focus. Reaches for the ZenBar via hotkey dozens of times a day and opens
the settings window rarely, to check status or change one thing. Secondary:
a privacy-conscious writer who chose ZenVoice because nothing leaves the
Mac; same interface, less frequent use.

## Product Purpose

Private, local-first voice dictation for macOS. Speak naturally, transcribe
on-device with whisper.cpp, paste into any app. Success: dictation is faster
than typing for this user, the transcript is trusted as-is, and nothing —
audio, text, or telemetry — ever leaves the machine.

## Positioning

Your voice never leaves your Mac — every screen reinforces that this is a
local instrument, not a cloud service.

## Brand Personality

Calm, precise, quietly luxurious. An instrument, not a dashboard: antique
brass on ink, the spoken word rendered like print. Never chatty, never
alarming, never bright.

## Anti-references

- Cloud-SaaS settings pages: blue/purple gradients, hero-metric cards,
  glass panels.
- Terminal-hacker aesthetic: saturated green-on-black, scanlines, glow.
- Linear/Raycast clones: cool graphite + electric accent, the default
  "good dark tool" look (that was ZenVoice v2).
- Cream/warm-paper light UI — irrelevant here; the redesign is dark-only.

## Design Principles

1. **Voice is the only green.** Green appears exclusively when the mic is
   live or a transcript is being produced. If it's green, it's listening.
2. **Brass marks affordance.** Selection, primary actions, focus, and the
   active destination carry the mark's metal. Colour is information, never
   decoration.
3. **Your words become print.** Transcript text is the typographic hero of
   the product — dictated output is set like editorial text, not like form
   data.
4. **Structure from hairlines and value steps.** No shadows, no glass. A
   dense settings window stays legible through 1px edges and surface value.
5. **Built for end-of-day eyes.** Dark-only, never flashes bright, motion
   is quick and state-driven, Reduce Motion respected everywhere.

## Accessibility & Inclusion

- WCAG AA-equivalent contrast discipline: body and placeholder text ≥4.5:1
  on every surface they appear on; large text and UI glyphs ≥3:1.
- Reduce Motion honoured (helpers return `nil`; the waveform is the only
  element with a spring).
- Full keyboard path: ⌘K command palette, focus rings on every custom
  control, 44pt hit targets under compact painted controls.
- VoiceOver labels on all icon-only controls; status announced, not just
  shown.
- Dark appearance is the only appearance; the app forces it and never
  renders light chrome, including overlays and ZenBar.
