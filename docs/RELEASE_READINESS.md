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
- [ ] Decide whether the first public build is free, paid, or private beta.
- [x] Decide direct download, Mac App Store, or both — direct download,
  decided 2026-08-01; the Mac App Store sandbox cannot host
  Accessibility-based insertion. Entitlements reviewed: `audio-input` only,
  no `get-task-allow`.
- [ ] Confirm that the final app, website, and store privacy statements match
  the actual release behavior.
- [ ] Re-review every model or runtime artifact added after the pinned M9
  catalogue.

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
- [ ] Test Fast, Balanced, Multilingual, and High Accuracy choices on the
  supported hardware range.
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

For the Apple distribution items: `Scripts/build-app.sh` requires a clean worktree
and reports the source commit when `ZENVOICE_SIGNING_IDENTITY` names a Developer
ID Application certificate. `Scripts/notarize-app.sh` creates a separate upload
archive, submits it with `notarytool`, staples and verifies the app with
`codesign`, `stapler`, and `spctl`, then packages the stapled app as
`build/ZenVoice-distribution.zip` and prints its SHA-256. The gate can also be
run hosted via the `Release readiness` workflow in the Actions tab.

Do not place Developer ID certificates, private keys, App Store Connect API
keys, notary credentials, or passwords in the repository. A future release
workflow must obtain them from an approved secret store and must require a
protected manual approval environment.
