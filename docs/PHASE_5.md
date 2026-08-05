# Phase 5 — Distribution & Cloud Opt-In

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

- [ ] Write `docs/decisions/0009-cloud-ai-enhancement.md`.
- [ ] Define the privacy model explicitly:
  - Off by default.
  - User must add their own API key for the provider.
  - Only the transcript text is sent; never audio, never app identity, never surrounding context.
  - No batching with other users; each request is isolated.
- [ ] Create `Sources/ZenVoiceCore/CloudAIEnhancement.swift`.
- [ ] Support providers:
  - OpenAI-compatible API
  - Groq API
  - Custom base URL + model name + API key
- [ ] Add a prompt template system for “clean up this transcript” and user-defined prompts.
- [ ] Add a diff/preview before applying the enhanced text.
- [ ] Network requests go through a narrow, auditable client.
- [ ] Update `docs/PRIVACY.md` with exact data flows.

### 2. Auto-Updates

- [ ] Write `docs/decisions/0010-auto-updates.md`.
- [ ] Evaluate update frameworks:
  - Sparkle (native, widely used)
  - Squirrel (Electron-based, less relevant)
  - A custom lightweight feed checker plus manual download
- [ ] Implement an opt-in updater:
  - Check feed signed with the project’s Ed25519 key or Developer ID signature.
  - Download only over HTTPS.
  - Verify the downloaded archive’s signature and hash before replacing the app.
  - Beta channel toggle.
- [ ] Add settings UI:
  - Check automatically / manually
  - Beta channel opt-in
  - Last check timestamp
- [ ] Keep the updater disabled until public shipping is approved.

### 3. Distribution gates (when shipping is reconsidered)

- [ ] Complete the deferred items from `docs/RELEASE_READINESS.md`:
  - Developer ID Application signing
  - Hardened Runtime
  - `notarytool` submission and stapling
  - Clean-device Microphone/Accessibility QA
  - Completed `docs/RELEASE_QA_RECORD.md`
- [ ] Run `./Scripts/check-release-readiness.sh` and resolve any new `BLOCK` items.
- [ ] Update `CHANGELOG.md` with the shipped version.

### 4. Security and trust

- [ ] Cloud AI keys are stored in Keychain, not UserDefaults.
- [ ] Update feed signature verification is fail-closed: if verification fails, the update is rejected.
- [ ] Add a security review section for cloud AI and auto-updates.

### 5. Verification

- [ ] Unit tests for update feed signature verification.
- [ ] Manual QA:
  - Cloud AI Enhancement cleans a transcript using a test provider endpoint.
  - API key is stored securely.
  - Opt-out removes the key and stops network calls.
  - Auto-update checks a signed feed and handles a beta-channel toggle.
- [ ] `swift build` and all checks pass.

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
