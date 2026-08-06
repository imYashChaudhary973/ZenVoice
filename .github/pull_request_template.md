## Summary

<!-- What changed and why? Keep this under 5 lines. -->

## Concerns touched (check all that apply)

- [ ] Code/runtime (Swift, Package.swift)
- [ ] License/legal (LICENSE, headers, THIRD_PARTY_NOTICES)
- [ ] Documentation (README, docs/*.md)
- [ ] Configuration/CI (.github, Scripts)
- [ ] Refactoring only (no behavior change)

If more than three are checked, consider splitting this PR.

## Privacy and security

- [ ] No audio, transcript, clipboard, credential, or personal data is committed.
- [ ] No cloud service, telemetry, or external data transfer was added.
- [ ] Permission or executable-path changes were reviewed when applicable.

## Verification

- [ ] `swift run ZenVoiceCoreChecks`
- [ ] `swift run ZenVoiceStorageChecks`
- [ ] `swift run ZenVoiceRuntimeChecks` (when a local model is installed)
- [ ] `swift build`
- [ ] `./Scripts/build-app.sh`
- [ ] Manual macOS QA completed when applicable

## Evidence

<!-- Add concise results, screenshots, or known limitations. -->
