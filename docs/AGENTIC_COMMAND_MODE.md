# Agentic Command Mode (v2) — Master Design

> **Status: Phase 2 implemented — 2026-08-18.** The planner, validator,
> orchestrator, approval gate, status contract, process adapters, encrypted
> task store, settings surface, and ZenBar HUD row all exist in `Sources/` and
> are covered by `ZenVoiceCoreChecks` and `ZenVoiceStorageChecks`. Agentic Mode
> ships **off by default** and, when switched on, enables Command Mode with it:
> the agentic path is only reached after the deterministic v1 phrase parser
> declines. Command Mode **v1** remains current and unchanged
> ([ADR 0008](decisions/0008-command-mode.md)); v2 extends it and does not
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
| 2. Smart Local Formatting (system LLM behind the meaning guard) | **current on macOS 26+; deterministic fallback elsewhere** |
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
  → Approval Gate (risk-based; risk computed by the PlanValidator)   [AGENTIC_APPROVAL_GATE]
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
Phase 0 (close Phase 6) — DONE 2026-08-18: Groq verified live (model
  catalogue refreshed after Groq shut down the previous default on
  2026-08-16; OpenAI/Anthropic live checks deferred by user choice), all
  seven engines baselined on the frozen real-speech corpus, UI audit clean.
  └─ Phase 1 (this document set) — COMPLETE 2026-08-18.
       └─ Phase 2 (implementation) — COMPLETE 2026-08-18, in this order:
            1. GoalPlan schema + validator + checks (pure Core, no execution)
            2. Orchestrator state machine with real process executor
            3. Approval gate UI (mac) + decision records
            4. Status streaming to ZenBar
            5. codex / claude executor adapters
            6. On-device planner tier behind the deterministic tier
```

Rationale: every step is testable without the next; schema-first prevents
the LLM tail wagging the system; the shell executor proves the whole loop
before any coding-agent integration.

## 8a. Phase 1 exit checklist — verified against the implementation

- [x] Cross-doc types line up: `PlanApprovalProposal` (planner) vs
      `ApprovalAction` (decision records) are distinct types with distinct
      value sets
- [x] Every `GoalState`/`StepState` maps to a status event, and every event
      maps to a state or is declared event-only
- [x] Tier 1 templates emit only whitelisted agents (`open -a` shell step,
      no phantom launch agent)
- [x] Risk recomputation is attributed to the validator everywhere; the
      planner's `plannedRisk` is advisory and overwritten
- [x] Queue semantics: one active goal end to end; queued goals sit at
      `idle`, not `planning`
- [x] Cancel is visible immediately (`goal.cancelling`) and idempotent;
      `step.cancelled` is distinct from `step.failed`
- [x] Fail-toward-text paths exist for every planner/validator failure mode
- [x] Non-coercion checklist in the approval-gate doc still holds
- [x] No secret can enter any event, record, or environment by construction
      (validator secret scan, `SecretRedactor` on every message and retained
      chunk, minimal child environment with no provider keys)

## 8b. What exists in code (2026-08-18)

| Piece | File |
|---|---|
| Plan and step schema, agent whitelist, risk levels | `Sources/ZenVoiceCore/AgenticPlanner.swift` |
| Validation, risk recomputation, path and secret policy | `Sources/ZenVoiceCore/PlanValidator.swift` |
| Preferences, states, events, decisions, redaction, plan digest | `Sources/ZenVoiceCore/AgenticExecution.swift` |
| Deterministic planner tier (Tier 1) | `Sources/ZenVoiceCore/GoalPlanner.swift` |
| On-device planner tier (Tier 2) | `Sources/ZenVoiceCore/FoundationModelsGoalPlanner.swift` |
| Orchestrator, queue, approval flow, low-risk memory | `Sources/ZenVoiceCore/GoalOrchestrator.swift` |
| `codex` / `claude` / shell / shortcut process adapters | `Sources/ZenVoiceCore/AgenticExecutors.swift` |
| Encrypted `agentic_tasks` store (schema v7) | `Sources/ZenVoiceStorage/DictationVault.swift` |
| Planning, approval, status coordination, notifications | `Sources/ZenVoice/AgenticModeCoordinator.swift` |
| Approval and step-approval panel | `Sources/ZenVoice/AgenticApprovalWindowController.swift` |
| Settings surface (Commands → Agentic Mode) | `Sources/ZenVoice/Screens/AgenticModeScreen.swift` |
| Live status row and Stop control | `Sources/ZenVoice/ZenBarView.swift` |
| Router from transcript to plan, fail-toward-text | `Sources/ZenVoice/AppDelegate.swift` |
| Checks | `Sources/ZenVoiceCoreChecks/AgenticChecks.swift`, `Sources/ZenVoiceStorageChecks/main.swift` |

### Deltas from the Phase 1 design

- `GoalPlan` gained an `id: UUID`. Approval records bind to plan id **and**
  SHA-256 **and** version, so a decision cannot be replayed onto an edited or
  different plan.
- Verified CLI contracts (U3 closed): `codex exec --json --ephemeral --sandbox
  workspace-write --approve-for-me --skip-git-repo-check --cd <dir> <prompt>`
  and `claude --print --verbose --output-format stream-json --permission-mode
  acceptEdits --no-session-persistence <prompt>`.
- Cancellation signals the child **process group** (`kill(-pid, SIGTERM)` after
  `setpgid`), then escalates to `SIGKILL` after a polled five-second grace
  window rather than a flat sleep, so the HUD reports `cancelled` as soon as
  the tree is gone.
- Retained step output is capped at 5 MB per step (tail kept) and the event log
  at 500 events per goal; every event message and retained chunk passes through
  `SecretRedactor` before it is persisted.
- Enabling Agentic Mode enables Command Mode with it, and every runtime gate
  reads `AgenticModePreferences.isEffectivelyEnabled()`, so switching Command
  Mode off neutralises the agentic path without a second write.
- Relaunch marks any non-terminal record `interrupted` and never resumes a
  process (U-part of the orchestrator contract, now enforced in code).
- Agentic records encode dates as seconds since 1970, not milliseconds: the
  milliseconds strategy multiplies on write and divides on read, which is not
  exactly reversible, so a reloaded plan stopped hashing equal to the one the
  user approved. A storage check now pins the digest across the round trip.

## 9. Pinned unknowns — resolutions

| # | Question | Resolution |
|---|---|---|
| U1 | Local LLM runtime for the planner | **Closed:** Apple `FoundationModels` / `SystemLanguageModel` via `FoundationModelsGoalPlanningModel`; the deterministic tier answers first and is also the fallback when the system model is unavailable |
| U2 | Planner model | **Closed:** the OS-managed `SystemLanguageModel`; no app-selected weights, no separate download |
| U3 | Codex / Claude Code headless invocation contract | **Closed:** flags verified against the installed CLIs and pinned in `AgenticExecutors.swift` (see §8b deltas); exit status is the step outcome, stdout/stderr stream to the HUD |
| U4 | Whether voice-only approval ("confirm") is ever allowed | **No for v2** — approval stays a deliberate non-voice interaction; revisit with an explicit ADR |
| U5 | Working-directory policy for agent steps before Project-Aware Agent exists | **Closed:** the validator requires a path contained in `~/Developer` by path components, so a sibling such as `~/Developer-escape` is rejected rather than prefix-matched |
| U6 | Retention period for encrypted task records | Open: follows History retention settings; a separate knob is still deferred |
