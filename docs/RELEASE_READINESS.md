# Release Readiness

ZenVoice's M9 release controls are implemented. Public distribution is
deliberately blocked until every unchecked item below is decided, evidenced,
and committed. This checklist is a project gate, not legal advice.

## Automated foundation

- [x] macOS CI runs core, encrypted-storage, runtime, build, package, and
  nested-signature checks.
- [x] Semgrep Community Edition scans pull requests and `main` without a paid
  account or repository write permission.
- [x] `whisper.cpp` runtime source, revision, checksum, and MIT notice are
  recorded.
- [x] Downloadable Whisper model source, revision, checksums, attribution, and
  licence are recorded.
- [x] The privacy and security boundaries are documented.
- [x] A local release gate checks the packaged artifact and tracked source.

## Founder and legal decisions

- [ ] Select and add the ZenVoice project licence as `LICENSE`.
- [ ] Decide whether the first public build is free, paid, or private beta.
- [ ] Decide direct download, Mac App Store, or both; review the rules and
  entitlements for the chosen channel.
- [ ] Confirm that the final app, website, and store privacy statements match
  the actual release behavior.
- [ ] Re-review every model or runtime artifact added after the pinned M9
  catalogue.

## Apple distribution

- [ ] Sign the app and every nested executable with a **Developer ID
  Application** certificate for direct distribution.
- [ ] Sign with Hardened Runtime and a secure timestamp; confirm
  `com.apple.security.get-task-allow` is absent.
- [ ] Submit the exact release artifact with `notarytool`, review Apple's log,
  and staple the accepted ticket.
- [ ] Verify the stapled artifact with `codesign`, `spctl`, and `stapler`.
- [ ] Install the exported artifact on a clean supported Mac and complete
  Microphone and Accessibility permission QA.

## Product and accessibility QA

- [ ] Complete every manual scenario in `docs/DEVELOPMENT.md` on the exact
  release commit.
- [ ] Test Fast, Balanced, Multilingual, and High Accuracy choices on the
  supported hardware range.
- [ ] Verify VoiceOver labels, keyboard navigation, reduced motion, contrast,
  and full-screen/multiple-display ZenBar behavior.
- [ ] Verify crash recovery, failed-audio expiry, Private Dictation, Delete All,
  and clipboard fallback with real lifecycle interruptions.
- [ ] Record the release version, commit, hardware, macOS version, model, and
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

Do not place Developer ID certificates, private keys, App Store Connect API
keys, notary credentials, or passwords in the repository. A future release
workflow must obtain them from an approved secret store and must require a
protected manual approval environment.
