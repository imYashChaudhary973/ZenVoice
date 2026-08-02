# Release QA Record Template

Copy this file for each release candidate, name the copy with the version and
date, and retain the completed copy with the protected release approval or
release assets. Do not modify the tested source commit only to add results. Run
every test against the app extracted from the exact post-staple
`ZenVoice-distribution.zip` produced by `Scripts/notarize-app.sh`, not the
pre-staple notarization upload or a later development build.

Use only `Pass`, `Fail`, `Blocked`, `Not run`, or `Not applicable` for results.
Explain every `Not applicable` result; it does not excuse supported release
coverage. Link failures to an issue or follow-up commit. Do not include private
transcript text, application names from private usage, credentials, private
contact details, or unrelated personal data in this record or its attachments.

## Candidate

| Field | Value |
|---|---|
| Release version and build | |
| Source commit reported by `Scripts/build-app.sh` | |
| Notarization upload archive | `ZenVoice-notarization-upload.zip` |
| Notarization request ID | |
| Distribution artifact | `ZenVoice-distribution.zip` |
| Distribution SHA-256 printed by `Scripts/notarize-app.sh` | |
| Test date | |
| Tester name, initials, or role | |
| Mac model | |
| Chip and memory | |
| macOS version | |
| Developer ID identity and team | |
| `codesign`, `spctl`, and `stapler` evidence | |

## Installed speech models

Record the exact catalogue identity rather than only the display name. Mark a
model `Not installed` when it is outside this candidate's test matrix.

| Display name | Catalogue ID | Runtime | Revision | Status |
|---|---|---|---|---|
| Parakeet | `parakeet-unified-en-int8` | Parakeet/CoreML | | |
| Whisper Small | `whisper-small-multilingual` | whisper.cpp | | |
| Whisper Turbo | `whisper-large-v3-turbo` | whisper.cpp | | |
| Hinglish Apex | `hindi2hinglish-apex` | whisper.cpp | | |
| Whisper Medium | `whisper-medium-multilingual` | whisper.cpp | | |

## Development manual scenarios

Run every numbered scenario in `docs/DEVELOPMENT.md#manual-qa` at the source
commit recorded above. Evidence should identify observable state such as **In
use**, **Home → Model**, ZenBar success, clipboard behavior, a content-free word
count, or an issue link. Do not paste the dictated sentence into this record.

| Scenario | Result | Evidence, issue, or notes |
|---:|---|---|
| 1 | Not run | |
| 2 | Not run | |
| 3 | Not run | |
| 4 | Not run | |
| 5 | Not run | |
| 6 | Not run | |
| 7 | Not run | |
| 8 | Not run | |
| 9 | Not run | |
| 10 | Not run | |
| 11 | Not run | |
| 12 | Not run | |
| 13 | Not run | See the model-runtime evidence below. |
| 14 | Not run | |
| 15 | Not run | |
| 16 | Not run | |
| 17 | Not run | |
| 18 | Not run | |
| 19 | Not run | |
| 20 | Not run | |
| 21 | Not run | |
| 22 | Not run | |
| 23 | Not run | |
| 24 | Not run | |
| 25 | Not run | |
| 26 | Not run | |
| 27 | Not run | |
| 28 | Not run | |
| 29 | Not run | |
| 30 | Not run | |
| 31 | Not run | |
| 32 | Not run | |
| 33 | Not run | |
| 34 | Not run | |

## Model-runtime evidence

Perform these transitions while ZenVoice is idle on Apple Silicon with
Parakeet and at least one current multilingual Whisper model installed. A row
passes only after the target shows **In use**, **Home → Model** shows the target,
and a new non-sensitive dictation completes through ZenBar. The successful
dictation is the runtime proof; the selection state alone does not prove that
asynchronous model loading or decoding succeeded.

| Transition | Language profile | Observable evidence | Result |
|---|---|---|---|
| Start with Parakeet (`parakeet-unified-en-int8`) | English | **In use**, **Home → Model: Parakeet**, two consecutive successful dictations | Not run |
| Parakeet → current multilingual Whisper model | English | Target **In use**, matching Home model, two consecutive successful dictations | Not run |
| Multilingual Whisper → Parakeet without relaunching | English | Parakeet **In use**, matching Home model, successful dictation | Not run |
| English/Parakeet → Auto-Detect | Auto-Detect | A compatible installed multilingual Whisper model becomes active; successful dictation | Not run |
| Auto-Detect/multilingual Whisper → Parakeet | Auto-Detect, then English | **Switch & use** commits Parakeet and English together; successful dictation | Not run |

Record the multilingual Whisper model used for the round trip:

- Display name:
- Catalogue ID:
- Runtime: `whisper.cpp`
- Local performance sample count before/after, if visible:
- Notes or issue:

## Performance and language coverage

Exercise each performance choice and language path in the release scope. Record
the exact model ID because display names can also belong to retired catalogue
entries. **Auto-Detect/multilingual** means a successful mixed or non-English
dictation through a current model with multilingual capability; it is not a
performance tier.

| Coverage | Choice or profile | Model ID | Hardware | Result | Evidence or issue |
|---|---|---|---|---|---|
| Performance | Fast | | | Not run | |
| Performance | Balanced | | | Not run | |
| Performance | High Accuracy | | | Not run | |
| Language | English | | | Not run | |
| Language | Hindi | | | Not run | |
| Language | Auto-Detect/multilingual | | | Not run | |
| Language | Hinglish specialist | | | Not run | |

## Additional edge cases

| Scenario | Result | Evidence, issue, or notes |
|---|---|---|
| Denied microphone permission | Not run | |
| Shortcut without a modifier | Not run | |
| Shortcut reserved by macOS or another app | Not run | |
| Silence-only recording | Not run | |
| Repeated hotkey presses during transcription | Not run | |
| App relaunch | Not run | |
| Multiple displays and full-screen spaces | Not run | |

## Release-candidate coverage

| Area | Result | Evidence, issue, or notes |
|---|---|---|
| VoiceOver labels and announcements | Not run | |
| Keyboard navigation | Not run | |
| Reduced motion | Not run | |
| Contrast | Not run | |
| Full-screen and multiple-display ZenBar behavior | Not run | |
| Crash recovery and real lifecycle interruptions | Not run | |
| Failed-audio expiry | Not run | |
| Private Dictation | Not run | |
| Delete All | Not run | |
| Clipboard fallback | Not run | |
| Clean supported-Mac install | Not run | |
| Microphone permission on clean install | Not run | |
| Accessibility permission on clean install | Not run | |

## Final result

Overall result can be `Pass` only when every applicable row above is `Pass`,
every `Not applicable` row has a release-scope justification, the two reviews
below pass, and unresolved blockers is `None`.

- Overall result: `Not run`
- Unresolved blockers:
- Linked issues or follow-up commits:
- Privacy statement compared with observed behavior: `Not run`
- Post-catalogue runtime and model artefacts re-reviewed: `Not run`
- Founder release approval: `Not run`
