# Phase 4 — Experience Polish

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

- [ ] Create `Sources/ZenVoice/Overlay/` group.
- [ ] Define `OverlayKind`: `.zenBar` (existing), `.livePreviewPill`, `.livePreviewMedium`, `.livePreviewLarge`.
- [ ] Define `OverlayPreferences` with storage keys.
- [ ] Refactor `ZenBarPanelController` into a generic `OverlayPanelController` that can host any `OverlayKind`.
- [ ] Keep ZenBar behavior unchanged by default.

### 2. Notch-aware live preview overlay

- [ ] Detect notch and safe area via `NSScreen` APIs.
- [ ] Position the live preview overlay around the notch when present.
- [ ] On non-notch Macs, center the overlay at the top of the active display.
- [ ] Show live transcription text as it arrives.
- [ ] Honor Reduce Motion and accessibility settings.
- [ ] Add a setting to disable the overlay entirely.

### 3. Configurable overlay sizes

- [ ] Add overlay size preference: pill, medium, large.
- [ ] Pill: one-line, compact, near notch/menu bar.
- [ ] Medium: 2–3 lines, top-center.
- [ ] Large: 5–6 lines, top-center.
- [ ] Preview each size in settings with sample text.

### 4. Audio History

- [ ] Write a short ADR or update `docs/decisions/0001-local-data-and-model-governance.md`.
- [ ] Extend `DictationVault` with an `audio_archive` table/metadata.
- [ ] Store full recordings only when the user opts in.
- [ ] Budget controls:
  - Maximum total archive size (default e.g., 2 GB)
  - Maximum age (default e.g., 30 days)
  - Cleanup on launch and after each recording
- [ ] Exclude audio archive from encrypted transcript history; audio is its own privacy surface.
- [ ] Add UI to enable, set budget, browse, play back, delete, and export.

### 5. ZIP export

- [ ] Export selected audio records as a ZIP file.
- [ ] Include only metadata (timestamp, duration, language) unless the user explicitly includes transcripts.
- [ ] Default export location: user-selected save panel.

### 6. Today-Usage Stats

- [ ] Extend `LocalInsightsSnapshot` with a `today` section.
- [ ] Add `TodayUsageInsight`: words, dictations, duration, top app.
- [ ] Show a header card on the Overview screen.
- [ ] Show a compact pill in the menu-bar tooltip or a dedicated status item.
- [ ] Respect Private Dictation mode: do not count private recordings in stats.

### 7. Settings UI

- [ ] New screens:
  - `OverlayScreen`
  - `AudioHistoryScreen`
  - Update `OverviewScreen` for today stats header
- [ ] Add toolbar/menu-bar toggle for the overlay pill.

### 8. Verification

- [ ] Manual QA:
  - Overlay appears in pill, medium, and large sizes.
  - Notch-aware positioning works on a notched Mac; falls back on non-notched.
  - Audio History respects budget and cleans up old recordings.
  - ZIP export contains expected files and no private transcript text by default.
  - Today stats update after a dictation and respect Private Dictation.
- [ ] `swift build` and all checks pass.

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
