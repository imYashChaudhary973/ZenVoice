# ZenVoice — Product Context

## What it is
Private, local-first voice dictation for macOS. Speak anywhere, transcribe on-device,
insert into the active app. No accounts, no cloud, no analytics.

## Register
`product` — design serves the task. The benchmark is Wispr Flow / Raycast / Linear:
calm, dense where useful, invisible when working.

## Platform
This directory is the **HTML/CSS/JS interactive prototype** of the redesigned macOS app.
It is the visual + UX contract for the SwiftUI rebuild. Target platforms after macOS:
Windows, then iOS/Android — so the design system must not depend on mac-only chrome.

## Audience
- Primary: the founder (personal daily driver, alpha testing).
- Next: privacy-conscious professionals who dictate into email, docs, chat, and code.

## Voice & tone
Plain language, privacy-forward, zero marketing fluff inside the app.
Every claim is specific ("Processing stays local", "SHA-256 verified"), never vague.

## Non-negotiable feature inventory (nothing may be dropped)
1. Global dictation shortcut (default ⌃⌥Space), paste-last (⌃⌥V), private dictation (⌃⌥P)
2. Hold-to-dictate with modifier choice
3. ZenBar HUD: ready / listening / processing / success / error + live waveform,
   cancel & finish controls, stable phrase preview, optional status message,
   Reduce Motion aware
4. Encrypted local history: search, copy, retry, delete, partial transcripts
5. Recovery Inbox for failed / partial dictations
6. Highlight cards: preview, Save, macOS Share
7. Insights: words, weighted WPM, streaks, apps, work categories
8. Voice Profile: recurring phrases, encrypted correction rules, pause rules,
   pause pattern analysis, delete rules independently
9. Verified model catalog: English + multilingual, pinned revisions, SHA-256,
   size, download % with cancel, hardware-aware Fast/Balanced/High-Accuracy
   recommendations from local timing samples
10. Languages: English-safe profiles, 64 languages, auto-detect, Hinglish
    (Latin script) + native-script + local English-translation modes
11. Audio: follow system default or pin a mic, safe disconnect, 3-second
    on-device Audio Doctor (signal + format)
12. Instant Refine: Off / Clean / Agent Prompt / Local Model; Fast & Balanced
    Qwen downloads (Apache-2.0, revision, size, SHA-256); grammar-constrained
    JSON, 5-second deadline, no-invention guard, deterministic Clean fallback;
    guarded commit-on-pause (opt-in, locked to origin app)
13. Per-application profiles: language, refinement, voice-command overrides
14. One-shot context box (memory-only, clears on next recording)
15. Voice layout & punctuation commands, English + Hindi/Spanish/French/
    Mandarin/Arabic aliases
16. Privacy: live inventory (transcripts, recovery audio, rules, models),
    pause history, private dictation, permission status, deletion controls
17. First-run onboarding (upgrade-safe) — redesigned as a true first-launch
    journey, never a sheet over the working app
18. Help & FAQ — new surface: searchable FAQs, shortcut cheat-sheet, replay setup
19. Light + dark appearance
20. Accessibility: contrast ≥ 4.5:1, focus states, reduced motion, AT labels

## Known UX debts being fixed in this redesign
- Setup guide currently opens as a sheet on top of settings tabs → becomes a
  dedicated first-run flow + replayable from Help.
- 10 flat sidebar tabs → grouped navigation with Home and Help & FAQ.
- No FAQ / self-serve help surface → added.
