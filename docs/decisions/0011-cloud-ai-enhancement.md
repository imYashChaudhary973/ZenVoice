# ADR 0011 — Cloud AI Enhancement: Optional Off-Device Post-Processing

## Status

Accepted — Phase 5 implemented, shipped off by default.

## Context

Every transcript path in ZenVoice up to this point is local. Instant Refine is
deterministic, ZenIntelligence runs on-device, and no application code opens a
network connection for transcription or refinement. That is the product's
central promise.

Some cleanup tasks are genuinely better served by a large hosted model than by
deterministic rules — restructuring a rambling paragraph, or rewriting to a
tone. Phase 5 adds **Cloud AI Enhancement** for those cases.

This is the first feature that can send user content off the Mac, so it is the
first real trust-boundary change in the product. The design problem is not
"how do we call an API" — it is how to add the capability without weakening the
guarantee for the overwhelming majority of users who will never turn it on.

## Decision

Cloud AI Enhancement is opt-in, bring-your-own-key, and narrow by construction.

1. **Off by default, and inert until fully configured.** The feature requires an
   explicit toggle *and* a user-supplied API key. Absent either, no network code
   path is reachable.
2. **Bring your own key.** ZenVoice operates no proxy and holds no vendor
   account. Requests go from the user's Mac to the provider the user chose,
   authenticated with the user's own key. There is no ZenVoice server in the
   path, so there is nothing for us to log.
3. **The key lives in the Keychain**, never in `UserDefaults` and never in the
   SQLite vault, using the same generic-password pattern as the transcript
   encryption key. Turning the feature off deletes the key.
4. **Only the transcript and the prompt are sent.** Explicitly *not* sent: audio,
   the target application's identity or bundle ID, surrounding or selected text,
   the next-dictation context, history, insights, voice-profile data, correction
   rules, or any device identifier. This is enforced at the point where the
   request body is built, not by convention.
5. **A single narrow transport.** All network access goes through one small,
   auditable type with one method, one HTTP verb, and one destination — the
   configured chat-completions endpoint. It sets no cookies, follows no
   redirects to other hosts, and carries no custom telemetry headers.
6. **HTTPS only.** A non-HTTPS base URL is rejected before any request is made,
   including for custom providers.
7. **The user sees the result before it lands.** Enhanced text is presented as a
   preview against the original; the transcript is only replaced on acceptance.
   A failed or rejected request leaves the local transcript untouched.
8. **Providers**: OpenAI-compatible, Groq, or a custom base URL plus model name.
   All three use the same request shape; "custom" exists so the user can point at
   a self-hosted or local endpoint and keep the data on their own infrastructure.

## Consequences

- The default install is unchanged: no network path, no key, no prompt.
- A user who opts in accepts a real and clearly-stated trade-off — their
  transcript text goes to a third party under their own account and that
  provider's retention policy, which ZenVoice cannot control or promise anything
  about. The UI says this plainly rather than burying it.
- Because there is no ZenVoice-operated proxy, we cannot add server-side
  features later without revisiting this ADR.
- The preview step costs an interaction. That is deliberate: silently replacing
  local text with the output of a remote model is exactly the surprise this
  feature must not produce.
- Provider outages or rate limits degrade to "enhancement unavailable, keep the
  local transcript" rather than to a failed dictation.

## Implementation notes

- `Sources/ZenVoiceCore/CloudAIEnhancement.swift` — providers, configuration,
  prompt templates, and request construction. Request building is pure and
  therefore directly testable without a network.
- `CloudAITransport` is a protocol; the URLSession implementation is the only
  place that touches the network, and checks inject a fake.
- `CloudAIKeyStore` wraps the Keychain item.
- Checks assert the redaction rule in point 4 by inspecting the encoded request
  body, so a future edit that starts attaching app identity fails the build.

## Privacy

- Nothing is sent unless the user has both enabled the feature and supplied a key.
- Only transcript text and the prompt leave the Mac.
- The API key is stored in the Keychain and deleted when the feature is disabled.
- Exact data flows are recorded in `docs/PRIVACY.md`.

## Related decisions

- ADR 0001 — Local data and model governance
- ADR 0004 — Internal-use-first, defer shipping
- ADR 0007 — ZenIntelligence (the on-device counterpart)
- `docs/PHASE_5.md`
