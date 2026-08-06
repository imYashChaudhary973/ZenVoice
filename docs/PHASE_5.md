# Phase 5 — Distribution & Cloud Opt-In

**Status:** Code deliverables complete — Cloud AI Enhancement and the signed-feed
updater are implemented, `swift build` and all check suites pass. Section 3
(distribution gates) is **blocked**, not skipped: it needs Developer ID signing,
notarization, clean-device QA, and the outstanding pricing decision. Manual QA
against a live provider endpoint and a real signed feed is also open.

**Goal:** Prepare the optional updater and cloud-AI enhancement paths, and complete any remaining release gates if a future shipping decision is made.

**Outcome:** ZenVoice has an opt-in auto-updater, an opt-in cloud AI Enhancement feature, and a documented path to public distribution. None of this is activated while ZenVoice remains internal-use-first.

## Deliverables

1. ADR for optional cloud AI enhancement
2. ADR for auto-updates and beta channel
3. Optional cloud AI Enhancement (OpenAI, Groq, custom provider)
4. Optional auto-updater with beta channel
5. Updated release readiness checklist execution
6. Hardened update verification and signing checks

## Why this phase is last

- These features introduce network calls, external trust boundaries, and distribution concerns.
- They are the only requested features that can send data off the Mac.
- Public shipping is deferred per [ADR 0004](decisions/0004-internal-use-first-defer-shipping.md); this phase builds the pieces without turning them on.

## Detailed tasks

### 1. Cloud AI Enhancement

- [x] Write `docs/decisions/0011-cloud-ai-enhancement.md`.
- [x] Define the privacy model explicitly:
  - Off by default.
  - User must add their own API key for the provider.
  - Only the transcript text is sent; never audio, never app identity, never surrounding context.
  - No batching with other users; each request is isolated.
- [x] Create `Sources/ZenVoiceCore/CloudAIEnhancement.swift`.
- [x] Support providers:
  - OpenAI-compatible API
  - Groq API
  - Custom base URL + model name + API key
- [x] Add a prompt template system for “clean up this transcript” and user-defined prompts.
- [x] Add a diff/preview before applying the enhanced text.
- [x] Network requests go through a narrow, auditable client.
- [x] Update `docs/PRIVACY.md` with exact data flows.

### 2. Auto-Updates

- [x] Write `docs/decisions/0012-auto-updates.md`.
- [x] Evaluate update frameworks:
  - Sparkle (native, widely used)
  - Squirrel (Electron-based, less relevant)
  - A custom lightweight feed checker plus manual download
- [x] Implement an opt-in updater:
  - Check feed signed with the project’s Ed25519 key or Developer ID signature.
  - Download only over HTTPS.
  - Verify the downloaded archive’s signature and hash before replacing the app.
  - Beta channel toggle.
- [x] Add settings UI:
  - Check automatically / manually
  - Beta channel opt-in
  - Last check timestamp
- [x] Keep the updater disabled until public shipping is approved.

### 3. Distribution gates (when shipping is reconsidered)

- [ ] **Blocked** — complete the deferred items from `docs/RELEASE_READINESS.md`.
  Needs a Developer ID signing run, notarization credentials, a clean Mac, and
  the pricing decision. None of these are code work:
  - Developer ID Application signing
  - Hardened Runtime
  - `notarytool` submission and stapling
  - Clean-device Microphone/Accessibility QA
  - Completed `docs/RELEASE_QA_RECORD.md`
- [ ] **Blocked** — run `./Scripts/check-release-readiness.sh` and resolve any
  new `BLOCK` items. 4 gates remain, all in this section.
- [ ] **Blocked** — update `CHANGELOG.md` with the shipped version (there is no
  shipped version yet).

### 4. Security and trust

- [x] Cloud AI keys are stored in Keychain, not UserDefaults.
- [x] Update feed signature verification is fail-closed: if verification fails, the update is rejected.
- [x] Add a security review section for cloud AI and auto-updates.

### 5. Verification

- [x] Unit tests for update feed signature verification.
- [ ] Manual QA (not yet run — needs a live provider endpoint and a real
  signed feed):
  - Cloud AI Enhancement cleans a transcript using a test provider endpoint.
  - API key is stored securely.
  - Opt-out removes the key and stops network calls.
  - Auto-update checks a signed feed and handles a beta-channel toggle.
- [x] `swift build` and all checks pass.

## Dependencies

- Phase 1–4 complete.
- A chosen update framework or custom implementation.
- API key management for cloud providers.
- Developer ID certificate and notarization credentials if public shipping proceeds.

## Out of scope

- Shipping to the public (requires a separate product decision per ADR 0004).
- Removing local-first defaults.

## Success criteria

- Cloud AI Enhancement is fully opt-in and auditable.
- Auto-updater is opt-in, verifies signatures, and can be disabled.
- All release-readiness gates are either complete or explicitly deferred with rationale.
- No local-first behavior is weakened by default.

## What is implemented

- `Sources/ZenVoiceCore/CloudAIEnhancement.swift` — providers, configuration,
  prompt templates, pure request construction, and the single narrow transport.
- `Sources/ZenVoiceCore/CloudAIKeyStore.swift` — Keychain-backed key storage
  plus the persisted configuration (which never holds the key).
- `Sources/ZenVoiceCore/UpdateFeed.swift` — manifest, channel, strict version
  parsing, and updater preferences.
- `Sources/ZenVoiceCore/UpdateVerifier.swift` — Ed25519 verification, HTTPS and
  channel enforcement, downgrade rejection, and archive hash binding.
- `Sources/ZenVoice/Screens/CloudAIScreen.swift` and `UpdatesScreen.swift`,
  with `CloudAIViewModel`.
- Checks in `ZenVoiceCoreChecks` covering the rejection paths and the request
  redaction rule.

## What is deliberately not done

Section 3 and the manual QA in section 5 are not code tasks. They require a
Developer ID signing run, notarization credentials, a clean Mac for install QA,
a live provider endpoint, a real signed release feed, and the pricing decision
that gates public distribution. They are left unchecked rather than marked done.
