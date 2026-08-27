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

## Apple distribution (v0.4.4)

Shipped 2026-08-27 via local build, sign, notarize, and `gh release create`
(asset: `ZenVoice.dmg`). Source commit `4a996f468500c3a77e5782946a5bf2beef3506a3`.

### v0.4.4 installed-app smoke evidence

Captured from `/Applications/ZenVoice.app` and the published DMG on 2026-08-28.

```zsh
$ mdls -name kMDItemVersion -name kMDItemCFBundleIdentifier -name kMDItemDisplayName /Applications/ZenVoice.app
kMDItemCFBundleIdentifier = "com.zenvoice.app"
kMDItemDisplayName        = "ZenVoice.app"
kMDItemVersion            = "0.4.4"

$ plutil -extract CFBundleShortVersionString raw /Applications/ZenVoice.app/Contents/Info.plist && plutil -extract CFBundleVersion raw /Applications/ZenVoice.app/Contents/Info.plist && plutil -extract CFBundleIdentifier raw /Applications/ZenVoice.app/Contents/Info.plist
0.4.4
4
com.zenvoice.app

$ codesign -dv --verbose=4 /Applications/ZenVoice.app 2>&1 | head -12
Executable=/Applications/ZenVoice.app/Contents/MacOS/ZenVoice
Identifier=com.zenvoice.app
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20500 size=84828 flags=0x10000(runtime) hashes=2640+7 location=embedded
Hash type=sha256 size=32
CandidateCDHash sha256=30dfc4141eba8d8880f78d879ad71b3f0e4bab00
Signature size=8978
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
Timestamp=27 Aug 2026 at 10:37:36
Notarization Ticket=stapled
TeamIdentifier=8QSM298XJ2
Runtime Version=14.0.0

$ spctl -a -vv /Applications/ZenVoice.app 2>&1
/Applications/ZenVoice.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Yash Chaudhary (8QSM298XJ2)

$ xcrun stapler validate /Applications/ZenVoice.app 2>&1
The validate action worked!

$ codesign -d --entitlements :- /Applications/ZenVoice.app 2>&1
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.device.audio-input</key><true/></dict></plist>

$ find /Applications/ZenVoice.app \( -type f -perm +111 \) -o -name "*.dylib" -o -name "*.framework" | xargs -I{} sh -c 'codesign -dv --verbose=2 "$1" 2>&1 | grep -E "^(Executable|Identifier|Authority)" | head -3' _ {} 2>&1 | head -80
Executable=/Applications/ZenVoice.app/Contents/MacOS/ZenVoice
Identifier=com.zenvoice.app
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Executable=/Applications/ZenVoice.app/Contents/Frameworks/Sparkle.framework/Versions/Current/Sparkle
Identifier=org.sparkle-project.Sparkle
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Executable=/Applications/ZenVoice.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate
Identifier=Autoupdate
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Executable=/Applications/ZenVoice.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater
Identifier=org.sparkle-project.Sparkle.Updater
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Executable=/Applications/ZenVoice.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader
Identifier=org.sparkle-project.DownloaderService
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Executable=/Applications/ZenVoice.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer
Identifier=org.sparkle-project.InstallerLauncher
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Executable=/Applications/ZenVoice.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle
Identifier=org.sparkle-project.Sparkle
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Executable=/Applications/ZenVoice.app/Contents/Frameworks/whisper.framework/Versions/Current/whisper
Identifier=org.ggml.whisper
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Executable=/Applications/ZenVoice.app/Contents/Frameworks/whisper.framework/Versions/A/whisper
Identifier=org.ggml.whisper
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)
Executable=/Applications/ZenVoice.app/Contents/Frameworks/libparakeet.dylib
Identifier=libparakeet
Authority=Developer ID Application: Yash Chaudhary (8QSM298XJ2)

$ lipo -archs /Applications/ZenVoice.app/Contents/MacOS/ZenVoice
arm64

$ curl -sL https://github.com/imYashChaudhary973/ZenVoice/releases/download/v0.4.4/ZenVoice.dmg -o /tmp/ZenVoice-published-0.4.4.dmg && shasum -a 256 /tmp/ZenVoice-published-0.4.4.dmg
8c7dbf30beccfe505ba0ab8ebca58d06f00bfb91d5e57de9207cc4a7535ed6b2  /tmp/ZenVoice-published-0.4.4.dmg

$ grep -E "version|sha256|url" Casks/zenvoice.rb
  version "0.4.4"
  sha256 "8c7dbf30beccfe505ba0ab8ebca58d06f00bfb91d5e57de9207cc4a7535ed6b2"
  url "https://github.com/imYashChaudhary973/ZenVoice/releases/download/v#{version}/ZenVoice.dmg"

$ xcrun stapler validate /tmp/ZenVoice-published-0.4.4.dmg 2>&1
The validate action worked!

$ hdiutil verify /tmp/ZenVoice-published-0.4.4.dmg 2>&1 | tail -5
hdiutil verify: checksum of "/tmp/ZenVoice-published-0.4.4.dmg" is VALID
```

Summary of automated checks for v0.4.4:

- Version 0.4.4, bundle ID `com.zenvoice.app`, build 4.
- Architecture is `arm64` (Apple Silicon baseline).
- Hardened Runtime flag `0x10000(runtime)` is present; only entitlement is
  `com.apple.security.device.audio-input`; `get-task-allow` is absent.
- Notarization ticket is stapled to the installed app; `spctl` reports
  `accepted`, `stapler validate` succeeds.
- The published DMG SHA-256 matches the cask and the expected release asset
  (`8c7dbf30beccfe505ba0ab8ebca58d06f00bfb91d5e57de9207cc4a7535ed6b2`); the
  DMG also passes `stapler validate` and `hdiutil verify`.
- Sparkle auto-update framework and XPC services are present and signed.
- `swift build`, `swift run ZenVoiceCoreChecks`, `swift run ZenVoiceStorageChecks`,
  and `./Scripts/check-ui-invariants.sh` all pass on the source commit.

- [x] Sign the app and every nested executable with a **Developer ID
  Application** certificate for direct distribution.
- [x] Sign with Hardened Runtime and a secure timestamp; confirm
  `com.apple.security.get-task-allow` is absent.
- [x] Submit the release-candidate app with `notarytool`, review Apple's log,
  and staple the accepted ticket to that app.
- [x] Verify the stapled app with `codesign`, `spctl`, and `stapler`.
- [x] Package that verified, stapled app as a DMG and record the SHA-256.
- [ ] Install that exact distribution DMG on a clean supported Mac and complete
  Microphone and Accessibility permission QA. In-progress: see
  [`docs/RELEASE_QA_RECORD_0.4.4_2026-08-28.md`](RELEASE_QA_RECORD_0.4.4_2026-08-28.md).

## Product and accessibility QA

These items remain important for daily use and must be completed before any
future public distribution. The v0.4.4 QA record tracks progress:
[`docs/RELEASE_QA_RECORD_0.4.4_2026-08-28.md`](RELEASE_QA_RECORD_0.4.4_2026-08-28.md).

- [ ] Complete every manual scenario in `docs/DEVELOPMENT.md` against the exact
  distribution DMG and source commit recorded in `docs/RELEASE_QA_RECORD_0.4.4_2026-08-28.md`.
  Retain the completed record with the release evidence; its overall result and
  founder approval must be **Pass**, every applicable row must be **Pass**, and
  every **Not applicable** row must explain why. (Manual end-to-end QA; cannot
  be auto-verified.)
- [ ] Test Fast, Balanced, and High Accuracy performance choices on Apple
  Silicon, recording the exact macOS version each was tested on. A version that
  was not tested is not certified and must not be described as supported in
  release notes or beta invitations, whatever the deployment target allows.
  (Manual performance testing; cannot be auto-verified.)
- [ ] Test explicit English, Hindi, Auto-Detect/multilingual, and Hinglish
  specialist language paths with compatible current-catalogue models. (Manual
  language-path testing; cannot be auto-verified.)
- [ ] Verify VoiceOver labels, keyboard navigation, reduced motion, contrast,
  and full-screen/multiple-display ZenBar behavior. (Manual/subjective
  accessibility and UI-perception testing; cannot be auto-verified.)
- [ ] Verify crash recovery, failed-audio expiry, Private Dictation, Delete All,
  and clipboard fallback with real lifecycle interruptions. (Manual lifecycle
  testing; cannot be auto-verified.)
- [ ] In the completed QA record, identify the release version, commit, exact
  artifact and SHA-256, hardware, macOS version, model catalogue IDs, and
  results without including private transcript text. (QA-record completeness
  check; not a runtime assertion.)

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
such change invalidates the evidence: build, sign, notarize, package, and test
a new candidate.

For the Apple distribution items: `Scripts/build-app.sh` requires a clean
worktree when `ZENVOICE_SIGNING_IDENTITY` names a Developer ID Application
certificate. It resets ignored SwiftPM state, resolves the pinned manifests,
rejects editable or dirty dependency checkouts, verifies that tracked inputs
remain unchanged through signing, and reports the source commit.
`Scripts/notarize-app.sh` creates a separate upload archive, submits it with
`notarytool`, staples and verifies the app with `codesign`, `stapler`, and
`spctl`, then packages the stapled app as a DMG (`build/ZenVoice.dmg`) and
prints its SHA-256. The local gate mounts the DMG, verifies that it contains
only `ZenVoice.app`, and confirms Gatekeeper acceptance with `spctl`.

The automated GitHub release flow is defined in `.github/workflows/release.yml`:

1. On your local machine, run `./Scripts/bump-version.sh X.Y.Z` and open a PR.
2. Merge the version bump PR to `main`.
3. Go to the Actions tab, select **Release**, enter the version, and trigger the
   workflow manually.
4. The workflow builds, signs, notarizes, and packages the app as a signed,
   stapled DMG, then creates a GitHub Release with `ZenVoice.dmg` and the
   generated release notes.
5. Optionally provide `ZENVOICE_HOMEBREW_TAP_TOKEN` in the repository secrets so
   the workflow can propose a cask update to the tap repository.

Required repository secrets are listed in
[`docs/RELEASE_SECRETS.md`](./RELEASE_SECRETS.md). Add them in GitHub Settings >
Secrets and Variables > Actions before running the workflow. The short version:
`ZENVOICE_SIGNING_IDENTITY`, `ZENVOICE_SIGNING_CERTIFICATE`,
`ZENVOICE_SIGNING_CERTIFICATE_PASSWORD`, `ZENVOICE_NOTARY_KEY`,
`ZENVOICE_NOTARY_KEY_ID`, `ZENVOICE_NOTARY_ISSUER_ID`, and optionally
`ZENVOICE_HOMEBREW_TAP_TOKEN`.

Do not place Developer ID certificates, private keys, App Store Connect API
keys, notary credentials, or passwords in the repository. The release workflow
obtains them from the GitHub secret store and uses a protected manual trigger.
