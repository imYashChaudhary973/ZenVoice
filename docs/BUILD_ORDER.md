# ZenVoice Build Order

This document records the approved implementation sequence. Each milestone must
pass its verification gate before dependent work begins.

| Milestone | Scope | Status |
| --- | --- | --- |
| M0 | Approve privacy, licensing, and metric definitions | Complete |
| M1 | Encrypted local vault and crash recovery | Complete |
| M2 | History UI, partial recovery, privacy shortcut, and hold-to-dictate | Complete |
| M3 | Verified model catalogue and downloader | Complete |
| M4 | Hardware recommendations and model benchmarks | Complete |
| M5 | Bundled persistent `whisper.cpp` runtime | Complete |
| M6 | Local insights and application categories | Complete |
| M7 | Usage-based voice profile and explicit corrections | Complete |
| M8 | Privacy-safe shareable highlight cards | Complete |
| M9 | Public-distribution legal and security review | Implemented; release gates pending |
| M10 | Instant Refine foundation and reliable model downloads | Complete |
| M11 | Explicit language profiles, Hinglish, translation, and 50+ languages | Implemented; real-microphone QA pending |
| M12 | Microphone selection, disconnection recovery, and Audio Doctor | Implemented; hardware-disconnect QA pending |
| M13 | Stable live transcript preview and commit-on-pause | Implemented; spoken-flow QA pending |
| M14 | Curated downloadable local refinement models | Implemented; broader language QA pending |
| M15 | Application profiles, context box, and local voice commands | Implemented; cross-app spoken QA pending |
| M16 | Correction Review, local learning controls, and Recovery Inbox | Planned |
| M17 | Onboarding, accessibility, privacy dashboard, and release polish | Planned |

## Delivery rules

- Work proceeds in milestone order.
- Each milestone receives a focused commit and verification evidence.
- Pull requests group only milestones that form one reviewable vertical slice.
- Model downloads remain blocked until the M3 catalogue verifies publisher,
  source, licence, checksum, format, and compatibility.
- Analytics remain blocked until M1 provides durable and correctly migrated
  records.
- Public distribution remains blocked until every M9 manual release gate is
  evidenced and approved.

## Pull request sequence

1. **Local Vault and History:** M0, M1, and M2.
2. **Verified Local Models:** M3, M4, and M5.
3. **Local Insights:** M6 and M7.
4. **Sharing and Release Readiness:** M8 and M9.
5. **Instant Refine Foundation:** M10.
6. **Multilingual Foundation:** M11.
7. **Daily Reliability:** M12 and M13.
8. **Context-aware Local Intelligence:** M14, M15, and M16.
9. **Release Experience:** M17.
