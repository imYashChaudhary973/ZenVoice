# Phase 6 — Product & Interface

**Status:** In progress — 2026-08-06.

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
3. New design system (moss on ink) and the window shell it lives in
4. Screen-by-screen rebuild against that system
5. Cloud refinement that works end to end, including Anthropic
6. A real-dictation evaluation corpus

## Detailed tasks

### 1. Remove borrowed and dead UI

- [x] Delete `"Codebase overview"`, the `t3.gg` badge pill, and the **Open** and
      **Commit & push** title actions from `ZenVoiceSettingsView.ledgerTitleBar`.
- [x] Replace the title bar with something a dictation app needs: current status,
      the dictation shortcut, and a single primary action.
- [x] Audit every screen for controls wired to `{ }` or to no-op handlers.
- [x] Audit for other reference-design leftovers ("ledger" naming, devtool
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

- [x] Merge Instant Refine and ZenIntelligence into **Formatting** with a single
      ladder: **Off → Clean → Smart → Cloud**. Today's `off/clean/agentPrompt`
      and `off/format/contextAware` are two ladders for one job.
- [x] Retire the `ZenIntelligence` name. Nothing behind it is intelligent yet;
      the "Smart" rung is reserved for when something is. Update ADR 0007 to say
      so rather than leaving the claim standing.
- [x] Rename the two profile surfaces so they stop reading as duplicates. They
      are genuinely different — Voice Profile is *your vocabulary and
      corrections*, App Profiles are *per-application overrides* — but the names
      invite the confusion. Proposed: **Your Words** and **Per-App Rules**.
- [x] Fold Audio History into History as a tab; it is a view of the same data.
- [x] Fold Updates into Help & About. It is inert and does not warrant top-level
      navigation.
- [x] Migrate persisted preference keys for anything renamed, so existing
      installs keep their settings.

### 3. Design system

Replaces ink + gold, which the user rejected, and the indigo-violet palette that
briefly replaced it. Never pure black. The full contract is
[Design](DESIGN.md); this section records what the phase had to change.

```
canvas   #0B0D0C   window background
surface  #161918   cards
raised   #202423   inset rows, inputs, chips
accent   #4FA88C   accent text, icons, meters
fill     #35806A   selected navigation, primary buttons
text     #EFF1F0   primary
muted    #A5ABA9   secondary
```

The accent is a **muted** moss green, and it exists in two weights. One
mid-green cannot both clear 4.5:1 as text on ink *and* carry white as a button
fill — it lands near 3.8:1 in each direction, so accent text and button labels
are simultaneously too faint. `accent` is the foreground weight, `accentFill`
the background weight.

- [x] Rewrite `ZenDesignTokens.swift`: palette above, card radius 16, nested
      radii 12 and 8, one spacing scale, one type scale.
- [x] Split the accent into foreground and background weights, and document
      which job each one does.
- [x] Card component: 16px radius, 1px hairline border, generous internal
      padding. No horizontal rules between sections — a card already has an
      edge.
- [x] Tinted icon chips — icon over a translucent accent-tinted rounded square,
      heading every page and every card.
- [x] Sidebar: filled accent pill for the active row, accent-tinted icons at
      rest, four labelled groups instead of nine one-item headings.
- [x] Buttons: fixed height, consistent horizontal padding, one primary style,
      one secondary, one destructive. Equal sizing within any row.
- [x] Metrics: uppercase eyebrow above the number, not below it — you read what
      the number is before you read the number.
- [x] Badges become sentence-case capsules. They carry proper nouns
      ("Apple Silicon"), and uppercasing turned those into shouting.
- [x] Remove monospace except where it carries meaning (shortcuts, model IDs,
      language codes, bundle IDs, revision/checksum metadata).
- [x] Light mode derived from the same tokens, not hand-tuned separately.
- [x] One `.tint()` at the window root so native switches, pop-up buttons, and
      text selection stop rendering in the system blue.

### 3a. Window shell

The chrome the design system sits in, rebuilt to match the approved reference.

- [x] Sidebar becomes an `NSVisualEffectView` with `behindWindow` blending,
      running the full height of the window under the traffic lights.
- [x] Root view paints no window-wide background, and the window's
      `backgroundColor` is `.clear` — an opaque fill behind the material
      flattens it to a plain grey panel.
- [x] Content column carries its own 52pt top bar: app name on the left, one
      capsule cluster of global actions on the right.
- [x] Appearance moves from a sidebar-footer segmented control to a single
      cycling toolbar button that names its current and next value.
- [x] The window opens on launch. ZenVoice keeps its menu-bar presence and its
      global hotkey, and closing the window drops the activation policy back to
      `.accessory`.

### 4. Screen rebuild

- [x] Home — status, today usage as large numerals, quick actions.
- [x] Dictation, Languages & Models, Formatting, Commands, Personal, History,
      Privacy & Data, Help & About.
- [x] Alignment pass: every screen on the same grid, labels on a shared baseline,
      controls right-aligned consistently.
- [x] Empty states for every list.

### 5. Cloud refinement, finished

Phase 5 shipped a settings-only preview. It is not usable during dictation.

- [x] **Add Anthropic (Claude).** This is not a base-URL change: the Messages API
      uses `POST /v1/messages`, an `x-api-key` header rather than
      `Authorization: Bearer`, a required `anthropic-version` header, a required
      `max_tokens`, a top-level `system` field, and returns `content[0].text`
      rather than `choices[0].message.content`. `CloudAIRequest` currently
      hardcodes the OpenAI shape, so this needs a per-provider request builder
      and response parser.
- [x] Verify Groq against the live endpoint (2026-08-18, `ZenVoiceCloudLiveChecks`:
      2xx on four models, cleanup changes the transcript, wrong key yields
      `provider(401)` with a readable message — evidence in
      [CLOUD_PROVIDERS.md §5.1](CLOUD_PROVIDERS.md)). En route this caught a
      real outage: Groq shut down `llama-3.3-70b-versatile` (the app default)
      on 2026-08-16; the curated list was refreshed to live-verified models
      and the stored configuration migrated.
- [ ] Verify OpenAI and Anthropic against live endpoints — **credential-blocked
      (user opted to skip, 2026-08-18)**. Wire shapes stay covered by
      `ZenVoiceCoreChecks`; one command per provider closes each when a key
      is stored: `ZENVOICE_CLOUD_LIVE_PROVIDER=openai|anthropic swift run
      ZenVoiceCloudLiveChecks`.
- [x] Make refinement reachable from the dictation flow, not only from settings.
      `CloudAIPreviewWindowController` is presented from `finishRecording()` when
      the active formatting mode is Cloud; Accept inserts the enhanced transcript,
      Discard / error / close keeps the local transcript.
- [x] Per-provider model lists instead of a free-text model field.
- [x] Surface failures without losing the local transcript.

### 6. Evaluation corpus

The goal is measurement, not training. Today's fixtures do not represent real
dictation.

- [x] Define what "real dictation" means here: spontaneous speech, self-
      corrections, filler words, varied mics and rooms — not read audiobook prose.
- [x] Source licence-clean audio. Existing `Scripts/build-librispeech-corpus.py`
      covers read speech; conversational corpora (Common Voice, AMI, or
      self-recorded) are needed for the dictation case. Record provenance and
      licence for each source.
- [x] Extend `ZenVoiceAccuracyChecks` to report per-engine WER on the new corpus.
- [x] Baseline every installed engine (2026-08-18). `ZENVOICE_ACCURACY_ENGINE`
      added to `ZenVoiceAccuracyChecks`; all seven registry engines measured on
      the frozen Common Voice Spontaneous test through their own
      `SpeechEngine` paths — Parakeet TDT v3 6.9 % whole WER at 73× real time
      (best accuracy *and* speed), Whisper Turbo 8.2 %, Cohere 10.8 %,
      Nemotron Multilingual 13.8 %, Parakeet Flash 14.1 %, Nemotron Ultra Fast
      23.8 %. Apple Speech remains behind the manual-QA authorization gate.
      Full table + re-run command:
      [REAL_SPEECH_CORPUS.md §5](REAL_SPEECH_CORPUS.md); recommendation note
      in [MODEL_CATALOG.md](MODEL_CATALOG.md).
- [x] Keep corpora out of git (`/Datasets/` is already ignored); fetch on demand.

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
- Cloud refinement works against a real key: **Groq verified end to end
      2026-08-18** (plus a fixed dead default model); OpenAI and Anthropic
      remain credential-blocked by user choice — one stored key each closes
      them via `ZENVOICE_CLOUD_LIVE_PROVIDER=openai|anthropic swift run
      ZenVoiceCloudLiveChecks`.
- Engine accuracy claims trace to a measured number on real dictation audio.
