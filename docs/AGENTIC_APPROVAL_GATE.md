# Agentic Approval Gate — Risk Policy and UX

> **Status: future design.** Part of [Agentic Command Mode v2](AGENTIC_COMMAND_MODE.md).
> Extends the non-coercion principle of
> [ADR 0008](decisions/0008-command-mode.md) (first-run approvals for
> AppleScript/shell/URL) to multi-step plans.

## 1. Invariant

**No step executes without a recorded approval decision that names the exact
step(s) approved and the plan version approved.** Everything else in this
document is policy and presentation around that invariant.

## 2. Risk classes

Risk is **computed by the validator from the action surface**
([AGENTIC_PLANNER.md §4](AGENTIC_PLANNER.md)); the planner's self-reported
risk is advisory and ignored. Executors may *raise* (never lower) a step's
class at run time when the observed command surface differs from the plan.

| Class | Definition | Examples | Approval requirement |
|---|---|---|---|
| **Low** | Read-only or report-only; no file, process, or network effects beyond the plan's own output | `git status`, `ls`, "notify me", listing test results | Batchable under one goal-level approval |
| **Medium** | Local writes inside the declared working directory; local builds and test runs | run tests, build, edit files in the project, agent fix steps | Goal-level approval sufficient **if** it is the highest class in the plan |
| **High** | Anything leaving the machine, writing outside the working directory, or irreversible | `git push`, deploy, external API calls, `rm`, sudo, unparseable commands | **Per-step approval** — each high-risk step is confirmed individually, always |

Anything the classifier cannot parse is high. A plan containing a high-risk
step can never be approved "all at once".

## 3. Approval modes and user actions

| Mode / action | Meaning | Availability |
|---|---|---|
| **Approve all** | Approve every remaining step ≤ the plan's highest *approved* class; high-risk steps still require their own confirmation | Only when no high-risk steps exist |
| **Approve up to next high-risk step** | Run through medium steps, then re-ask | Default offer when high-risk steps exist |
| **Approve step-by-step** | Confirm each step before it starts | Always available; forced for high-risk-only plans |
| **Edit plan** | Open the plan editor: edit a command, remove a step, change working directory (edits re-validate + recompute risk; edited plan is a new plan version) | Always, before or instead of approving |
| **Reject** | No execution; plan recorded as rejected; transcript still available as text | Always |
| **Cancel** | Stop a running goal immediately: no new steps start, running children are terminated, partial state recorded | Always, including mid-run |

Defaults: first presentation focuses **Edit plan** for mixed plans (not
Approve); a plan whose steps are all low focuses **Approve all**. Approve is
never focused for a plan containing high risk.

## 4. Mac UI (v2)

### 4.1 Plan approval sheet (primary surface)

```text
┌──────────────────────────────────────────────────────────────┐
│  Goal: Bridgemind — E2E run, fix, notify            Ⓩ Cancel │
│  From: "open bridgemind in codex, run the e2e tests, fix…"   │
├──────────────────────────────────────────────────────────────┤
│  1 ▸ medium   Run E2E tests via Codex                        │
│        cd ~/Developer/bridgemind && codex 'run E2E tests…'   │
│  2 ▸ HIGH     Fix obvious failures            [Approve step] │
│        codex 'fix the obvious failures…'                     │
│  3 ▸ low      Notify when done                               │
├──────────────────────────────────────────────────────────────┤
│  [Edit plan]   [Approve up to next high-risk]   [Reject]     │
└──────────────────────────────────────────────────────────────┘
```

- Risk is a colored chip per step; **HIGH is spelled out, never just a color**.
- Commands are visible in full (expandable), monospace, copyable — no
  truncation of what will run.
- Keyboard: `Esc` = Reject, `⌘.` = Cancel, `⌘E` = Edit plan. Approve
  requires an explicit click/Return on the approve control.

### 4.2 ZenBar / HUD compact form

While awaiting approval for a low/medium-only plan, ZenBar may show a
collapsed form: goal title, step count, highest risk chip, and the same four
actions. High-risk approval **never** happens in the compact form — it opens
the sheet.

### 4.3 Mid-run approval prompt

When a goal-level approval runs into the next high-risk step, execution
pauses in `awaiting_step_approval`, the HUD shows the step, and the sheet
re-presents focused on that step. A paused goal consumes no CPU (no steps
running).

## 5. Decision records

Every decision writes an encrypted record (task store, `ZenVoiceStorage`
vault) at decision time:

```swift
public struct ApprovalDecision: Codable, Equatable, Sendable {
    public var planID: UUID
    public var planSHA256: String     // exact plan bytes approved
    public var mode: ApprovalMode     // approveAll | upToNextHigh | perStep | edit | reject | cancel
    public var stepNumbers: [Int]     // steps covered by this decision
    public var decidedAt: Date
    public var planVersion: Int       // edits bump the version
}
```

Edits create a new version; prior approvals do **not** carry over to
materially changed steps (a changed command re-risks and re-asks). The
hash binding is what makes "I approved exactly this" auditable later.

First-run memory: like v1's `CommandModeApprovalPreferences`, a *low-risk*
command shape the user approved repeatedly may be offered "remember this
command shape" (goal templates). **Never for medium or high.**

## 6. Edge cases

| Case | Behavior |
|---|---|
| Approval timeout (no decision in 10 min) | Goal auto-**cancels** (never auto-approves); notification says so |
| Mac locks while awaiting approval | Same as timeout on unlock+prompt? No — cancellation is NOT triggered by lock; the prompt simply waits; timeout still applies |
| Screen asleep / app hidden | `UNUserNotificationCenter` banner with Reject/Approve for low/medium-only plans (high requires the sheet) |
| Plan edited during a run | Run halts (finish current step, cancel rest); edited plan re-validates and re-asks |
| Executor reports a surface riskier than planned | Step aborts before effect; re-approval required at the higher class |
| Two goals queued | v2 executes one goal at a time; second goal waits in `planning` (serialized by design) |
| App relaunch mid-run | Goal marked `interrupted`; **no auto-resume**; user may re-approve a fresh run of remaining steps |
| Voice "approve" spoken at the prompt | **Ignored in v2** (pinned unknown U4): approval is deliberately non-voice so a mis-transcription can never authorize a high-risk action |
| Power/autonomy loss mid-step | Orchestrator's persisted state shows step `running` at relaunch; recorded as `interrupted`; no re-execution without approval |

## 7. Non-coercion checklist for review

- [ ] No approve-by-default focus on mixed/high plans
- [ ] Cancel visible in every agentic surface (sheet, HUD, menu bar)
- [ ] No countdowns, urgency styling, or repeated re-prompting after Reject
- [ ] High risk requires reading the command (sheet, expanded) — no compact approval
- [ ] Approval decisions are auditable and bound to plan bytes
- [ ] Refusal paths (Reject / timeout / invalid) always preserve the transcript as text
