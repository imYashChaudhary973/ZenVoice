# M9 Security Review

Status: implementation review complete; public release remains blocked by the
manual gates in [Release Readiness](RELEASE_READINESS.md).

This is an engineering review, not a claim that ZenVoice is vulnerability-free.
Automated checks and Semgrep supplement code review; they do not replace
permission, privacy, signing, or release testing.

## Protected assets

- microphone recordings and recoverable failure audio;
- transcript history and correction phrases;
- the Keychain-protected vault key;
- clipboard contents and synthetic paste permission;
- downloaded model files and the embedded runtime;
- code-signing identity and future notarization credentials.

## Trust boundaries and controls

| Boundary | Primary risk | Current control | Residual risk |
| --- | --- | --- | --- |
| Microphone → temporary WAV | sensitive audio survives unexpectedly | cancellation cleanup, successful cleanup, private Application Support recovery, capture-bounded 24-hour expiry | forced termination can leave an OS temporary file when recovery is disabled |
| Transcript → SQLite | plaintext disclosure or record swapping | AES-GCM, Keychain key, record-and-field authenticated data | an unlocked local account can open ZenVoice and view decrypted history |
| Transcript → clipboard | another process reads dictated text | explicit clipboard fallback documented; no background upload | clipboard remains outside ZenVoice until another app replaces it |
| Accessibility paste | synthetic events affect the wrong target | paste only after an explicit dictation lifecycle; denial falls back to copy | focus can change before insertion |
| Model download | tampered or substituted weights | fixed HTTPS allowlist, revision, size, SHA-256, atomic install, user-only permissions | a newly approved model still requires human provenance and licence review |
| Runtime dependency | compromised binary framework | fixed release URL and SwiftPM checksum; embedded framework signed with the app | upstream binary is trusted after checksum and source review, not reproduced locally |
| Developer model override | unreviewed local model | opt-in environment override; weights are treated as data, not executable code | developer mode bypasses catalogue verification |
| Share card | transcript or app identity disclosure | numeric-only type, local renderer, exact preview, explicit destination choice | the user can still share a card intentionally |
| Release pipeline | altered automation or leaked signing material | read-only workflow permissions, pinned checkout commit, no signing credentials in CI | public signing/notarization is not yet configured |

## Automated gates

- deterministic core, storage, runtime, packaging, and nested-signature checks
  run in macOS CI;
- Semgrep Community Edition scans Swift and supporting files on pull requests
  and `main`;
- workflow permissions are `contents: read`;
- the release-readiness script rejects missing notices, ZenVoice licensing,
  a non-Developer-ID signature, an unstapled app, secrets found in tracked
  files, or unfinished manual checklist items.

## Review conclusions

No cloud transcription, analytics endpoint, account system, remote sync,
automatic publishing, or updater is present. Those are intentionally outside
M9 and require a new threat review before implementation.

The current build is appropriate for private development testing. ZenVoice is
proprietary software, direct download is the selected channel, and the first
distributed build is an invitation-only private beta for Apple Silicon Macs
running macOS 14 or newer. It is not approved even for that beta because the
final privacy statements and post-M9 runtime/model review are incomplete, the
app is not signed with a Developer ID Application certificate, no notarization
ticket is stapled, and clean-device plus release-candidate accessibility QA
remain unfinished. Public pricing and launch terms remain a later decision.
