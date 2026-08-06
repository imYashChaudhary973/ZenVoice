# Release Readiness

ZenVoice's M9 release controls are implemented. Public distribution is
deliberately deferred while ZenVoice is refined for internal use; see
[ADR 0004](decisions/0004-internal-use-first-defer-shipping.md). This checklist
records the gates that must be completed before any future public distribution
decision, not a current blocker list. Decisions and source changes must be
committed; per-candidate QA, signing, and notarization evidence may instead be
retained with the protected release approval or release assets. This checklist is
a project gate, not legal advice.

## Automated foundation

- [x] macOS CI runs core, encrypted-storage, runtime, build, package, and
  nested-signature checks.
- [x] Semgrep Community Edition scans pull requests and `main` without a paid
  account or repository write permission.
- [x] `whisper.cpp` runtime source, pinned release, checksum, and licence notice
  are recorded.
- [x] Downloadable speech-model sources, immutable revisions, checksums,
  attribution, and licences are recorded.
- [x] The privacy and security boundaries are documented.
- [x] A local release gate checks the packaged artifact and tracked source.

## Founder and legal decisions

- [x] Select and add the ZenVoice project licence as `LICENSE` — Apache License,
  Version 2.0, decided 2026-08-01; updated to Apache-2.0 for open-source
  distribution.
- [x] Decide whether the first distributed build is free, paid, or private beta
  — open-source direct download, free, decided 2026-08-05. Not a per-user trial:
  no trial timer, licence key, entitlement check, or account system ships in
  this release, so no new authentication surface is introduced.
- [x] Define the supported release baseline — Apple Silicon Macs running macOS
  14 or newer, decided 2026-08-02. Amended 2026-08-03: that figure is the
  deployment target, not a tested claim. The private beta is certified only on
  the macOS versions actually swept and recorded in the QA record, and
  invitations are limited to those versions.
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
- [x] Re-review every model or runtime artifact in the catalogue — completed
  2026-08-05. The closed-source FluidAudio runtime and its transitive
  components have been removed. ZenVoice now uses only the checksum-pinned
  `whisper.cpp` XCFramework and `whisper.cpp` GGML models. The retired Parakeet
  entry remains resolvable for users who previously installed it, but is no
  longer downloaded or executed.
- [x] Confirm the `whisper.cpp` runtime licence is recorded — MIT, reproduced
  in `THIRD_PARTY_NOTICES.md`.

## Apple distribution (deferred)

The following gates are required before any future public distribution and are
not being pursued while ZenVoice remains internal-use-first.

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

These items remain important for daily use and must be completed before any
future public distribution. They are not treated as release blockers while
ZenVoice is internal-use-first.

- [ ] Complete every manual scenario in `docs/DEVELOPMENT.md` against the exact
  distribution ZIP and source commit recorded in `docs/RELEASE_QA_RECORD.md`.
  Retain the completed record with the release evidence; its overall result and
  founder approval must be **Pass**, every applicable row must be **Pass**, and
  every **Not applicable** row must explain why.
- [ ] Test Fast, Balanced, and High Accuracy performance choices on Apple
  Silicon, recording the exact macOS version each was tested on. A version that
  was not tested is not certified and must not be described as supported in
  release notes or beta invitations, whatever the deployment target allows.
- [ ] Test explicit English, Hindi, Auto-Detect/multilingual, and Hinglish
  specialist language paths with compatible current-catalogue models.
- [ ] Verify VoiceOver labels, keyboard navigation, reduced motion, contrast,
  and full-screen/multiple-display ZenBar behavior.
- [ ] Verify crash recovery, failed-audio expiry, Private Dictation, Delete All,
  and clipboard fallback with real lifecycle interruptions.
- [ ] In the completed QA record, identify the release version, commit, exact
  artifact and SHA-256, hardware, macOS version, model catalogue IDs, and
  results without including private transcript text.

## Running the local gate

Build the app, then run:

```zsh
./Scripts/check-release-readiness.sh
```

Run it through `./` or with an explicit `zsh`; the script is zsh, not bash.

The command is expected to fail for development builds and for any build made
while public distribution is deferred. It passes only after the project licence
exists, this checklist has no unfinished items, the app is Developer-ID signed,
its nested signatures are valid, a notarization ticket is stapled, and no common
secret pattern is found in tracked files.

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
verifies that the ZIP contains the same app.

The automated GitHub release flow is defined in `.github/workflows/release.yml`:

1. On your local machine, run `./Scripts/bump-version.sh X.Y.Z` and open a PR.
2. Merge the version bump PR to `main`.
3. Go to the Actions tab, select **Release**, enter the version, and trigger the
   workflow manually.
4. The workflow builds, signs, notarizes, and packages the app, then creates a
   GitHub Release with the distribution ZIP and release notes.
5. Optionally provide `ZENVOICE_HOMEBREW_TAP_TOKEN` in the repository secrets so
   the workflow can propose a cask update to the tap repository.

Required repository secrets (add these in GitHub Settings > Secrets and Variables
> Actions before running):

- `ZENVOICE_SIGNING_IDENTITY` — full "Developer ID Application: ..." string.
- `ZENVOICE_APPLE_ID` — Apple ID for notarytool.
- `ZENVOICE_TEAM_ID` — Apple Developer Team ID.
- `ZENVOICE_APP_PASSWORD` — app-specific password for notarytool.
- `ZENVOICE_HOMEBREW_TAP_TOKEN` — optional GitHub token for the Homebrew tap.

Do not place Developer ID certificates, private keys, App Store Connect API
keys, notary credentials, or passwords in the repository. The release workflow
obtains them from the GitHub secret store and uses a protected manual trigger.
