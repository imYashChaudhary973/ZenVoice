# Contributing to ZenVoice

ZenVoice is open-source software licensed under the Apache License, Version 2.0.
We welcome contributions from anyone who agrees to license their contribution
under the same terms.

## Quick rules

- One commit = one logical, self-contained change that compiles and passes
  checks.
- Push at least once per work session, but **never push directly to `main`**.
- Open a pull request for every coherent chunk of work.
- Keep each PR small enough to review in under 30 minutes.
- Split a PR when it touches more than three distinct concerns.
- Never commit secrets, model files, recordings, transcripts, `.build/`, or
  `build/`.

## Git workflow

### When to commit

A commit should do exactly one thing and leave the project in a working state.
Good examples:

```text
feat: add configurable dictation shortcut
fix: release microphone after cancelled recording
docs: explain multilingual model setup
license: add Apache-2.0 header to ZenVoiceCore files
```

Bad examples:

```text
update files
changes
fix stuff
```

Before committing, run the checks relevant to your change:

```bash
swift run ZenVoiceCoreChecks
swift run ZenVoiceStorageChecks
swift run ZenVoiceRuntimeChecks
swift build
```

### When to push

- Push after a commit that is ready for review or backup.
- Push at least once per work session.
- Always push to a feature branch, never directly to `main`.

### When to open a pull request

Open a pull request as soon as a coherent chunk of work is complete and
reviewable. A PR must:

- have a clear title and a short description of what changed and why;
- pass CI (`swift build`, `ZenVoiceCoreChecks`, `ZenVoiceStorageChecks`,
  `ZenVoiceRuntimeChecks`);
- be small enough to review in under 30 minutes.

### Splitting work into multiple PRs

If a change touches more than **three distinct concerns**, split it. Examples of
separate concerns:

1. Code/runtime changes (Swift, `Package.swift`).
2. License/legal changes (`LICENSE`, headers, `THIRD_PARTY_NOTICES.md`).
3. Documentation changes (`README.md`, `docs/*.md`).
4. Configuration/CI changes (`.github`, `Scripts`).
5. Large behavior-preserving refactoring.

Example: switching the project license and removing a dependency should be
**two PRs**, not one.

## Required verification

```bash
swift run ZenVoiceCoreChecks
swift run ZenVoiceStorageChecks
swift run ZenVoiceRuntimeChecks
swift build
./Scripts/build-app.sh
codesign --verify --deep --strict build/ZenVoice.app
```

UI, microphone, hotkey, and auto-paste changes also require the manual QA
procedure in [Development](docs/DEVELOPMENT.md).

## Repository safety

Never commit:

- Whisper model binaries
- microphone recordings or transcripts
- API keys, credentials, or signing certificates
- generated `.build/` or `build/` output
- personal paths that are not part of the documented configuration

Do not add cloud services, telemetry, analytics, or paid dependencies without
an explicit product decision and privacy review.

Public-release changes must also update the third-party notices when relevant,
pass Semgrep, and follow [Release Readiness](docs/RELEASE_READINESS.md). Never
commit Developer ID private keys or notarization credentials.

## DCO

By contributing to this project, you agree that your contribution is licensed
under the Apache License, Version 2.0. A signed-off-by line is appreciated but
not required.
