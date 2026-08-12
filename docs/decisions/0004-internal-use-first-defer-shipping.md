# ADR 0004: Internal-Use-First and Deferred Public Shipping

- Status: Accepted
- Date: 2026-08-06

## Context

ZenVoice has reached a functional personal-dictation state: local transcription,
encrypted history, multilingual profiles, application profiles, a verified
model catalogue, a `whisper.cpp` runtime, onboarding, and release tooling are all
implemented. The project also has a complete public-distribution checklist
(Developer ID signing, notarization, clean-device QA, accessibility QA, and a
GitHub Releases workflow).

However, the product has not yet been used broadly enough to confidently ship
a public release. The founder/team's priority is to make ZenVoice the best
daily dictation tool for their own workflows before inviting external users.
Shipping introduces support surface, trust expectations, and release-maintenance
overhead that are not justified until the product is meaningfully better through
regular personal use.

## Decision

- ZenVoice is now **internal-use-first**. The immediate goal is to make it the
  best possible personal dictation tool for the people building it.
- **Public shipping is deferred.** Signed, notarized distribution, a private
  beta programme, Homebrew cask availability, and GitHub Releases publishing are
  not current goals. They remain prepared but inactive.
- Quality, reliability, latency, language accuracy, and daily workflow fit are
  the active priorities. Distribution readiness is maintained as a future option,
  not a near-term target.
- The repository stays public and open-source under the Apache License, Version
  2.0. Contributions are still welcome, but there is no release timeline.

## Consequences

- Engineering milestones continue in the order defined by
  `docs/BUILD_ORDER.md`, but M17 (onboarding, accessibility, privacy dashboard,
  and release polish) is no longer blocked by signing or notarization. Manual
  QA and accessibility work still matter for daily use, but they do not have to
  be completed as a release gate.
- `docs/RELEASE_READINESS.md` remains the single source of truth for what must
  be done before any future public distribution, but its unchecked items are
  now explicitly deferred rather than urgent blockers.
- The private-beta guide has been retired: the programme is paused while
  ZenVoice is refined for internal use, and a paused programme needs a decision
  record rather than an invitation process.
- Security and privacy reviews continue to be valuable for protecting the
  developer's own data, not only for future users.
- No source code, build scripts, CI workflows, or signing configuration are
  removed; they remain ready for a future shipping decision.
- A future decision will be required to reactivate shipping. That decision
  should review this ADR, the current `docs/RELEASE_READINESS.md` checklist,
  and the state of personal-use evidence.
