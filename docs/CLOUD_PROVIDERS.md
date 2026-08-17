# Cloud Providers

> **Status:** Implemented and UI-reachable; **live endpoint verification is the
> one open Phase 6 item** (requires real API keys). This document describes
> what exists in code today, the exact wire shapes each provider uses, and the
> procedure that closes the open item. It is written for the coding agent
> (Zcode Harness) implementing changes against
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
| Live verification against real OpenAI/Groq endpoints | **Not done — needs real API keys** |
| Live verification against real Anthropic endpoint | Not done (same reason) |

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
| Known models | `gpt-4o-mini`, `gpt-4o`, `gpt-4.1-mini`, `gpt-4.1` | `llama-3.3-70b-versatile`, `llama-3.1-8b-instant`, `mixtral-8x7b-32768`, `gemma2-9b-it` | `claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022`, `claude-3-opus-20240229`, `claude-3-7-sonnet-20250219` | open field |

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
needs real API keys, which the coding agent must never fabricate. Procedure
for the human-assisted run:

1. **Ask the user** for a test key per provider (or ask them to paste keys
   into the app's Formatting screen directly — keys never belong in the repo
   or on the command line).
2. Configure Formatting → Cloud with provider, default model, Clean up
   template; store the key.
3. Dictate or paste a non-sensitive two-sentence transcript and run one
   enhancement per provider.
4. Record, per provider: HTTP success, enhanced text differs from input,
   dismiss-keeps-local behavior, wrong-key produces `provider(status,…)`
   with a readable message.
5. Delete the keys afterwards (turning the feature off deletes the key).
6. Record results in the Phase 6 doc and mark the item complete.

**Do not** automate step 1–2 or spend the user's money without asking; the
coaching workflow requires asking before real API usage.

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
