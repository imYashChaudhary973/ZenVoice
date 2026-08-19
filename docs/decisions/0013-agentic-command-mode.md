# ADR 0013 — Agentic Command Mode: Approved, Observable Goal Orchestration

## Status

**Accepted and implemented — 2026-08-18.** Phase 6 was closed for gating: Groq
live endpoint verified (with a dead-model fix), all seven installed speech
engines measured on the frozen real-speech corpus, UI audit clean. OpenAI and
Anthropic live checks remain open only because the user chose not to provide
those keys; their wire shapes stay fixture-verified.

Phase 2 landed the whole design set in code — deterministic and on-device
planner tiers, validator, orchestrator, approval gate, status events, `codex`
and `claude` process adapters, encrypted `agentic_tasks` storage (vault schema
v7), settings surface, and the ZenBar status row — with coverage in
`ZenVoiceCoreChecks` (preferences, planner, validator, orchestration lifecycle,
real process executor) and `ZenVoiceStorageChecks` (encrypted round-trip and
plaintext-at-rest scan). The feature ships **off by default**; enabling it
enables Command Mode with it, and every runtime gate reads the effective value
so switching Command Mode off neutralises the agentic path. See
[AGENTIC_COMMAND_MODE.md §8b](../AGENTIC_COMMAND_MODE.md) for the file map and
the deltas from the Phase 1 design.
(Numbered 0013 rather than a requested "0008-agentic…" because ADR 0008 is
Command Mode v1; numbering must stay monotonic.)

## Context

Command Mode v1 ([ADR 0008](0008-command-mode.md)) maps fixed spoken phrases
to single, approval-gated actions. It is deterministic, safe, and deliberately
dumb: it cannot express "open the project, run the tests, fix what fails,
tell me when done" — the shape of work the user actually wants from a
voice-first tool.

The product's stated evolution is a voice-first personal agent. Three facts
from project history shape this decision:

1. **Non-coercion is load-bearing.** v1's first-run approval model for
   AppleScript/shell/URL is the most trusted surface in the product. Any v2
   that weakens it — auto-executing anything novel — destroys the property
   that makes voice control acceptable at all.
2. **A local LLM is not automatically an improvement.** The generative
   refinement experiment measured exactly 0.0 improvement over deterministic
   rules and was removed ([ADR 0007](0007-zenintelligence.md)). Model-driven
   components must earn their tier against a deterministic baseline.
3. **Local-first is the product.** Cloud AI enhancement exists as an
   opt-in transcript feature ([ADR 0011](0011-cloud-ai-enhancement.md)); a
   cloud-based planner that ships every spoken goal off-device would invert
   the privacy promise for the app's most sensitive new capability.

## Decision

Build **Agentic Command Mode v2**: a multi-step goal orchestrator with a
hybrid planner, a risk-based approval gate, a serialized execution state
machine, and a live status event stream.

1. **Hybrid planner, deterministic first.** v1 phrase parser → structured
   goal parser → local LLM (JSON-only). The LLM is the last tier, not the
   front door; its output is untrusted input to a validator that recomputes
   risk from the action surface. ([AGENTIC_PLANNER.md](../AGENTIC_PLANNER.md))
2. **Approval gate with recomputed risk classes.** Low/medium/high; high-risk
   steps require per-step approval; "approve all" exists only for plans with
   no high-risk steps; every decision is recorded bound to the exact plan
   bytes. Approval is deliberately **not** voice-controllable in v2.
   ([AGENTIC_APPROVAL_GATE.md](../AGENTIC_APPROVAL_GATE.md))
3. **Fail-toward-text and fail-toward-halt.** Any planner/validator failure
   returns the transcript as ordinary text (the Cloud AI precedent of never
   losing the local transcript, generalized). Ambiguity asks one clarifying
   question, then declines.
4. **Serialized orchestrator, cancellation always wins.** One goal at a
   time; per-step process groups with SIGTERM→SIGKILL; no auto-resume after
   interruption; every transition persisted to the encrypted task record at
   transition time. ([AGENTIC_ORCHESTRATOR.md](../AGENTIC_ORCHESTRATOR.md))
5. **One status vocabulary, many consumers.** Mac HUD in v2; the future
   iPhone companion consumes the same envelope over WebSocket/APNs without a
   schema change. ([AGENTIC_STATUS_STREAMING.md](../AGENTIC_STATUS_STREAMING.md))
6. **Planning stays local.** No cloud planner exists in v2 or is planned.
   The only network in the agentic path is what an approved executor step
   itself does (for example a `git push` the user per-step approved).
7. **Agents are CLIs we spawn, not services we host.** Codex CLI, Claude
   Code, shell, Shortcuts, notifications — `Process`-spawned, minimal
   environment, no secrets injection, streamed output, hard timeouts.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Grow the v1 phrase manifest (more phrases, optional arguments) | Combinatorial explosion; phrases cannot express dependencies or multi-step goals; every phrase is a new safety review |
| Cloud planner (GPT/Claude API) for quality | Every spoken goal — including drafts the user abandons — leaves the device; contradicts ADR 0001/0011 posture for the most sensitive feature; also adds latency and cost |
| Apple Shortcuts as the entire orchestration layer | Cannot host coding agents; approval UX is Apple's, not enforceable per-risk; no live output streaming contract |
| Auto-execute low-risk steps with no gate at all | Violates non-coercion; "low risk" is a classifier output, and classifiers are exactly the thing this design refuses to trust |
| Agent-owns-everything (spawn one long-lived agent with the goal) | Unobservable and uncancellable mid-flight; the approval gate would approve a black box; violates the attribution and cancellation invariants |
| Voice-only approval ("computer, confirm") | A mis-transcription or synthesized-voice risk authorizes effects; approval must be a deliberate non-voice interaction (pinned unknown U4, revisit only via a new ADR) |

## Consequences

**Positive**

- The user's actual daily shape of request becomes speakable.
- Every effect is attributable to a hash-bound approval; the audit trail is
  encrypted and local.
- The planner tiers give deterministic latency for common goals and
  model-quality for the rest, with a measured upgrade path (the exact lesson
  of ADR 0007 applied at design time).
- The event envelope makes the iPhone companion a consumer, not a redesign.

**Negative / accepted costs**

- A local planner model (3B+) must ship and be governed by the verified
  catalogue; disk and memory cost are real until proven worth it.
- Serialized goals: a long-running agent goal blocks the next goal; accepted
  for v2 (predictability beats throughput at personal scale).
- No undo: the orchestrator halts and reports; it does not revert agent
  edits. The approval UI says so plainly.
- More UI surface to keep non-coercive; the approval doc ships a review
  checklist precisely because this erodes by accident, not on purpose.

## Privacy impact

- Goal transcripts, plans, decisions, and outputs live only in the encrypted
  task store on the Mac.
- The local planner receives the transcript and nothing else — no app
  context, history, or profile data.
- Executors receive only their own step command and working directory, in a
  minimal environment without keychain material.
- The only egress in the agentic path is caused by approved steps themselves
  (high-risk class), each individually approved and recorded.
- The iPhone link (future phase) carries the same envelope over pinned-key
  WebSocket; APNs messages carry intent + ID, not content.

## References

- Master design: [AGENTIC_COMMAND_MODE.md](../AGENTIC_COMMAND_MODE.md)
- Precedents: [ADR 0007](0007-zenintelligence.md) (measured LLM removal),
  [ADR 0008](0008-command-mode.md) (v1 approval model),
  [ADR 0011](0011-cloud-ai-enhancement.md) (transcript-survival pattern),
  [ADR 0001](0001-local-data-and-model-governance.md) (local-first posture)
