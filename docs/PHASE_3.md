# Phase 3 — Intelligence & Control

**Goal:** Add on-device AI enhancement and voice-driven control of the Mac.

**Status:** Implemented — all code deliverables complete, unit tests and release checks pass. Manual live-QA items remain open.

**Outcome:** ZenVoice can post-process transcripts locally for formatting and capitalization (ZenIntelligence), execute voice commands (Command Mode), and rewrite or compose text inline (Write Mode). All three are opt-in and operate on the local machine.

## Deliverables

1. ADR `0006-zenintelligence.md` — on-device AI scope and privacy model
2. ADR `0007-command-mode.md` — voice control trust boundaries
3. ADR `0008-write-mode.md` — inline compose and rewrite behavior
4. `ZenIntelligence` local enhancement engine
5. Command Mode execution: apps, Shortcuts, system actions, scripts
6. Write Mode: compose inline and rewrite selected text
7. Per-app prompt/command sets
8. Settings screens and ZenBar controls

## Why this phase is third

- ZenIntelligence, Command Mode, and Write Mode all consume transcript text.
- They must not be built until the transcription pipeline is stable across engines (Phase 2).
- Command Mode in particular is a trust boundary: it can launch apps and run scripts.

## Detailed tasks

### 1. ZenIntelligence

- [x] Write `docs/decisions/0006-zenintelligence.md`.
- [x] Define `ZenIntelligenceMode`: `.off`, `.format`, `.contextAware`.
- [x] Create `Sources/ZenVoiceCore/ZenIntelligence.swift`.
- [x] Select a small on-device model approach:
  - Core ML conversion of a permissively licensed 1–3B language model, or
  - MLX-based local model runner (if a compatible Swift package exists), or
  - Rule-based meaning guard plus a tiny model for formatting only.
  - **Resolved:** deterministic formatter with a rule-based meaning guard. A local model can replace the formatter later without changing the API.
- [x] Input: raw or deterministically refined transcript + language profile + optional context box.
- [x] Output: formatted transcript with a `wasRejected` flag (same pattern as Instant Refine).
- [x] Add a “meaning guard” so the model cannot change facts or expand vocabulary.
- [x] Add preference keys and UI toggle.
- [ ] Load a local model on demand (deferred until a compatible on-device model is selected).

### 2. Command Mode

- [x] Write `docs/decisions/0007-command-mode.md`.
- [x] Extend Phase 1 scaffold into full execution:
  - `LaunchApp(bundleID:)` via `NSWorkspace`
  - `RunShortcut(name:)` via `Shortcuts` framework if available, otherwise open Shortcuts app
  - `SystemAction(...)` for volume, brightness, Do Not Disturb, etc.
  - `RunAppleScript(String)` and `RunShellScript(String)` with explicit user approval
- [x] Add a command manifest editor in settings:
  - Built-in command library
  - User-defined commands with phrase + action
  - Per-app command sets
- [x] Safety controls:
  - Command Mode is off by default.
  - Commands that run scripts or open URLs require a confirmation overlay the first time.
  - A kill phrase (“cancel command”) stops an in-flight action.
- [x] Parse transcript for command intent only when Command Mode is enabled and the active app profile allows it.

### 3. Write Mode

- [x] Write `docs/decisions/0008-write-mode.md`.
- [x] Create `Sources/ZenVoiceCore/WriteModeEngine.swift`.
- [x] Two sub-modes:
  - **Compose**: insert at caret (same as normal dictation, but explicitly labeled as Write Mode).
  - **Rewrite**: read the current selected/focused text via Accessibility, send it through ZenIntelligence/refinement with a user prompt, and replace it.
- [x] Add ZenBar toggle to switch between Dictation, Command, and Write modes.
- [x] For Rewrite:
  - Verify the selection matches what ZenVoice expects before replacing.
  - Fall back to clipboard if the selection cannot be safely read.
  - Show a diff/preview before applying for large rewrites.

### 4. Per-app prompt and command sets

- [x] Extend `ApplicationProfile` with:
  - `zenIntelligenceMode`
  - `commandSetID`
  - `writeModeDefault: .compose | .rewrite`
  - custom prompt hints for ZenIntelligence
- [x] Allow a default profile to be cloned per app.
- [x] Surface per-app overrides in the App Profiles settings screen.

### 5. UI/UX

- [x] New settings screens:
  - `ZenIntelligenceScreen`
  - `CommandModeScreen`
  - `WriteModeScreen`
- [x] ZenBar mode switcher (Dictation / Command / Write) when any of Command or Write Mode is enabled.
- [ ] Feedback announcements for command execution and rewrite results (pending voiceover/announcement QA).

### 6. Privacy and security

- [x] ZenIntelligence model must be loaded locally; no cloud call.
- [x] Command Mode script execution requires Accessibility permission plus an explicit ZenVoice approval.
- [x] Document all data flows in `docs/PRIVACY.md`.
- [x] Add security review section for Command Mode trust boundary.

### 7. Verification

- [x] Unit tests for command phrase matching and action serialization.
- [x] Unit tests for ZenIntelligence meaning guard.
- [ ] Manual QA:
  - ZenIntelligence formats a messy transcript without changing meaning.
  - Command Mode launches an app by voice.
  - Command Mode runs a Shortcut by voice.
  - Write Mode rewrites selected text in a text editor.
  - Fallbacks work when Accessibility cannot read the selection.

## Dependencies

- Phase 1 and Phase 2 complete.
- A chosen on-device model for ZenIntelligence with a permissive license.
- `Shortcuts` framework availability on macOS 14+.

## Out of scope for Phase 3

- Notch-aware overlay, Audio History, Today-Usage Stats (Phase 4).
- Cloud AI Enhancement and auto-updates (Phase 5).
- Public shipping / release gates (deferred per ADR 0004).

## Success criteria

- ZenIntelligence is opt-in, local, and has a working meaning guard.
- Command Mode can launch an app and run a Shortcut by voice.
- Write Mode can rewrite selected text across apps.
- All three features are off by default.
- `swift build` and all checks pass.
