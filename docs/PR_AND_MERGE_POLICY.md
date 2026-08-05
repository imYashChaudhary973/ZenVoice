# ZenVoice Pull Request and Merge Policy

Every code, legal, documentation, or CI change must follow this policy. The
policy is a living record of how ZenVoice stays reviewable, safe, and
releasable. Updates to this file require a PR and are not exempt from the
rules below.

## When to create a PR

Create a pull request when any of the following is true:

1. A branch contains changes that should be part of `main`.
2. More than one concern is touched, even if small (see Concerns table below).
3. The change affects executable code, runtime dependencies, or model catalogues.
4. The change affects legal/licensing files, privacy claims, or security boundaries.
5. The change affects CI, build, signing, notarization, or release scripts.
6. The change is user-facing (UI text, onboarding, permissions, defaults, pricing, distribution).

A PR is **not** required for a pure doc typo on a page that is not referenced by
release gates, but it still requires a branch + commit; never edit `main`
directly. When in doubt, open a PR.

## When to merge a PR

A PR may be merged **only** when **all** of the following are true:

1. CI passes for every required job on the latest commit.
2. The required review is complete (see Required reviews below).
3. Every concern checkbox in the PR template is honestly checked and justified.
4. The release-readiness script has no new `BLOCK` items caused by this PR.
5. The diff does not introduce secrets, credentials, or private data.
6. The diff does not add or update dependencies without a licence/provenance note.
7. The branch is up to date with `main` (rebased or merged; no merge conflicts).
8. The PR description links to evidence: test output, manual QA notes, or a related issue.

A PR is **never** merged if any of the following are true:

- It edits `main` directly.
- It merges another PR or release branch back into itself to bypass review.
- It contains untracked binary artifacts, screenshots, or clipboard media.
- It disables a CI job, bypasses a hook, or weakens a security check to make tests pass.
- It removes or weakens `Package.resolved` without a documented dependency change.

## Required reviews

| Change type | Required review |
|---|---|
| Swift behavior change | At least one code review from someone who can read Swift |
| Security boundary change (auth, encryption, keychain, file paths, network, paste) | Security-aware review + manual QA evidence |
| Dependency, model catalogue, or licence change | Licence/provenance review + `THIRD_PARTY_NOTICES.md` update |
| Privacy statement change | Accuracy review against source behavior |
| CI/release workflow change | CI behavior review + secret-handling check |
| Documentation only | One review; may be lightweight |

## Concerns and vertical slices

ZenVoice PRs are organized by **concern**, not by file count. The PR template
asks which concerns are touched. If more than three are checked, the author
must either split the PR or explain why the concerns are inseparable in a
single vertical slice.

Allowed concerns:

- Code/runtime (Swift, Package.swift)
- License/legal (LICENSE, headers, THIRD_PARTY_NOTICES)
- Documentation (README, docs/*.md)
- Configuration/CI (.github, Scripts)
- Refactoring only (no behavior change)

A single PR should usually address one milestone slice from
`docs/BUILD_ORDER.md`. Large cross-cutting changes (for example, re-licensing
plus runtime removal plus release tooling) are acceptable only when they form
one coherent transition that cannot be safely split.

## Branch naming

Use the following prefixes so branches sort and signal intent:

- `feat/<name>` — new user-facing capability
- `fix/<name>` — bug fix
- `refactor/<name>` — internal restructuring with no behavior change
- `docs/<name>` — documentation-only change
- `legal/<name>` — licence, notice, or provenance change
- `release/<name>` — release preparation, signing, or distribution changes
- `security/<name>` — security remediation or hardening
- `ci/<name>` — CI/workflow change

The `main` branch is the protected integration branch. The `release/*` branches
carry release-candidate work. Feature branches branch from `main` and merge back
to `main`.

## Rebase vs merge commits

- Default: **rebase onto `main`** to keep history linear and bisectable.
- Use a merge commit only when the branch deliberately combines two previously
  reviewed streams or when preserving branch identity is important.
- Never force-push to `main` or `release/*`.

## PR description and evidence

The PR description must answer:

1. What changed and why (under 5 lines).
2. Which concerns are touched.
3. What verification was run and the result.
4. Known limitations or follow-up work.

Evidence belongs in the PR body or linked from it. Acceptable evidence:

- Terminal output of `swift build` and `swift run ZenVoice*Checks`.
- Output of `./Scripts/check-release-readiness.sh`.
- Manual QA notes with macOS version and scenario numbers.
- A link to a related issue, milestone, or prior PR.

## Commit discipline

- Follow Conventional Commits (`type(scope): subject`).
- Subject line ≤ 72 chars, imperative mood, no trailing period.
- One commit per logical group; do not bundle unrelated fixes.
- Never reference the AI assistant or conversation in a commit message.
- Never bypass pre-commit hooks with `--no-verify` unless explicitly approved.

## Release branch handling

`release/*` branches prepare distribution. Extra rules apply:

1. A release PR must include an updated `docs/RELEASE_QA_RECORD.md` if any
   application source, resource, dependency, or build/signing script changed.
2. The PR is not merged until the release-readiness checklist is complete or
   the incomplete items are explicitly deferred by a follow-up PR.
3. After a release is tagged, the exact distribution artifact and its SHA-256
   are recorded in the release notes and in `docs/RELEASE_QA_RECORD.md`.
4. A checklist-only approval commit may follow the source commit recorded for
   the tested artifact, but the intervening diff must not change application
   source, resources, dependencies, or build/signing/packaging scripts.

## Security and privacy hard stops

Before merging any PR that touches security or privacy:

- Confirm auth/authz/ownership checks on every state-changing path.
- Confirm input validation happens before side effects.
- Confirm secrets are not added to tracked files, logs, or error responses.
- Confirm the failure mode is deny-by-default.
- Confirm output is sanitized for its destination context.
- For storage changes, confirm path traversal cannot occur and file modes are
  least-privilege.

When any of the above cannot be confirmed, request a security review before
merging.

## Emergency fixes

Emergency fixes are still PRs. The only difference is that review and CI may
happen in parallel and merge may happen as soon as CI is green and one
reviewer approves. Post-merge, the author must open a follow-up PR to add or
update tests within the next 48 hours.

## Policy updates

Changes to this policy require a PR titled `docs: update PR and merge policy`
and at least one approving review.
