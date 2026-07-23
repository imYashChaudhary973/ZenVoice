# ZenVoice Build Order

This document records the approved implementation sequence. Each milestone must
pass its verification gate before dependent work begins.

| Milestone | Scope | Status |
| --- | --- | --- |
| M0 | Approve privacy, licensing, and metric definitions | Complete |
| M1 | Encrypted local vault and crash recovery | Complete |
| M2 | History UI, partial recovery, privacy shortcut, and hold-to-dictate | Complete |
| M3 | Verified model catalogue and downloader | Planned |
| M4 | Hardware recommendations and model benchmarks | Planned |
| M5 | Bundled persistent `whisper.cpp` runtime | Planned |
| M6 | Local insights and application categories | Planned |
| M7 | Usage-based voice profile and explicit corrections | Planned |
| M8 | Privacy-safe shareable highlight cards | Planned |
| M9 | Public-distribution legal and security review | Planned |

## Delivery rules

- Work proceeds in milestone order.
- Each milestone receives a focused commit and verification evidence.
- Pull requests group only milestones that form one reviewable vertical slice.
- Model downloads remain blocked until the M3 catalogue verifies publisher,
  source, licence, checksum, format, and compatibility.
- Analytics remain blocked until M1 provides durable and correctly migrated
  records.
- Public distribution remains blocked until M9 is complete.

## Pull request sequence

1. **Local Vault and History:** M0, M1, and M2.
2. **Verified Local Models:** M3, M4, and M5.
3. **Local Insights:** M6 and M7.
4. **Sharing and Release Readiness:** M8 and M9.
