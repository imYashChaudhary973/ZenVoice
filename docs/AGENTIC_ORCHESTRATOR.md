# Agentic Orchestrator — Execution State Machine

> **Status: implemented — 2026-08-18.** Part of
> [Agentic Command Mode v2](AGENTIC_COMMAND_MODE.md). The orchestrator owns
> execution after an approval exists; it produces the events defined in
> [AGENTIC_STATUS_STREAMING.md](AGENTIC_STATUS_STREAMING.md) and persists state
> through the encrypted task store. Code:
> `Sources/ZenVoiceCore/GoalOrchestrator.swift` with the process adapters in
> `AgenticExecutors.swift`; relaunch marks non-terminal records `interrupted`
> and never resumes a process.

## 1. Model overview

One `GoalOrchestrator` instance per goal; a session-level `GoalQueue`
serializes goals. **One goal is active at a time, end to end**: a queued
goal stays in `idle` — its planning does not start until it becomes active
(predictability beats throughput at personal scale, and it keeps the
planner model's warm/idle policy trivial). The orchestrator is an actor; all
state transitions happen inside it.

```swift
// Sketch of the model surface (interfaces for the coding agent, not code to paste)

public enum GoalState: String, Codable, Sendable {
    case idle                      // constructed, planning not started
    case planning                  // planner tiers running
    case planningFailed            // planner could not produce a plan
    case awaitingApproval          // plan validated, gate is asking
    case approvalTimedOut          // no decision within 10 min (terminal → cancelled)
    case rejected                  // user rejected (terminal)
    case running                   // ≥ 1 step executing or runnable
    case awaitingStepApproval      // paused before a high-risk step
    case cancelling                // stop signal sent, children terminating
    case cancelled                 // terminal
    case completed                 // all steps succeeded (terminal)
    case failed                    // a step failed and policy halted (terminal)
    case interrupted               // app died / relaunched mid-run (terminal, resumable by fresh approval)
}

public enum StepState: String, Codable, Sendable {
    case pending, running, awaitingApproval
    case succeeded, failed, skipped, cancelled, interrupted
    // waitingInput is an event, not a state: a child blocking on stdin stays
    // `running` (headless agents should never block; the timeout reaps it).
}
```

## 2. State machine

```text
                    ┌─────────────────────────────────────────────┐
                    │                                             │
  idle ──▶ planning ──▶ planningFailed (terminal: offer text)     │
              │                                             │    │
              ▼                                             ▼    │
      awaitingApproval ──reject──▶ rejected           (timeout)──┘
              │  ▲                                   approvalTimedOut
              │  └──── edit plan (re-plan/revalidate, same state)
              │
        approve(all|upToNextHigh|perStep)
              │
              ▼
          running ◀────────────────────────────┐
        │  │  │  │                             │ next step runnable
   step done│  │step fails                     │
        │  │  └─▶ failed (policy: halt)        │
        │  └────▶ next high-risk step ─▶ awaitingStepApproval
        │                     │ approve step ──┘        │ reject/cancel
        │                     ▼                         ▼
        │              (back to running)           cancelling/cancelled
        ▼
   all steps succeeded ─▶ completed

  any pre-terminal state ──cancel──▶ cancelling ──▶ cancelled
  process death mid-run ──relaunch──▶ interrupted
```

### 2.1 Transition table

| From | Event | To | Side effects |
|---|---|---|---|
| idle | `start(transcript)` | planning | planner tiers invoked |
| planning | plan validated | awaitingApproval | plan persisted; gate prompt shown; 10-min timer |
| planning | planner decline/invalid | planningFailed | transcript offered as text; reason surfaced |
| awaitingApproval | approve (any mode) | running | approval decision recorded; first step starts |
| awaitingApproval | reject | rejected | decision recorded |
| awaitingApproval | timer expiry | approvalTimedOut | notification; goal terminal (≡ cancelled) |
| awaitingApproval / running | edit plan | re-plan (stays awaitingApproval on new version) | run halts after current step; new version re-validated |
| running | step exit 0 | (running) → next step or completed | step record written |
| running | step exit ≠ 0 | failed **or** (running) if plan declares `continue` | see §4 |
| running | next step is high-risk | awaitingStepApproval | no child running while waiting |
| awaitingStepApproval | approve step | running | decision recorded |
| awaitingStepApproval | reject step | cancelled | remaining steps skipped, recorded |
| any active | cancel | cancelling | SIGTERM→SIGKILL to children; no new steps |
| cancelling | children reaped | cancelled | partial state persisted |
| process death | relaunch detection | interrupted | store shows last known step states |

## 3. Step execution

### 3.1 Scheduling

- Steps run in **topological order of `dependsOn`**, **serially** in v2.
  Parallel-ready plans are allowed by the schema but the scheduler
  serializes — simpler to reason about, easier to cancel, and no goal needs
  parallelism to feel fast.
- A step with a failed dependency is `skipped` (recorded, not silent).

### 3.2 Spawning executors (app layer; `ZenVoiceCore` holds only protocols)

```swift
public protocol GoalExecutor: Sendable {
    var agent: GoalAgent { get }
    /// Launch the step. Streamed output and termination are delivered via the
    /// event sink. The executor must honor cancellation cooperatively.
    func run(_ step: GoalStep, events: StatusEventSink) async throws -> ExecutorOutcome
}
```

Rules:

- `Process` spawns with a **process group** so cancellation can reap the
  whole tree (`setsid`-equivalent via `preExec` behavior on macOS:
  `Process` + `SIGTERM` to `-pgid`).
- Environment: a **minimal copy** — `PATH`, `HOME`, `TMPDIR`, and the
  terminal essentials. Never the user's full shell environment, never
  keychain material. No secrets injection exists in v2.
- Working directory: the step's validated absolute path; executor refuses a
  missing directory (step fails cleanly, no auto-creation).
- stdout/stderr: streamed as `step.output` events with **coalescing**
  (§ STATUS doc) and a hard cap per step (default 5 MB retained; beyond it,
  counts + a truncation marker).
- Timeouts: per-step `timeoutSeconds` (defaults: shell 600, codex/claude
  3600, shortcut 300, notification 10). Timeout kills the group and marks
  the step failed with `timedOut`.

### 3.3 Agent adapters (pinned unknown U3 — prototype before freezing)

| Agent | Invocation sketch (to verify against real CLIs) |
|---|---|
| `shell` | `Process`, `/bin/zsh -c <command>`, cwd as above |
| `codex` | `codex exec --json <prompt>` in cwd (headless mode; flags to confirm) |
| `claude` | `claude -p <prompt> --output-format json` in cwd (flags to confirm) |
| `shortcut` | `shortcuts run <name>` (reuse v1 wiring) |
| `notification` | `UNUserNotificationCenter` (no Process) |

Adapters translate agent-specific output into the same
`ExecutorOutcome { exitStatus, summaryText, artifactsHint }` so the state
machine never special-cases an agent.

## 4. Failure handling

- Per-step failure policy comes from the plan (validator default: **halt**).
  `continue` is only permitted for steps whose failure cannot corrupt a
  dependent (validator enforces: a `continue` step must be a dependency of
  nothing that writes).
- **No automatic retries** of medium/high-risk steps. A failed low-risk
  read-only step may be retried once (same approval covers it: idempotent
  reads only).
- No compensation/undo in v2. The honest model is: halt and show state;
  undoing agent edits is a coding-agent capability, not an orchestrator
  promise. The plan approval UI shows "no undo" for medium/high steps.
- Failure surfaces: `step.failed` event + goal `failed` with a summary of
  which steps ran, which were skipped, and where output text lives
  (encrypted task record).

## 5. Cancellation

1. Transition to `cancelling`; emit `goal.cancelling` immediately (the HUD
   must reflect the press before children are reaped — termination can take
   up to 5 s); scheduler stops starting steps immediately.
2. `SIGTERM` to each child process group; after 5 s, `SIGKILL`.
3. Steps not started → `skipped(cancelled)`; running step → `cancelled` with
   partial output retained (`step.cancelled` event).
4. Persist, emit `goal.cancelled`, notify.
5. Cancel is **idempotent** — pressing it N times is safe, and it is
   available in every non-terminal state (the one UI invariant from the
   approval gate doc).

- Every state transition and step outcome is written to the encrypted task
  record (`ZenVoiceStorage` vault) **at transition time**, not at goal end —
  crash-consistency is the point.
- Record shape: plan (with version chain), approval decisions, per-step
  outcome + retained output (capped), terminal state, timestamps.
- Relaunch: goals found in `running`/`awaitingApproval`/`awaitingStepApproval`
  become `interrupted` and are shown in History → Goals with a re-run
  (fresh approval) affordance. **Never auto-resume.**
- Retention follows the History retention setting; agentic records are
  transcripts-adjacent data and inherit its encryption and deletion story.

## 7. What the coding agent builds first

1. `GoalState`/`StepState` + transition function as pure `ZenVoiceCore` code
   with a full transition-table check (every legal transition exercised,
   every illegal one rejected).
2. `GoalOrchestrator` with the `shell` executor and a **fake** codex/claude
   executor (scripted outcomes) — end-to-end 3-step goal, dependency skip,
   failure halt, cancel mid-step, timeout — all under `ZenVoiceCoreChecks`
   semantics (deterministic, no network, no real agents).
3. Only then: real adapters, behind manual QA with the real CLIs.

## 8. Pinned unknowns

| # | Question | Default |
|---|---|---|
| O1 | Exact headless flags/exit-code contracts for codex & claude | prototype-driven (U3 in master doc) |
| O2 | Output retention cap vs user expectation for long agent runs | 5 MB/step, knob later |
| O3 | Whether `shortcuts` output can stream (it is effectively batch) | treat as batch, single completion event |
| O4 | macOS notification actions (Approve from banner) availability per OS version | ship without; add opportunistically |
