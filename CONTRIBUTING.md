# Contributing

ZenVoice is a proprietary, source-visible personal project. These rules apply
to collaborators whom the repository owner has authorized to contribute. The
right to submit a contribution does not grant permission to redistribute the
project or publish a modified fork; those actions remain governed by
[`LICENSE`](LICENSE).

## Workflow

1. After the repository owner authorizes the contribution, create a focused
   branch from `main`.
2. Keep changes limited to one feature, fix, or documentation topic.
3. Run the relevant checks.
4. Open a pull request using the repository template.
5. Merge only after the change is understood and manually verified where
   macOS permissions or audio behavior are involved.

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

## Commit messages

Use focused Conventional Commit messages such as:

```text
feat: add multilingual model picker
fix: scale ZenBar waveform from microphone levels
docs: document Accessibility permission recovery
```

Avoid vague messages such as `update files`, `changes`, or `fix stuff`.

## Repository safety

Never commit:

- Whisper model binaries
- microphone recordings or transcripts
- API keys, credentials, or signing certificates
- generated `.build/` or `build/` output
- personal paths that are not part of the documented configuration

Do not add cloud services, telemetry, analytics, or paid dependencies without an
explicit product decision and privacy review.

Public-release changes must also update the third-party notices when relevant,
pass Semgrep, and follow [Release Readiness](docs/RELEASE_READINESS.md). Never
commit Developer ID private keys or notarization credentials.
