# Release Readiness

ZenVoice's M9 release controls are implemented. Public distribution is
deliberately blocked until every unchecked item below is decided and evidenced.
Decisions and source changes must be committed; per-candidate QA, signing, and
notarization evidence may instead be retained with the protected release
approval or release assets. This checklist is a project gate, not legal advice.

## Automated foundation

- [x] macOS CI runs core, encrypted-storage, runtime, build, package, and
  nested-signature checks.
- [x] Semgrep Community Edition scans pull requests and `main` without a paid
  account or repository write permission.
- [x] `whisper.cpp` and FluidAudio runtime sources, pinned revisions or
  checksums, and licence notices are recorded.
- [x] Downloadable speech-model sources, immutable revisions, checksums,
  attribution, and licences are recorded.
- [x] The privacy and security boundaries are documented.
- [x] A local release gate checks the packaged artifact and tracked source.

## Founder and legal decisions

- [x] Select and add the ZenVoice project licence as `LICENSE` — proprietary,
  source-visible, decided 2026-08-01.
- [x] Decide whether the first distributed build is free, paid, or private beta
  — invitation-only private beta, decided 2026-08-02.
- [x] Define the supported release baseline — Apple Silicon Macs running macOS
  14 or newer, decided 2026-08-02.
- [x] Decide direct download, Mac App Store, or both — direct download,
  decided 2026-08-01; the Mac App Store sandbox cannot host
  Accessibility-based insertion. Entitlements reviewed: `audio-input` only,
  no `get-task-allow`.
- [x] Confirm that the final app, website, and store privacy statements match
  the actual release behavior — audited 2026-08-02 against the source. There is
  no website and no store listing for a direct-download private beta, so the
  app's own statements are the whole surface. Corrections made rather than
  claimed: recovery-audio expiry now honours its stated 24-hour window from
  capture, Insights count only completed dictations, the Accessibility scope
  and secure-input refusal are described, and the Privacy screen's 500-record
  count window is stated. Re-confirm if application behavior changes before the
  release commit.
- [x] Re-review every model or runtime artifact added after the pinned M9
  catalogue — completed 2026-08-02. The transitive FluidAudio components
  compiled into the shipped binary are now noticed, including fastcluster's
  required BSD notice; the Parakeet download is revision-pinned,
  manifest-exact, and atomically installed; and every recorded size, digest and
  pinned revision was checked against its source.
  The Parakeet licence was recorded as CC-BY-4.0 by taking the conversion
  repository's declaration at face value. Its own bundle metadata says
  `model_id: nvidia/parakeet-unified-en-0.6b`, which NVIDIA governs under the
  Open Model License, while the conversion card declares CC-BY-4.0 and names
  `parakeet-tdt-0.6b-v2`. ZenVoice now records the NVIDIA Open Model License
  and carries its required notice, that being the stricter of the two and the
  one the artifact's own identity supports. Both candidates permit commercial
  use and redistribution with attribution, so ZenVoice is compliant either way.
  Confirming the exact source model with the publisher remains open as an
  accuracy item below rather than a distribution blocker.
- [ ] Ask FluidInference to confirm which NVIDIA model
  `parakeet-unified-en-0.6b-coreml` was converted from, and align the recorded
  licence with the answer. See the conflict table in `THIRD_PARTY_NOTICES.md`.

## Apple distribution

- [ ] Sign the app and every nested executable with a **Developer ID
  Application** certificate for direct distribution.
- [ ] Sign with Hardened Runtime and a secure timestamp; confirm
  `com.apple.security.get-task-allow` is absent.
- [ ] Submit the release-candidate app with `notarytool`, review Apple's log,
  and staple the accepted ticket to that app.
- [ ] Verify the stapled app with `codesign`, `spctl`, and `stapler`.
- [ ] Package that verified, stapled app as `build/ZenVoice-distribution.zip`
  and record the SHA-256 printed by `Scripts/notarize-app.sh`.
- [ ] Install that exact distribution ZIP on a clean supported Mac and complete
  Microphone and Accessibility permission QA.

## Product and accessibility QA

- [ ] Complete every manual scenario in `docs/DEVELOPMENT.md` against the exact
  distribution ZIP and source commit recorded in `docs/RELEASE_QA_RECORD.md`.
  Retain the completed record with the release evidence; its overall result and
  founder approval must be **Pass**, every applicable row must be **Pass**, and
  every **Not applicable** row must explain why.
- [ ] Test Fast, Balanced, and High Accuracy performance choices on the
  private-beta baseline: Apple Silicon Macs running macOS 14 or newer.
- [ ] Test explicit English, Hindi, Auto-Detect/multilingual, and Hinglish
  specialist language paths with compatible current-catalogue models.
- [ ] On Apple Silicon, record a successful Parakeet/CoreML → current
  multilingual whisper.cpp → Parakeet round trip without relaunching, plus the
  Parakeet English-only profile transition. Selection state alone is not
  sufficient; each selected runtime must complete a dictation.
- [ ] Verify VoiceOver labels, keyboard navigation, reduced motion, contrast,
  and full-screen/multiple-display ZenBar behavior.
- [ ] Verify crash recovery, failed-audio expiry, Private Dictation, Delete All,
  and clipboard fallback with real lifecycle interruptions.
- [ ] In the completed QA record, identify the release version, commit, exact
  artifact and SHA-256, hardware, macOS version, model catalogue IDs, and
  results without including private transcript text.

## Running the local gate

Build the app, then run:

```bash
./Scripts/check-release-readiness.sh
```

The command is expected to fail for development builds. It passes only after
the project licence exists, this checklist has no unfinished items, the app is
Developer-ID signed, its nested signatures are valid, a notarization ticket is
stapled, and no common secret pattern is found in tracked files.

A checklist-only release-approval commit may follow the source commit recorded
for the tested artifact. The intervening diff must not change application
source, resources, dependencies, or build, signing, and packaging scripts. Any
such change invalidates the evidence: build, sign, notarize, package, and test a
new candidate.

For the Apple distribution items: `Scripts/build-app.sh` requires a clean
worktree when `ZENVOICE_SIGNING_IDENTITY` names a Developer ID Application
certificate. It resets ignored SwiftPM state, resolves the pinned manifests,
rejects editable or dirty dependency checkouts, verifies that tracked inputs
remain unchanged through signing, and reports the source commit.
`Scripts/notarize-app.sh` creates a separate upload archive, submits it with
`notarytool`, staples and verifies the app with `codesign`, `stapler`, and
`spctl`, then packages the stapled app as `build/ZenVoice-distribution.zip` and
prints its SHA-256. The local gate rejects additional top-level payloads and
verifies that the ZIP contains the same app. It can also be run hosted via the
`Release readiness` workflow in the Actions tab.

Do not place Developer ID certificates, private keys, App Store Connect API
keys, notary credentials, or passwords in the repository. A future release
workflow must obtain them from an approved secret store and must require a
protected manual approval environment.
