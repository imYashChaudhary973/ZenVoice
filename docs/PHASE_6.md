# Phase 6 — Product & Interface

**Status:** Planned — 2026-08-06. No implementation yet.

**Goal:** Make ZenVoice look and behave like a product rather than a pile of
features. Consolidate overlapping capabilities, replace the visual system, and
finish the two features that are currently shells.

**Outcome:** Nine navigation entries instead of nineteen, one coherent visual
language, refinement that actually refines, and a way to measure whether any of
it improved accuracy.

## Why this phase exists

Phases 1–5 added capability quickly and never went back to ask whether the
result was usable. Three specific things went wrong:

1. **Borrowed chrome was never removed.** The settings title bar renders
   `"Codebase overview"`, a `t3.gg` badge, and **Open** / **Commit & push**
   buttons whose actions are empty closures. This is reference-design scaffolding
   from a developer tool, shipped in a dictation app.
2. **Features were added as navigation entries rather than as parts of a
   product.** Nineteen sidebar items, several of which do the same job.
3. **Names promised more than the code delivers.** `ZenIntelligence` contains no
   model — `enhance()` is deterministic string manipulation. ADR 0007 describes
   it as "on-device AI enhancement", which is not accurate.

## Deliverables

1. Removal of borrowed and dead UI
2. Information architecture: 19 → 9 navigation entries
3. New design system (indigo/violet on deep navy)
4. Screen-by-screen rebuild against that system
5. Cloud refinement that works end to end, including Anthropic
6. A real-dictation evaluation corpus

## Detailed tasks

### 1. Remove borrowed and dead UI

- [ ] Delete `"Codebase overview"`, the `t3.gg` badge pill, and the **Open** and
      **Commit & push** title actions from `ZenVoiceSettingsView.ledgerTitleBar`.
- [ ] Replace the title bar with something a dictation app needs: current status,
      the dictation shortcut, and a single primary action.
- [ ] Audit every screen for controls wired to `{ }` or to no-op handlers.
- [ ] Audit for other reference-design leftovers ("ledger" naming, devtool
      metaphors, monospace where it carries no meaning).

### 2. Information architecture

Current: 19 entries across 6 groups. Target: 9.

| New entry | Absorbs |
|---|---|
| **Home** | Home (status, today usage, quick actions) |
| **Dictation** | Shortcuts, Audio, Overlay |
| **Languages & Models** | Languages, Models |
| **Formatting** | Instant Refine, ZenIntelligence, Cloud AI |
| **Commands** | Command Mode, Write Mode |
| **Personal** | Voice Profile, App Profiles (as two tabs) |
| **History** | History, Audio History, Insights (as tabs) |
| **Privacy & Data** | Privacy |
| **Help & About** | Help, Updates |

- [ ] Merge Instant Refine and ZenIntelligence into **Formatting** with a single
      ladder: **Off → Clean → Smart → Cloud**. Today's `off/clean/agentPrompt`
      and `off/format/contextAware` are two ladders for one job.
- [ ] Retire the `ZenIntelligence` name. Nothing behind it is intelligent yet;
      the "Smart" rung is reserved for when something is. Update ADR 0007 to say
      so rather than leaving the claim standing.
- [ ] Rename the two profile surfaces so they stop reading as duplicates. They
      are genuinely different — Voice Profile is *your vocabulary and
      corrections*, App Profiles are *per-application overrides* — but the names
      invite the confusion. Proposed: **Your Words** and **Per-App Rules**.
- [ ] Fold Audio History into History as a tab; it is a view of the same data.
- [ ] Fold Updates into Help & About. It is inert and does not warrant top-level
      navigation.
- [ ] Migrate persisted preference keys for anything renamed, so existing
      installs keep their settings.

### 3. Design system

Replaces ink + gold, which the user rejected. Never pure black.

```
base     #0B0F1A   window background
surface  #131A2B   cards
raised   #1B2438   inputs, chips
accent   #6D5EF8   indigo-violet
glow     #8B7CFF   hover / active
text     #E8EBF5   primary
muted    #98A2B8   secondary
```

- [ ] Rewrite `ZenDesignTokens.swift`: palette above, card radius 14 (from 4),
      one spacing scale, one type scale.
- [ ] Card component: 14px radius, 1px hairline border, generous internal padding.
- [ ] Tinted icon chips — icon over a translucent accent-tinted rounded square,
      consistent 28×28.
- [ ] Sidebar: pill-shaped active state, single icon size, consistent label
      baseline.
- [ ] Buttons: fixed height, consistent horizontal padding, one primary style,
      one secondary, one destructive. Equal sizing within any row.
- [ ] Metrics: large semibold numerals with a small caption beneath, as in the
      reference dashboards.
- [ ] Remove monospace except where it carries meaning (shortcuts, model IDs).
- [ ] Light mode derived from the same tokens, not hand-tuned separately.

### 4. Screen rebuild

- [ ] Home — status, today usage as large numerals, quick actions.
- [ ] Dictation, Languages & Models, Formatting, Commands, Personal, History,
      Privacy & Data, Help & About.
- [ ] Alignment pass: every screen on the same grid, labels on a shared baseline,
      controls right-aligned consistently.
- [ ] Empty states for every list.

### 5. Cloud refinement, finished

Phase 5 shipped a settings-only preview. It is not usable during dictation.

- [ ] **Add Anthropic (Claude).** This is not a base-URL change: the Messages API
      uses `POST /v1/messages`, an `x-api-key` header rather than
      `Authorization: Bearer`, a required `anthropic-version` header, a required
      `max_tokens`, a top-level `system` field, and returns `content[0].text`
      rather than `choices[0].message.content`. `CloudAIRequest` currently
      hardcodes the OpenAI shape, so this needs a per-provider request builder
      and response parser.
- [ ] Verify Groq and OpenAI against live endpoints. Neither has ever run against
      a real provider — current confidence is fixture-level only.
- [ ] Make refinement reachable from the dictation flow, not only from settings.
- [ ] Per-provider model lists instead of a free-text model field.
- [ ] Surface failures without losing the local transcript.

### 6. Evaluation corpus

The goal is measurement, not training. Today's fixtures do not represent real
dictation.

- [ ] Define what "real dictation" means here: spontaneous speech, self-
      corrections, filler words, varied mics and rooms — not read audiobook prose.
- [ ] Source licence-clean audio. Existing `Scripts/build-librispeech-corpus.py`
      covers read speech; conversational corpora (Common Voice, AMI, or
      self-recorded) are needed for the dictation case. Record provenance and
      licence for each source.
- [ ] Extend `ZenVoiceAccuracyChecks` to report per-engine WER on the new corpus.
- [ ] Baseline every installed engine so engine recommendation rests on measured
      accuracy rather than hardware heuristics.
- [ ] Keep corpora out of git (`/Datasets/` is already ignored); fetch on demand.

## Sequencing

1 → 2 → 3 → 4 are ordered by dependency: delete the dead UI, decide the
structure, build the system, then apply it. 5 and 6 are independent and can run
in parallel with any of them.

Milestone 1 is hours. Milestone 2 is a day of decisions and mechanical
migration. Milestone 3–4 is the bulk. Milestone 6 is open-ended and should not
block the interface work.

## Out of scope

- New speech engines.
- Cross-platform (deferred until after macOS 1.0).
- Any change to the local-first default posture.

## Success criteria

- No control in the app does nothing when clicked.
- Nine navigation entries, none of which duplicate another.
- A screenshot of any screen is recognisably the same product as any other.
- Cloud refinement works against OpenAI, Groq, and Anthropic from a real key.
- Engine accuracy claims trace to a measured number on real dictation audio.
