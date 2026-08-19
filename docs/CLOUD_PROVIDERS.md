# Cloud Providers

> **Status:** Implemented and UI-reachable. **Groq was verified against the
> live endpoint on 2026-08-18** (see §5.1). OpenAI and Anthropic live
> verification is still open — no credentials were provided; their wire
> shapes remain fixture-verified only. This document describes what exists
> in code today, the exact wire shapes each provider uses, and the
> procedure that closes the remaining items. It is written for the coding
> agent (Zcode Harness) implementing changes against
> `Sources/ZenVoiceCore/CloudAIEnhancement.swift`.
>
> Related: [ADR 0011](decisions/0011-cloud-ai-enhancement.md) records the
> privacy decision this feature implements.

## 1. What exists today vs what does not

| Capability | Status |
|---|---|
| Provider enum: OpenAI, Groq, Anthropic, custom endpoint | Done |
| Per-provider request builders with distinct wire shapes | Done |
| Per-provider model pickers (no free-text model IDs for known providers) | Done |
| Keychain key storage (`CloudAIKeyStore`), never `UserDefaults` | Done |
| Preview window before replacing local text (`CloudAIPreviewWindowController`) | Done |
| Never lose the local transcript on dismiss/timeout/error (`CloudTranscriptResolution`) | Done |
| Deterministic checks for request shape and Anthropic shape | Done (`ZenVoiceCoreChecks`) |
| Live verification against real Groq endpoint | **Done 2026-08-18** (`ZenVoiceCloudLiveChecks`, §5.1) |
| Live verification against real OpenAI endpoint | **Open — needs a real API key** (user opted to skip for now) |
| Live verification against real Anthropic endpoint | Open (same reason) |

Everything below marked **Current** describes shipped behavior. Anything else
is explicitly marked **Future**.

## 2. Architecture (Current)

```text
Formatting ladder (mode = cloud)
  → CloudAIViewModel (app layer)
  → CloudAIEnhancementEngine.makeRequest(transcript, configuration)   // pure, no network
  → CloudAIRequest.urlRequest(apiKey:)                                // key applied at send time only
  → CloudAITransport.send(request)                                    // the single network seam
  → firstMessageContent(from: data, provider:)                        // provider-specific parse
  → CloudAIPreviewWindowController  (review before apply; autoApply pref may skip)
  → CloudTranscriptResolution.resolve(local:, accepted:)              // empty result keeps local text
```

Design rules the coding agent must preserve:

1. **Request construction is pure.** `CloudAIRequest.encodedBody()` never
   touches the network, so checks can assert the privacy contract (only
   model + prompt + transcript appear in the body) without a live endpoint.
2. **The API key is applied at send time only** and is never part of an
   `Equatable` value that could be logged or diffed.
3. **One network seam.** `CloudAITransport` is the only protocol ZenVoice
   uses for cloud calls; checks inject a fake. Do not add a second.
4. **The local transcript always survives.** Dismiss, cancel, timeout,
   transport error, provider error, and empty provider result all resolve to
   the exact local text with `didApply: false`.

## 3. Provider matrix (Current)

| | OpenAI | Groq | Anthropic | Custom |
|---|---|---|---|---|
| Default base URL | `https://api.openai.com/v1` | `https://api.groq.com/openai/v1` | `https://api.anthropic.com/v1` | none — user must set one |
| Path | `/chat/completions` | `/chat/completions` | `/messages` | `/chat/completions` |
| Wire shape | Chat Completions | Chat Completions (OpenAI-compatible) | Messages API | Chat Completions |
| Auth header | `Authorization: Bearer <key>` | `Authorization: Bearer <key>` | `x-api-key: <key>` | Bearer |
| Extra headers | — | — | `anthropic-version: 2023-06-01` | — |
| Body extras | `temperature: 0.2` | `temperature: 0.2` | `temperature: 0.2`, `max_tokens: 4096`, top-level `system` | same as OpenAI |
| Known models | `gpt-4o-mini`, `gpt-4o`, `gpt-4.1-mini`, `gpt-4.1` | `openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `groq/compound`, `groq/compound-mini`, `qwen/qwen3.6-27b` | `claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022`, `claude-3-opus-20240229`, `claude-3-7-sonnet-20250219` | open field |

**Custom exists so data can stay on infrastructure the user controls** (for
example a self-hosted OpenAI-compatible endpoint). It has no default URL on
purpose: the user must state where their text is going. `resolvedEndpoint()`
enforces HTTPS for every provider, including custom.

### 3.1 Request bodies

Bodies are encoded with `.sortedKeys`, so the byte-exact body for OpenAI and
Groq is:

```json
{
  "messages": [
    {"role": "system", "content": "<prompt template text>"},
    {"role": "user", "content": "<trimmed transcript>"}
  ],
  "model": "gpt-4o-mini",
  "temperature": 0.2
}
```

Anthropic:

```json
{
  "max_tokens": 4096,
  "messages": [
    {"role": "user", "content": "<trimmed transcript>"}
  ],
  "model": "claude-3-5-haiku-20241022",
  "system": "<prompt template text>",
  "temperature": 0.2
}
```

**Privacy contract, enforced by checks:** the body contains only the model,
the prompt, and the transcript. Never present: audio, app identity or bundle
ID, target application, selected or surrounding text, next-dictation context,
history, voice-profile or correction-rule data, device identifiers, telemetry
fields.

### 3.2 Response parsing

- OpenAI / Groq / custom: `choices[0].message.content` (string). Anything
  else is `malformedResponse`.
- Anthropic: `content[0].text` (string).
- Empty or whitespace-only content is treated as malformed, never as "apply
  an empty transcript" — that is what guarantees the local transcript wins.

### 3.3 Prompt templates

Two built-in templates exist (`CloudAIPromptTemplate`): **Clean up** and
**Tighten**. Both instruct the model to reply with corrected text only, to
preserve meaning, and not to add information. The user can edit the prompt
text in configuration.

## 4. Transport and error handling (Current)

`URLSessionCloudAITransport` uses an **ephemeral** `URLSession`: no cookie
storage, no URL cache, no additional headers. Requests use
`cachePolicy = .reloadIgnoringLocalCacheData`, `httpShouldHandleCookies =
false`, and a 30-second timeout.

`CloudAIEnhancementError` is the complete failure taxonomy:

| Case | Meaning | User effect |
|---|---|---|
| `disabled` | Feature toggle off | Local transcript kept |
| `missingAPIKey` / `missingBaseURL` / `missingModel` | Incomplete configuration | Local transcript kept, settings hint |
| `insecureBaseURL` / `invalidBaseURL` | Non-HTTPS or malformed endpoint | Refused before any bytes leave |
| `emptyTranscript` | Nothing to send | Local transcript kept |
| `transport(message)` | URLSession failure | Local transcript kept |
| `provider(status, message)` | Non-2xx; `error.message` extracted best-effort | Local transcript kept, error surfaced |
| `malformedResponse` | Unparseable/empty body | Local transcript kept |

**Future (Phase 0 close):** the live-verification step below is the missing
piece; no new error cases are expected from it.

## 5. Closing the open item: live endpoint verification

Phase 6 item *"Verify Groq and OpenAI against live endpoints"* (also Anthropic)
needs real API keys, which the coding agent must never fabricate.

The reproducible path is `ZenVoiceCloudLiveChecks` (added 2026-08-18). It
sends one real enhancement per provider through the exact production path —
`makeRequest` → `urlRequest(apiKey:)` → `URLSessionCloudAITransport` →
`firstMessageContent` — and asserts: HTTP 2xx with parseable per-provider
content, the Clean up template changes a deliberately messy transcript, and
a wrong key lands in `provider(status, message)` with a readable message.
The key is read from the production Keychain item the app's Formatting
screen writes; it never touches the command line, the repo, or logs.

```bash
# after storing the provider's key in Formatting → Cloud:
ZENVOICE_CLOUD_LIVE_PROVIDER=groq swift run ZenVoiceCloudLiveChecks
```

### 5.1 Evidence — Groq, verified 2026-08-18

| Check | Result |
|---|---|
| Endpoint | `api.groq.com/openai/v1/chat/completions` |
| Stored key, model `openai/gpt-oss-120b` | HTTP 2xx, parsed in 0.70 s; cleanup changed the transcript |
| Stored key, model `openai/gpt-oss-20b` | HTTP 2xx, parsed in 0.57 s; changed |
| Stored key, model `groq/compound` | HTTP 2xx, parsed in 1.79 s; changed |
| Stored key, model `qwen/qwen3.6-27b` | HTTP 2xx, parsed in 3.47 s; changed |
| Wrong key | `provider(401, "Invalid API Key")` — taxonomy + readable message confirmed |

**Finding fixed en route:** the previous default model
`llama-3.3-70b-versatile` was shut down by Groq on 2026-08-16 (their
deprecation notice names `openai/gpt-oss-120b` as the replacement). The
curated list in `CloudAIProvider.knownModels` was refreshed to live-verified
models, and the stored configuration was migrated off the dead id — every
Cloud refinement would otherwise have failed with 404.

OpenAI and Anthropic remain **credential-blocked** (user opted to skip on
2026-08-18). Their wire shapes stay covered by the deterministic checks in
`ZenVoiceCoreChecks`; run the same command with `openai` or `anthropic`
once a key is stored to close them.

**Do not** spend the user's money without asking; the coaching workflow
requires asking before real API usage.

## 6. Adding or changing a provider (checklist for the coding agent)

1. Extend `CloudAIProvider` with the case; supply `displayName`,
   `defaultBaseURL` (or none), `knownModels`, `endpointPath`, `authHeader`,
   `extraHeaders`, `requestBody`, `extractContent`.
2. Keep the OpenAI-compatible branch as the default shape for anything that
   speaks Chat Completions.
3. Add deterministic checks: request shape (body keys, no private fields) and
   response parse for the new provider, next to the existing
   "Anthropic request shape" checks in `ZenVoiceCoreChecks`.
4. Update this document's matrix.
5. Model lists are **curated at build time**. Refresh them only with a
   verified provider announcement; a stale list must fail closed (user sees
   the picker, not free text) rather than fall back to free-text entry.

## 7. Pinned unknowns

- Model-list freshness cadence (no automated sync exists; intentionally).
- Whether `custom` should also learn the Anthropic shape (Open question —
  current answer: no; custom means OpenAI-compatible self-hosting).
- Streaming responses are not planned for this feature (latency target is
  met by small fast models; streaming would complicate the preview flow).
