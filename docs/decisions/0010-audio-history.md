# ADR 0010 — Audio History: Optional Local Recording Archive

## Status

Accepted — Phase 4 implemented.

## Context

Until now ZenVoice deleted the source recording as soon as a transcript was
stored. That is the right default: audio is the rawest form of a dictation, and
keeping it indefinitely would be the single largest privacy liability in an
otherwise transcript-only product.

Some workflows still want the audio — checking what was actually said when a
transcript looks wrong, re-running a recording against a newer engine, or
keeping a short-lived record of a dictated note. Phase 4 adds **Audio History**
to serve those cases without changing the default.

The design problem is that audio is a *different* privacy surface from
transcripts, not merely more of the same, so it should not inherit the
transcript history's settings, storage, or lifetime.

## Decision

Audio History is an opt-in, bounded, separately-governed archive.

1. **Off by default.** `AudioHistoryPreferences.isEnabled` defaults to false and
   records whether the user has made an explicit choice.
2. **Separate storage.** Recordings live as plain WAV files in
   `Application Support/.../AudioHistory/`, not in the encrypted transcript
   vault. Metadata rows live in the existing SQLite database in a dedicated
   `audio_archive` table.
3. **Not encrypted at rest.** Transcript text is encrypted because it is small
   and cheap to protect; whole recordings are not. The archive is protected by
   private directory permissions and by being opt-in and bounded, and this is
   stated plainly in the UI rather than implied.
4. **Bounded by two budgets**, both user-configurable:
   - total size, default 2 GB, clamped to a 100 MB minimum
   - age, default 30 days, clamped to a 1 day minimum

   Cleanup runs at launch and after every archived recording, oldest first.
5. **Archiving follows transcript persistence.** A recording is archived only
   when its dictation row is persisted. Private Dictation, paused history, and
   per-dictation suppression therefore exclude audio automatically — there is no
   second code path that could disagree with the first.
6. **Export is metadata-first.** A ZIP export carries the audio files plus a
   `manifest.json` of capture facts (timestamp, duration, size, language, model,
   target app, category). Transcript text is included only when the user
   explicitly turns it on for that export.
7. **Failure to archive never fails a dictation.** The transcript is already
   stored by the time archiving runs.

## Consequences

- The default install behaves exactly as before: no audio is retained.
- A user who opts in cannot accidentally fill their disk; the archive is capped
  in two independent dimensions.
- Because archiving keys off transcript persistence, Private Dictation needs no
  special handling in the audio path — it cannot leak by construction.
- Unencrypted audio on disk is a real, disclosed trade-off. Anyone with access
  to the user account can read the archive. This is acceptable for an opt-in
  local feature with a visible cap, and is called out in the UI and in
  `docs/PRIVACY.md`.
- Deleting an archive removes both the row and the file; delete-all also
  checkpoints the WAL.

## Implementation notes

- `Sources/ZenVoiceStorage/AudioArchiveRecord.swift` — the record type.
- `Sources/ZenVoiceStorage/AudioHistoryPreferences.swift` — opt-in and budgets.
- `Sources/ZenVoiceStorage/AudioArchiveExporter.swift` — ZIP export via
  `NSFileCoordinator(.forUploading)`, so no third-party archiver is needed.
- `DictationVault` owns the `audio_archive` table, budget enforcement, and path
  confinement — an archive row's audio path must resolve to the exact expected
  file inside the archive directory, mirroring the recovery-audio rule.
- `Sources/ZenVoice/Screens/AudioHistoryScreen.swift` and
  `AudioHistoryViewModel.swift` provide enable, budget, browse, playback,
  delete, and export.

## Privacy

- Nothing is recorded to the archive unless the user turns it on.
- Private Dictation is never archived.
- Audio never leaves the Mac unless the user exports it themselves.
- Exports exclude transcript text by default.

## Related decisions

- ADR 0001 — Local data and model governance
- ADR 0004 — Internal-use-first, defer shipping
- `docs/PHASE_4.md`
