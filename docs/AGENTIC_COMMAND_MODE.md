# Agentic Command Mode (v2) — Master Design

> **Status: future design. Nothing in this document is implemented.**
> Command Mode **v1** is current and deterministic
> ([ADR 0008](decisions/0008-command-mode.md)); v2 extends it and must not
> break a single v1 phrase behavior. This is the master document; the four
> component designs are:
>
> - [AGENTIC_PLANNER.md](AGENTIC_PLANNER.md) — transcript → validated plan
> - [AGENTIC_APPROVAL_GATE.md](AGENTIC_APPROVAL_GATE.md) — risk policy and UX
> - [AGENTIC_ORCHESTRATOR.md](AGENTIC_ORCHESTRATOR.md) — execution state machine
> - [AGENTIC_STATUS_STREAMING.md](AGENTIC_STATUS_STREAMING.md) — live status contract
>
> The decision record is [ADR 0013](decisions/0013-agentic-command-mode.md).

## 1. Goal

Let the user speak a multi-step natural-language goal and have ZenVoice turn
it into an **explicitly approved, observable, cancellable** plan executed by
local tools and coding agents:

> "Open Codex in the Bridgemind project, run the E2E tests, fix the obvious
> failures, and notify me when done."

— becomes a 3-step plan the user approves once, watches live, and gets a
notification for. Planning and orchestration stay **local**; no cloud is
required at any point in v2.

## 2. Non-goals (v2)

- No background listening for goals — invocation is always the deliberate
  dictation act, same as v1.
- No autonomous scheduling, no "while I sleep" execution.
- No cloud planner. A hosted planner contradicts the trust model
  ([ADR 0001](decisions/0001-local-data-and-model-governance.md)); the
  existing opt-in Cloud AI enhancement stays a separate, transcript-only
  feature.
- No auto-execution of anything beyond v1's no-approval set. Everything new
  passes the approval gate.
- No iPhone app in v2 (the status event schema is designed so a later
  companion consumes it unchanged — Cross-Device Orchestrator state).

## 3. Position in the evolution

| State | Status |
|---|---|
| 1. Passive Dictation | current |
| 2. Smart Local Formatting (local LLM behind the meaning guard) | future (Phase 2 work) |
| 3. Command Mode v1 (deterministic) | **current** |
| 4. **Agentic Command Mode v2 (this document)** | **design phase** |
| 5. Project-Aware Agent | future |
| 6. Cross-Device Orchestrator | future |
| 7. Proactive Assistant | future |
| 8. Fully Offline Agentic Mode | v2 is designed to already satisfy this for planning/execution |

## 4. End-to-end flow

```text
Hotkey / hold-to-dictate (deliberate act)
  → AudioRecorder (16 kHz mono)
  → selected SpeechEngine (unchanged multi-engine path)
  → TranscriptCleaner (unchanged)
  → CommandRouter                              [new, thin]
  │   1. v1 CommandModeEngine phrase match?    → v1 execution (fast path, unchanged)
  │   2. Agentic Mode enabled + goal-shaped?   → Planner
  │   3. otherwise                             → normal text insertion (unchanged)
  → Planner (structured parser → local LLM fallback)      [AGENTIC_PLANNER]
  → Plan validation (schema + whitelists + lint)
  → Approval Gate (risk-based; risk computed by orchestrator)   [AGENTIC_APPROVAL_GATE]
  → Orchestrator state machine runs steps       [AGENTIC_ORCHESTRATOR]
       ├─ executors: codex | claude | shell | shortcut | notification
       └─ status events → Mac HUD (v2), iPhone (future)  [AGENTIC_STATUS_STREAMING]
  → completion notification + encrypted task record
```

**Ordering rule:** v1 phrase matching runs first and wins ties. Agentic mode
never intercepts a phrase v1 already resolves. If agentic mode is disabled
(default), the router is literally the v1 path plus text insertion.

## 5. Components

| Component | Owns | Module home |
|---|---|---|
| `CommandRouter` | v1-first dispatch, goal detection | `ZenVoiceCore` |
| `AgenticPlanner` | transcript → `GoalPlan` (hybrid tiers) | `ZenVoiceCore` (parsing) + `ZenVoiceRuntime` (LLM runtime) |
| `PlanValidator` | schema, agent whitelist, dependency lint, risk recomputation | `ZenVoiceCore` |
| `ApprovalGate` | risk policy, approval UI model, decision records | `ZenVoiceCore` (policy) + `ZenVoice` (UI) |
| `GoalOrchestrator` | state machine, process spawning, cancellation, persistence | `ZenVoice` (process) + `ZenVoiceCore` (model) |
| Executors | codex / claude / shell / shortcut / notification adapters | `ZenVoice` (imp), protocols in `ZenVoiceCore` |
| Status stream | event construction and fan-out | `ZenVoiceCore` (schema) + `ZenVoice` (HUD) |
| Task store | encrypted records of plans, decisions, outputs | `ZenVoiceStorage` (vault reuse) |

Module rule (matches existing architecture): **`ZenVoiceCore` never spawns
processes and never touches the network.** Executors are protocols in Core
with app-layer implementations, exactly like `CommandModeExecutor` today.

## 6. Trust model

1. **The planner is untrusted.** Whatever produced a plan — regex parser or
   local LLM — its output is validated against a fixed schema, agents are
   whitelist-checked, dependencies are linted, and **risk is recomputed by
   the orchestrator from the action surface**, never taken from the plan
   text.
2. **Approval is the only path to execution.** Risk classes and approval
   modes are defined in the approval-gate doc; the invariant is: *no new
   effect on the system occurs without a recorded approval decision*.
3. **Effects are attributable.** Every plan, approval decision, spawned
   process, exit status, and output chunk is written to the encrypted task
   record at the time it happens.
4. **Cancellation is always available and always wins.** Cancel halts new
   step starts immediately, terminates running children, and records partial
   state. There is no state in which cancel is unavailable.
5. **Data boundary.** Goal transcripts, plans, and outputs stay on the Mac
   in encrypted storage. Executors receive only their own step's command and
   working directory. The local planner model receives the transcript and
   nothing else. Nothing about other applications, history, or the voice
   profile is attached.
6. **Non-coercive UI.** Approve is never the default focused action for a
   plan containing medium/high-risk steps; Reject and Cancel are always one
   action away; no countdowns, no nagging, no pre-checked "don't ask again"
   for high risk.

## 7. Failure philosophy

- **Fail toward text.** If anything in the agentic path errors — planner
  timeout, unparseable plan, validator rejection — the transcript is offered
  as normal inserted text. Agentic failure must never lose the user's words
  (same principle as `CloudTranscriptResolution`).
- **Fail toward halt.** Ambiguous plans ask a clarifying question or return
  to text; they are never "best-effort" executed.
- **One change at a time.** v1 behavior is protected by its existing checks;
  the router is additive and covered by a check proving phrase commands
  still resolve identically with agentic mode on and off.

## 8. Dependencies and sequencing for implementation

```text
Phase 0 (close Phase 6: live cloud verification, per-engine baselines)
  └─ Phase 1 (these documents) — no agentic code before this set is reviewed
       └─ Implementation order:
            1. GoalPlan schema + validator + checks (pure Core, no execution)
            2. Orchestrator state machine with shell executor + fake agents
            3. Approval gate UI (mac) + decision records
            4. Status streaming to ZenBar/HUD
            5. codex / claude executor adapters
            6. Local-LLM planner tier (after Smart-rung runtime decision)
```

Rationale: every step is testable without the next; schema-first prevents
the LLM tail wagging the system; the shell executor proves the whole loop
before any coding-agent integration.

## 9. Pinned unknowns (must be decided before or during implementation)

| # | Question | Default assumption |
|---|---|---|
| U1 | Local LLM runtime for the planner (MLX vs llama.cpp C API) | llama.cpp C API, matching the whisper.cpp integration pattern; decided in the Smart-rung work |
| U2 | Planner model (Llama 3.2 3B vs 8B vs Qwen) | 3B first; plan quality measured before 8B ships |
| U3 | Codex / Claude Code headless invocation contract (flags, exit codes, machine-readable output) | prototype on real CLIs before the adapter spec is frozen |
| U4 | Whether voice-only approval ("confirm") is ever allowed | **No for v2** — approval is a deliberate non-voice interaction; revisit with an explicit ADR |
| U5 | Working-directory policy for agent steps before Project-Aware Agent exists | plan must name an absolute path inside `~/Developer` or the step is rejected |
| U6 | Retention period for encrypted task records | follow History retention settings; separate knob deferred |
