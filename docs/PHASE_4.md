# Phase 4 — Experience Polish

**Status:** Implemented — all code deliverables complete, `swift build` and all
check suites pass. Manual live-QA items remain open.

**Goal:** Improve the daily-use surface around dictation without changing the core speech pipeline.

**Outcome:** A notch-aware, configurable live transcription overlay; optional local audio history with budget controls and ZIP export; a daily usage stats card and menu-bar pill.

## Deliverables

1. Refactored overlay system beyond ZenBar
2. Notch-aware live transcription overlay
3. Configurable overlay sizes (pill / medium / large)
4. Audio History: opt-in recording archive with budget controls
5. ZIP export of selected audio history
6. Today-Usage Stats header card and toolbar pill
7. Settings screens for overlays, audio history, and stats

## Why this phase is fourth

- These are user-experience features that depend on the dictation lifecycle being stable.
- They do not add new engines or trust boundaries, so they are a good follow-up after Phase 3.
- Audio History touches storage and privacy, so it needs focused attention.

## Detailed tasks

### 1. Overlay framework

- [x] Create `Sources/ZenVoice/Overlay/` group.
- [x] Define `OverlayKind`: `.zenBar` (existing), `.livePreviewPill`, `.livePreviewMedium`, `.livePreviewLarge`.
- [x] Define `OverlayPreferences` with storage keys.
- [x] Refactor `ZenBarPanelController` into a generic `OverlayPanelController` that can host any `OverlayKind`.
- [x] Keep ZenBar behavior unchanged by default.

### 2. Notch-aware live preview overlay

- [x] Detect notch and safe area via `NSScreen` APIs.
- [x] Position the live preview overlay around the notch when present.
- [x] On non-notch Macs, center the overlay at the top of the active display.
- [x] Show live transcription text as it arrives.
- [x] Honor Reduce Motion and accessibility settings.
- [x] Add a setting to disable the overlay entirely.

### 3. Configurable overlay sizes

- [x] Add overlay size preference: pill, medium, large.
- [x] Pill: one-line, compact, near notch/menu bar.
- [x] Medium: 2–3 lines, top-center.
- [x] Large: 5–6 lines, top-center.
- [x] Preview each size in settings with sample text.

### 4. Audio History

- [x] Write a short ADR or update `docs/decisions/0001-local-data-and-model-governance.md`.
  Written as [ADR 0009](decisions/0009-audio-history.md).
- [x] Extend `DictationVault` with an `audio_archive` table/metadata.
- [x] Store full recordings only when the user opts in.
- [x] Budget controls:
  - Maximum total archive size (default e.g., 2 GB)
  - Maximum age (default e.g., 30 days)
  - Cleanup on launch and after each recording
- [x] Exclude audio archive from encrypted transcript history; audio is its own privacy surface.
- [x] Add UI to enable, set budget, browse, play back, delete, and export.

### 5. ZIP export

- [x] Export selected audio records as a ZIP file.
- [x] Include only metadata (timestamp, duration, language) unless the user explicitly includes transcripts.
- [x] Default export location: user-selected save panel.

### 6. Today-Usage Stats

- [x] Extend `LocalInsightsSnapshot` with a `today` section.
- [x] Add `TodayUsageInsight`: words, dictations, duration, top app.
- [x] Show a header card on the Overview screen.
- [x] Show a compact pill in the menu-bar tooltip or a dedicated status item.
- [x] Respect Private Dictation mode: do not count private recordings in stats.

### 7. Settings UI

- [x] New screens:
  - `OverlayScreen`
  - `AudioHistoryScreen`
  - Update `OverviewScreen` for today stats header
- [x] Add toolbar/menu-bar toggle for the overlay pill.

### 8. Verification

- [ ] Manual QA (not yet run — needs a person at a Mac):
  - Overlay appears in pill, medium, and large sizes.
  - Notch-aware positioning works on a notched Mac; falls back on non-notched.
  - Audio History respects budget and cleans up old recordings.
  - ZIP export contains expected files and no private transcript text by default.
  - Today stats update after a dictation and respect Private Dictation.
- [x] `swift build` and all checks pass.
- [x] Automated coverage for the items that can be checked without a person:
  archive lifecycle, age and size budgets, export manifest contents and
  transcript exclusion, preference defaults and clamping, and today-usage
  aggregation (`ZenVoiceStorageChecks`, 22 checks).

## Dependencies

- Phase 1–3 complete.
- `AVAudioPlayer` or similar for audio playback.
- `NSStatusItem` / `NSMenu` knowledge already exists.

## Out of scope for Phase 4

- New engines (Phase 2).
- ZenIntelligence, Command Mode, Write Mode (Phase 3).
- Cloud AI Enhancement and auto-updates (Phase 5).
- Public shipping (deferred per ADR 0004).

## Success criteria

- Live preview overlay is usable and configurable.
- Audio History is opt-in, bounded, and exportable.
- Today-Usage stats are visible and accurate.
- No regression in ZenBar default behavior.
