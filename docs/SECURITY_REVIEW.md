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
| Whisper model download | tampered or substituted weights | fixed HTTPS allowlist, revision, size, SHA-256, atomic install, user-only permissions | a newly approved model still requires human provenance and licence review |
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

The current build is appropriate for personal use, development testing, and
open-source contribution. ZenVoice is licensed under the Apache License, Version
2.0. Public distribution is deferred while ZenVoice is refined for internal use;
see [ADR 0004](decisions/0004-internal-use-first-defer-shipping.md). The build
targets macOS 14 or newer, but only the macOS versions recorded in the release
QA record are certified; the deployment target is a floor, not evidence.

There is no account system, subscription, trial mechanism, or remote entitlement
check in the application. Adding any of those would require a new threat review
before implementation.

The privacy statement review and the runtime and model review are current as of
2026-08-02. The application can sign with a Developer ID Application
certificate, Hardened Runtime, and a secure timestamp, with
`com.apple.security.get-task-allow` absent. Any future public release would
require a stapled notarization ticket and completed clean-device plus
release-candidate accessibility QA.

## Phase 5 — Cloud AI Enhancement and auto-updates

Phase 5 introduces the first two components that cross the machine boundary.
Both ship off by default; the updater ships inert entirely.

### Cloud AI Enhancement

The only feature in ZenVoice that can send user content off-device. See
[ADR 0011](decisions/0011-cloud-ai-enhancement.md).

| Concern | Control |
|---|---|
| Unintended activation | Requires an explicit toggle **and** a user-supplied key. Neither alone reaches a network path. |
| Credential storage | Keychain generic password, `WhenUnlockedThisDeviceOnly`. Never `UserDefaults`, never the SQLite vault. Disabling the feature deletes the key. |
| Over-disclosure | Only transcript text and the prompt are sent. Audio, bundle ID, app name, next-dictation context, history, insights, voice profile, and device identifiers are excluded at request-construction time. |
| Transport downgrade | HTTPS enforced in `CloudAIConfiguration.resolvedEndpoint()`, before any request exists, including for custom endpoints. |
| Silent replacement | Results are shown against the original and applied only on explicit accept. |
| Credential leakage into logs | The API key is not a stored property of `CloudAIRequest`; it is supplied only when building the `URLRequest`, so it cannot appear in an `Equatable` value or a debug description. |
| Request reuse | Ephemeral `URLSession`, no cookie storage, no URL cache, cache policy `reloadIgnoringLocalAndRemoteCacheData`. |

**Residual risk, accepted:** once the user opts in, their transcript text is
governed by the chosen provider's retention policy, which ZenVoice cannot
observe or constrain. This is stated in the UI rather than mitigated, because it
is inherent to the feature. There is no ZenVoice-operated proxy, so there is no
ZenVoice-side log of user content.

### Auto-updates

The highest-privilege component in the product: it can replace the application
binary. See [ADR 0012](decisions/0012-auto-updates.md).

| Concern | Control |
|---|---|
| Spoofed feed | Ed25519 signature over canonical manifest bytes, verified against a public key compiled into the app. |
| Tampered manifest | The manifest is decoded from the exact bytes that were verified, never re-encoded from a parsed object. |
| Substituted archive | The signed manifest carries the archive SHA-256; the download is hashed and compared before anything is replaced. |
| Transport downgrade | HTTPS required for the archive and release-notes URLs; a validly signed feed carrying an `http://` URL is still rejected. |
| Downgrade / replay | Updates are offered only when strictly newer than the installed version, so a replayed old feed cannot walk a user back to a vulnerable build. |
| Channel confusion | A stable install rejects beta manifests. Channel selects eligibility; it never relaxes verification. |
| Failure handling | Fail-closed throughout. No warn-and-continue, no user override, no unverified-install fallback. |
| Check-time disclosure | A check sends no install identifier and no user content. |

**Dependency posture:** Sparkle was considered and not adopted. The verification
surface needed is small and CryptoKit provides Ed25519 directly; taking Sparkle
would add a large dependency, a second update UI, and its own historical CVE
surface for features (delta updates, installer scripts) this product does not
want. The trade-off is that ZenVoice owns this code and its defects.

**Residual risk, accepted:** the signing key is a single point of failure for
update delivery. Losing it means no further updates to existing installs;
compromise of it would be a full compromise of the update channel. Key custody
is a release-process control, not a code control, and rotating the compiled-in
public key requires shipping a build signed with the old key first.

### Verification

`ZenVoiceCoreChecks` covers the rejection paths specifically, since a verifier
that accepts valid input is the easy half: tampered manifest, unknown signing
key, absent signature, `http://` archive URL, downgrade, same-version reinstall,
beta-on-stable, disabled-updates, and archive hash mismatch. Cloud AI checks
assert the redaction rule against the encoded request body, so a future change
that starts attaching app identity fails the build rather than shipping.

This Phase 5 review is current as of 2026-08-06. Neither component has had
manual QA against a live provider endpoint or a real signed feed; both remain
open in [Release readiness](RELEASE_READINESS.md).

## Phase 6/v2 — Agentic Command Mode

Reviewed 2026-08-18, at implementation. Agentic Mode deliberately introduces the
largest capability in the product — spawning developer tools that edit files —
so the controls are stated as an explicit chain rather than a summary.

**Trust boundary:** the planner is untrusted input. Both tiers (deterministic
templates and Apple's on-device model) produce a `GoalPlan` that only becomes
executable after `PlanValidator` accepts it. The validator enforces schema
version, ≤12 contiguous step numbers, the closed agent whitelist, acyclic
dependencies referencing earlier steps only, timeouts in 1–7200 s, a
secret-shape scan over title/transcript/commands/paths, and containment of every
working directory inside `~/Developer` **by path components**, so a sibling such
as `~/Developer-escape` is rejected rather than accepted by prefix match. The
planner's self-reported `plannedRisk` is advisory and always overwritten by the
validator's recomputation from the command surface.

**Authorisation:** no step runs without an `ApprovalDecision` bound to the
plan's id, its SHA-256 over canonical (sorted-key) JSON, and its version. An
edited plan becomes a new version and re-enters review, so a decision cannot be
replayed onto changed bytes. Steps recomputed as high risk always require their
own decision — `all`-scope approval is refused outright when the plan contains a
high-risk step. Only an unchanged low-risk step can be remembered, and only when
the user has switched that memory on; the memory key is a digest of the whole
step, so changing one character of a command invalidates it.

**Execution containment:** steps are spawned with `Process` and explicit
argument vectors — never a shell string — except the `shell` agent, which is the
user-approved shell case by definition. The child environment is rebuilt to
`HOME`, `PATH`, `TMPDIR`, `LANG`: no Keychain material and no provider API keys
can reach a child by construction. Each child gets its own process group, so
cancellation and timeout signal `-pid` and escalate to `SIGKILL` after a polled
grace window rather than orphaning grandchildren.

**Data at rest and in the HUD:** plans, decisions, per-step state and captured
output live in the same AES-GCM-sealed vault as transcripts, in `agentic_tasks`
with field-bound authentication context (schema v7). Every event message and
every retained output chunk passes `SecretRedactor` before persistence, retained
output is capped at 5 MB per step and the event log at 500 events per goal.
`ZenVoiceStorageChecks` scans the raw database file for known plaintext markers,
so a future change that stores an agentic plan or its output unencrypted fails
the build.

**Residual risk, accepted:** an approved Codex or Claude step is a delegation to
a separate product with its own credentials and its own network behaviour.
ZenVoice can bound *where* it runs, *what* it was asked, and *when* it is
killed; it cannot bound what that tool then does within those limits. This is
why the feature is off by default, why the plan is shown verbatim before
execution, and why approval is never voice-only.

**Not covered:** no live run against a paid provider was performed as part of
this review. The executor path is exercised end to end with the `shell` agent
(success, non-zero exit, timeout, process-group cancellation, agent mismatch) in
`ZenVoiceCoreChecks`; the Codex and Claude adapters share that code path and
differ only in their verified argument vectors.
