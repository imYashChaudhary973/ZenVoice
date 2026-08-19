# Agentic Status Streaming — Event Contract

> **Status: implemented — 2026-08-18.** Part of
> [Agentic Command Mode v2](AGENTIC_COMMAND_MODE.md). One event vocabulary
> serves the Mac HUD in v2 and a future iPhone companion unchanged; the iPhone
> would be a consumer of the same envelope, not a second schema. Code:
> `GoalStatusEvent` in `Sources/ZenVoiceCore/AgenticExecution.swift`, emitted by
> `GoalOrchestrator` and rendered by the ZenBar status row. Messages are
> redacted and the per-goal log is capped at 500 events.

## 1. Envelope

Every event is a single JSON object (and the matching `Codable` struct in
`ZenVoiceCore`). Events are **append-only per goal** and **totally ordered**
by `sequence`.

```json
{
  "schemaVersion": 1,
  "goalID": "8F3A…-UUID",
  "sequence": 42,
  "emittedAt": "2026-08-17T15:04:11.282Z",
  "event": "step.output",
  "step": 2,
  "payload": { "…": "event-specific" }
}
```

```swift
public struct GoalStatusEvent: Codable, Equatable, Sendable {
    public var schemaVersion: Int          // 1
    public var goalID: UUID
    public var sequence: Int               // 1-based, gapless, monotonic per goal
    public var emittedAt: Date
    public var event: GoalEventType
    public var step: Int?                  // set for step.* events
    public var payload: GoalEventPayload   // enum over the payloads below
}
```

## 2. Event types

| Event | Payload fields | Emitted when |
|---|---|---|
| `goal.planning` | `transcriptWords: Int` | planner tiers started |
| `goal.plan_ready` | `title`, `stepCount`, `maxComputedRisk` | plan validated, gate prompted |
| `goal.planning_failed` | `reason` (short, no transcript) | planner declined / invalid |
| `goal.awaiting_approval` | `planVersion`, `modeOffered` | approval prompt shown |
| `goal.approved` | `mode`, `coveredSteps` | decision recorded |
| `goal.plan_edited` | `oldVersion`, `newVersion` | plan editor saved; re-validation + re-ask follow |
| `goal.approval_timeout` | — | 10-min expiry |
| `goal.started` | `firstStep` | execution begins |
| `step.started` | `agent`, `risk`, `workingDirectory` | step process spawned |
| `step.output` | `channel: stdout|stderr`, `text` (chunk), `truncated: Bool` | streamed child output |
| `step.waiting_input` | `prompt` | child blocks on stdin (rare; agents run headless) |
| `step.succeeded` | `exitStatus`, `durationMs`, `summaryText?` | exit 0 |
| `step.failed` | `exitStatus`, `durationMs`, `reason: error|timeout` | non-zero / timeout |
| `step.cancelled` | `durationMs`, `partialOutputRetained: Bool` | killed by cancel (distinct from failure — the step did not fail, we stopped it) |
| `step.skipped` | `because: dependency_failed | cancelled` | scheduler skip |
| `goal.step_approval_required` | `step`, `risk`, `commandPreview` | paused before high-risk step |
| `goal.completed` | `stepsSucceeded`, `stepsSkipped`, `durationMs` | all done |
| `goal.failed` | `failedStep`, `stepsRan[]` | halt policy fired |
| `goal.cancelling` | — | cancel pressed; children terminating (emitted immediately, before reap) |
| `goal.cancelled` | `stepsCancelled[]` | cancel completed |
| `goal.interrupted` | `lastKnownStep` | relaunch discovery |
| `goal.notification` | `title`, `body`, `intent: completed|failed|cancelled|approval` | terminal/attention states |

## 3. Sequencing and delivery rules

1. **Ordering:** per goal, `sequence` is assigned by the orchestrator actor
   and is gapless. Consumers may rely on it for resumability.
2. **No cross-goal interleaving on one stream** in v2 (serialized goals);
   the envelope carries `goalID` anyway so a future concurrent scheduler
   needs no schema change.
3. **Coalescing:** `step.output` chunks are coalesced to at most
   **20 events per step per second**; a chunk may merge multiple reads and
   must preserve text order and channel. Byte-exactness is not promised on
   the live stream — the encrypted task record retains the capped exact
   output.
4. **Backpressure:** HUD consumers drop to the latest `step.output` under
   load; nothing in the system blocks execution on UI consumption.
5. **Replay:** a consumer joining late (window closed, future iPhone
   reconnecting) asks for `events(after sequence)` and receives the tail
   from the in-memory ring plus persisted summaries; v2 keeps a 500-event
   in-memory ring per active goal.
6. **Redaction:** events never carry secrets by construction (plans are
   secret-scanned; environment is minimal) and `step.output` text is capped
   at 8 KB per event. Output that matches secret shapes is elided with a
   marker — reusing the validator's secret-scan.

## 4. Mac HUD contract (v2)

- **ZenBar / overlay (compact):** current state icon, goal title, current
  step (`step N of M` + description), last output line, risk chip, Cancel
  button always visible.
- **Expanded panel:** the step list with live per-step state, a scrolling
  tail (last ~200 lines) of the active step's coalesced output, "Open task
  record" link.
- **Notifications:** only the `goal.notification` intent events post
  `UNUserNotificationCenter` notifications (completed / failed / cancelled /
  approval needed — approval-needed is click-to-open-the-sheet, never
  approve-from-banner for high risk).

State → presentation mapping is a pure function of the event stream
(`GoalStatusReducer` in Core, unit-checked): a check feeds a scripted event
sequence and asserts the derived HUD state (title, current step, last line,
cancel visibility).

## 5. iPhone companion contract (future — Cross-Device state)

The same envelope crosses the link unchanged:

```text
Mac orchestrator ──▶ GoalEventBroadcaster ──▶ WebSocket (URLSessionWebSocketTask)
                                                   │  envelope frames, same schemaVersion
                                                   ▼
                                        iPhone status / approval views
Mac terminal events ──▶ APNs push (short: intent + goalID only; the app fetches the tail)
```

- Transport pairing (Bonjour + pinned keys) is a Cross-Device-phase design;
  **this document fixes only the envelope**, so the companion is never
  schema-blocked.
- Approval *decisions* may travel iPhone → Mac for **low/medium** goals
  (already approved classes at goal level); high-risk step approval remains
  Mac-sheet-only in the first companion version (same non-coercion rule).
- Live Activities consume `goal.started…goal.completed` sequences with the
  step counter as the activity's progress value.

## 6. Checks to write (pure, no agents)

- Envelope codability round-trip; unknown-event forward compatibility
  (future `event` strings must not crash old consumers — decode to
  `.unknown(raw)`).
- Reducer: scripted sequences for the four terminal paths + step approval
  pause; coalescing preserves order and respects the 20/s cap.
- Redaction: a payload containing a secret-shaped string is elided.
- Sequence gaplessness under injected concurrency (orchestrator actor test).
