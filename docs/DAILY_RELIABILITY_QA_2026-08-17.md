# Daily Reliability QA — 2026-08-17

**Status:** In progress. Development QA, not release certification. This
record continues the open items from
[`DAILY_RELIABILITY_QA_2026-08-11.md`](DAILY_RELIABILITY_QA_2026-08-11.md).
It contains no transcript text, API keys, or private application content.

## Tested build and Mac

| Field | Evidence |
|---|---|
| Source branch | `feat/consented-dictation-cycle` at `fcbd529` (worktree at that state) |
| App | `build/ZenVoice.app` via `Scripts/build-app.sh` |
| Executable SHA-256 | `1e00156b329c4ed85ab3c70eaea919924e7c7498bfa7e99dcbaeca31ec20639a` |
| Bundle identity | `dev.yashchaudhary.ZenVoice`, team `8QSM298XJ2`, Hardened Runtime |
| Build result | `Scripts/build-app.sh` passed with Apple Development signing |
| Independent signature verification | Pass: `codesign --verify --deep --strict` valid on disk and satisfies its Designated Requirement |
| Mac | MacBook Pro `Mac17,2`, Apple M5, 10 cores, 24 GB |
| macOS | 27.0 build `26A5388g` |
| Installed speech model exercised | Whisper Turbo `ggml-large-v3-turbo-q5_0.bin` (catalogue SHA-256 verified) |

## Automated lifecycle evidence

| Check | Result | Evidence |
|---|---|---|
| Core policies | Pass | `swift run ZenVoiceCoreChecks`: 10 checks, including the new semantic-guard and slang-lexicon coverage |
| Encrypted storage lifecycle | Pass | `swift run ZenVoiceStorageChecks`: 22 checks |
| Real runtime lifecycle | Pass | `ZENVOICE_RUNTIME_REQUIRED=1 ZENVOICE_MODEL_PATH=…turbo… swift run ZenVoiceRuntimeChecks`: warm-up 1.19 s, decodes 0.90 s, 751 MB loaded, 598 MB reclaimed, reload on next decode |
| Fail-closed required mode | Pass | `ZENVOICE_RUNTIME_REQUIRED=1` with no resolvable model exits 1 with a clear message; same contract verified for `ZENVOICE_ACCURACY_REQUIRED=1` |
| Real-speech corpus validation | Pass | `ZENVOICE_CORPUS_VALIDATE_ONLY=1` against the frozen Common Voice Spontaneous test JSONL: 262 clips validated |
| Real-speech WER measurement | Pass with finding | Full `ZenVoiceAccuracyChecks` decode of the 262-clip / 3,084 s Common Voice test with Whisper Turbo Q5: **8.1 % whole / 9.6 % segmented WER** at 10× real time; semantic-guard violations 0 in both Clean and Agent Prompt modes; whole-recording protected-token counts 10 quantities / 5 negations. For scale on the same frozen test: whisper-small.en base Q5 scored 9.1 % / 9.6 % and the rejected fine-tuned checkpoint 7.3 % / 8.3 % |
| Local smoke-gate reproduction | Pass | `build-librispeech-corpus.py` corpus; smoke with Whisper Turbo: 1.0 % WER; with the gate's pinned `ggml-base.en.bin` (SHA verified): 2.0 % WER on the dictation clip and 7.7 % / 0.55 s on the single-utterance clip now used by the gate — the hosted-runner smoke failure does not reproduce locally |
| Full compile | Pass | `swift build`; only pre-existing Apple locale deprecation warnings |
| Signed app build | Pass | `Scripts/build-app.sh` with Apple Development identity |
| Python pipeline checks | Pass | consented-dictation pipeline, evidence collection, composite selection, and promotion checks all pass |

## Findings recorded this session

1. **Vacuous runtime/accuracy skips (fixed in PR #34).** A plain `swift run`
   cannot see the app's model selection (`RuntimeIdentity` intentionally
   keeps foreign processes out of the production defaults suite), so both
   checks skipped — with exit 0 — even with a catalogue-verified model
   installed and selected. `ZENVOICE_RUNTIME_REQUIRED=1` now fails closed,
   and PR CI downloads the pinned `ggml-small.en.bin` so every merge decodes
   through the real whisper.cpp path.
2. **Weekly speech gate had never passed (fixed; five stacked causes).**
   Every scheduled run since its introduction failed. In order, the layers
   were: exit 137 SIGKILL during compilation from the missing SwiftPM cache
   (added, with the `macos-latest` image); Flash Attention hardcoded without
   a GPU check (now gated); a ~40 s multi-sentence smoke clip no hosted VM
   can decode inside the product's own 2.5×-audio decode deadline, which
   catches stuck decodes for real users and must not be loosened for CI
   (the gate now smokes a single ~5 s utterance); the VM's paravirtualized
   Metal device decoding speech ~40x slower than its own CPU backend
   (`ZENVOICE_DISABLE_GPU=1` forces CPU there; real Macs keep Metal); and
   the reproducible-harness thread pin of 4 oversubscribing the VM's 3
   vCPUs into ggml barrier livelock (the pin is now capped at the machine's
   core count). Final state: runtime checks green on the runner (0.78 s
   decode, 303 MB reclaimed) and real-speech smoke green — `1272-00` at
   11.5 % WER, 1.32 s decode, matching local CPU results.
3. **Turbo hallucinates "Thank you." on near-silence (open product
   decision).** The first honest accuracy run with the daily Whisper Turbo
   model fails the silence-suppression probes: 1, 5, and 10 seconds of
   near-silence decode to "Thank you." and survive cleanup. This is not a
   regression — `TranscriptCleaner.nonSpeechFragments` deliberately excludes
   "Thank you." because it is plausible real dictation, and the tradeoff is
   documented at the declaration. The check is correctly reporting a real
   artifact of the recommended model. Resolving it means choosing between
   accepting the artifact, audio-conditioned suppression in the recorder
   path (suppress only when speech activity was near zero), or a different
   default model; it should not be fixed by silently widening the fragment
   list.
4. **External-input M12 failure still not reproduced.** The 2026-08-11
   record's `Fail` (USB microphone absent from the capture catalogue) was
   re-tested with `Scripts/probe-audio-inputs.swift` on the same macOS
   build with the same USB device connected: built-in, USB (`USBAudio1.0`),
   Bluetooth (`JBL Tune 770NC`), and Continuity iPhone inputs all appear in
   the same `AVCaptureDevice` discovery session the app issues. Consistent
   with the 2026-08-12 non-reproduction record; the one in-app observation
   under the app's own TCC identity remains the only settling step.

## Remaining manual scenarios

Unchanged from the 2026-08-11 record and still `Not run`: real-microphone
Hindi, auto-detect multilingual, live spoken preview, force-quit Recovery
retry, and the in-app Audio screen observation for M12. The deterministic
`ZENVOICE_E2E_AUDIO_FILE` fixture path remains available and should adopt
the first consented cohort clip once session 001 exists.

## Model-cycle status reminder

The consented cohort remains at zero recorded sessions; the pipeline,
locks, and measurement path are verified end-to-end and wait only on
`Datasets/consented-dictation/cohort-v1/SESSION_001_RUNBOOK.md`.
