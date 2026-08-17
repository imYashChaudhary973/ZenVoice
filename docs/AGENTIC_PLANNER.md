# Agentic Planner — Design

> **Status: future design.** Part of [Agentic Command Mode v2](AGENTIC_COMMAND_MODE.md).
> Audience: the coding agent implementing it. Nothing here is built.

## 1. Requirement

Turn one dictated sentence (or a few) into a **validated `GoalPlan`** — a
typed, whitelisted, dependency-ordered structure — or a typed refusal. The
planner never executes anything, never prompts the user on its own, and its
output is untrusted input to the validator.

Latency budget: **≤ 2 s** from transcript to validated plan on the reference
Mac (M-series, planner model resident). If a tier cannot meet it, the next
tier answers.

## 2. Architecture: three tiers, cheapest first

```text
transcript
  → Tier 0  v1 phrase parser (CommandModeEngine)          — exact matches only
  → Tier 1  structured goal parser (deterministic)        — common goal shapes
  → Tier 2  local LLM planner (JSON mode)                 — everything else
  → PlanValidator                                          — same for all tiers
```

### 2.1 Tier 0 — v1 phrase parser (exists)

Unchanged. "Open safari" must keep resolving identically forever. The router
tries this first; agentic tiers never see transcripts that v1 resolves.

### 2.2 Tier 1 — structured goal parser (deterministic, new)

Covers the goal shapes that make up most daily use, with zero model latency
and zero hallucination surface. Recognized shapes in v1 of this tier:

| Shape | Example | Produced plan |
|---|---|---|
| `open <app> [and] <verb-phrase>` | "open bridgemind and run the tests" | launchApp + shell/codex step |
| `<imperative> in/on <known project>` | "run e2e tests in bridgemind" | one agent step with resolved cwd |
| `notify me when <condition>` (as a step) | "…and notify me when done" | notification step depending on all prior |
| `ask me before <anything>` | any plan | forces step approval mode |

Rules: templates match on normalized transcripts (the same normalization
`CommandModeEngine` applies); unknown tokens end the match — **no partial
guesses**. A shape that does not consume the whole goal falls through to
Tier 2.

### 2.3 Tier 2 — local LLM planner (new)

A small instruct model running on-device, prompted for **JSON only**, parsed
strictly. Runtime choice (pinned unknown U1 in the master doc) is shared
with the Smart-rung local model work so one runtime serves both. Prompt:

```text
You are ZenVoice Planner, a local goal parser running on the user's Mac.
Convert the voice command into a structured JSON plan.

Rules:
- agent must be one of: codex, claude, shell, shortcut, notification
- command must be a complete, runnable instruction for that agent
- depends_on lists step numbers this step needs finished first
- risk is your estimate only; the system recomputes it
- at most 12 steps; if the goal needs more, return needs_clarification
- if the goal is ambiguous or asks for anything outside the agent list,
  return needs_clarification with one short question
- never include secrets, passwords, or API keys in any field
- respond with JSON only, no prose

User command:
"{{TRANSCRIPT}}"

JSON shape:
{
  "result": "plan" | "needs_clarification" | "not_a_goal",
  "title": "short title",
  "steps": [
    {
      "step": 1,
      "agent": "codex",
      "command": "cd ~/Developer/bridgemind && codex 'run E2E tests and report failures'",
      "description": "Run E2E tests in Bridgemind via Codex",
      "depends_on": [],
      "risk": "medium"
    }
  ],
  "clarifying_question": "only when result is needs_clarification"
}
```

`not_a_goal` is a valid answer: it routes the transcript back to normal text
insertion. **The planner is allowed to decline.**

### 2.4 Why hybrid (and not pure LLM)

- The measured precedent in this codebase: a local LLM added **0.0** WER
  improvement over deterministic formatting rules, and was removed (see
  [ADR 0007](decisions/0007-zenintelligence.md) and the formatting history).
  Deterministic-first is the house style until a model *proves* its tier.
- Reliability: Tier 1 answers the majority of goals with zero failure modes.
- Latency and memory: Tier 2 needs a resident 3B+ model; it must not be on
  the critical path for goals Tier 1 already answers.
- Privacy: Tier 1 is pure text processing — no model input at all.

## 3. `GoalPlan` schema (v1)

Versioned, `Codable`, stable field names — this is a persistence format.

```swift
public struct GoalPlan: Codable, Equatable, Sendable {
    public var schemaVersion: Int          // == 1
    public var title: String               // ≤ 80 chars, non-empty
    public var createdAt: Date
    public var transcript: String          // verbatim source
    public var steps: [GoalStep]           // 1...12, step numbers 1...n unique
    public var approvalMode: ApprovalMode  // proposed by planner, decided by gate
}

public struct GoalStep: Codable, Equatable, Sendable {
    public var number: Int                 // 1-based, unique
    public var agent: GoalAgent            // codex | claude | shell | shortcut | notification
    public var command: String             // ≤ 2000 chars, non-empty
    public var description: String         // ≤ 200 chars, human-readable
    public var workingDirectory: String?   // absolute, must exist, inside ~/Developer (U5)
    public var dependsOn: [Int]            // subset of other step numbers; acyclic
    public var plannedRisk: RiskLevel      // planner's guess — advisory only
    public var computedRisk: RiskLevel     // set by validator; the one that counts
    public var timeoutSeconds: Int         // default per agent; capped
}
```

JSON example — "open bridgemind in codex, run the e2e tests, fix the obvious
failures, and notify me when done":

```json
{
  "schemaVersion": 1,
  "title": "Bridgemind: E2E test run + fix + notify",
  "steps": [
    {"number": 1, "agent": "codex", "command": "cd ~/Developer/bridgemind && codex 'run E2E tests and report failures'", "description": "Run E2E tests via Codex", "workingDirectory": "~/Developer/bridgemind", "dependsOn": [], "plannedRisk": "medium", "computedRisk": "medium", "timeoutSeconds": 900},
    {"number": 2, "agent": "codex", "command": "codex 'fix the obvious failures reported by the last test run'", "description": "Fix obvious failures", "workingDirectory": "~/Developer/bridgemind", "dependsOn": [1], "plannedRisk": "high", "computedRisk": "high", "timeoutSeconds": 1800},
    {"number": 3, "agent": "notification", "command": "Bridgemind E2E run finished", "description": "Notify when done", "dependsOn": [1, 2], "plannedRisk": "low", "computedRisk": "low", "timeoutSeconds": 10}
  ]
}
```

## 4. PlanValidator (all tiers pass through this)

Ordered gates; first failure rejects the plan (→ transcript falls back to
text, with a one-line reason surfaced):

1. **Schema:** decodes as `GoalPlan`; version supported; limits respected
   (steps ≤ 12, strings within caps, step numbers contiguous 1…n).
2. **Agent whitelist:** every `agent` is a known executor. Unknown agent →
   reject (never "run as shell" fallback).
3. **Risk recomputation:** `computedRisk` is derived from the **action
   surface**, overwriting `plannedRisk`:
   - `notification`, read-only commands (`ls`, `cat`, `git status`, `npm
     test` without writes) → low
   - file-editing agents, builds, test runs → medium
   - `git push`, deploys, network calls, `rm`, anything writing outside the
     working directory, any command the classifier cannot parse → **high**
   - Unparseable command → high, always.
4. **Dependency lint:** references valid, acyclic (topological sort
   succeeds), notification steps must depend on ≥ 1 step or be the only step.
5. **Path policy:** `workingDirectory` (after `~` expansion) exists and is
     inside `~/Developer` (U5); plan-supplied paths outside it reject the step.
6. **Secret scan:** any field matching common secret shapes (key=, token,
     `AKIA…`, long hex/base64 runs) → reject the whole plan.

Checks to write with the schema (pure `ZenVoiceCore`, no LLM): valid plan
passes; each gate has a fixture that only fails that gate; planner-supplied
risk is provably ignored (fixture where `plannedRisk: low` but surface is
`git push` → `computedRisk: high`).

## 5. Failure and fallback matrix

| Situation | Result |
|---|---|
| Tier 1 matches fully | plan (no model touched) |
| Tier 2 returns valid JSON, validator passes | plan |
| Tier 2 JSON malformed (once) | one re-prompt with the error appended; second failure → fallback |
| Tier 2 `needs_clarification` | one clarifying question shown; answer re-plans once; second ambiguity → text |
| Tier 2 `not_a_goal` | normal text insertion |
| Validator rejects | text insertion + reason line; plan recorded as rejected (audit) |
| Planner timeout (> 4 s hard cap) | text insertion; timeout recorded |

**Invariant: an unparseable or invalid goal can never execute anything.**

## 6. Model-runtime notes (shared with Smart rung)

- One resident model serves Tier 2 and (later) Smart formatting; the
  orchestrator holds it warm during an active goal, idle-unloads with the
  same policy as ASR models (~5 min, reference-counted).
- Model must ship through the verified-catalogue contract (pinned URL,
  revision, size, SHA-256, licence, attribution) — same as every other model
  in ZenVoice.
- Determinism: `temperature 0`; a goal transcript must produce the same plan
  on re-run (checked in tests with a stub model).

## 7. Worked examples

| Transcript | Tier | Outcome |
|---|---|---|
| "open safari" | 0 | v1 action (unchanged) |
| "run the e2e tests in bridgemind" | 1 | single codex step, cwd resolved, risk medium |
| "open bridgemind in codex, run e2e tests, fix obvious failures, notify me" | 1–2 | 3-step plan as §3 example |
| "delete everything in my documents folder" | 2 | `not_a_goal`-style refusal → validator would classify destructive → text + refusal note; **never planned** |
| "tell me a joke about my calendar" | 2 | `not_a_goal` → text insertion |
| "deploy the site" | 2 | `needs_clarification` ("deploy how — which command?") |
