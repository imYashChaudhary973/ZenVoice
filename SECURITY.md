# Security Policy

## Supported versions

Only the latest commit on `main` is supported. Security fixes are backported to
the most recent release branch when one exists.

## Reporting a vulnerability

Do not open a public issue containing sensitive details. Use GitHub's private
security reporting for this repository or contact the maintainers through
GitHub.

Include:

- affected commit or version;
- macOS version and hardware;
- reproduction steps;
- expected and observed behavior;
- potential microphone, transcript, clipboard, or code-execution impact.

Do not include real private recordings, transcripts, credentials, or personal
data in the report.

## Security-sensitive areas

Changes involving microphone permissions, Accessibility events, clipboard
handling, executable paths, model downloads, signing, or updates require
explicit security review.

The current engineering threat review and public-distribution blockers are
recorded in [M9 Security Review](docs/SECURITY_REVIEW.md) and
[Release Readiness](docs/RELEASE_READINESS.md).
