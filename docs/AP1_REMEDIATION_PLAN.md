# AP1 Security Remediation Plan

Status: **In progress** on branch `security/ap1-remediation-and-release-gates`.

This plan tracks the independent AP1 review findings that must be remediated
before the release-candidate PR can be marked ready for merge. The findings are
current as of the 2026-08-01 independent review recorded in the project memory.

## Findings and fixes

### 1. Public `DictationVault.live()` bypass

**Risk:** A test or attacker can call the production vault factory directly,
bypassing the injected test configuration used by checks.

**Fix:** Make `DictationVault.live()` package-internal (or replace it with a
factory that accepts an explicit `ApplicationSupportRoot`) so the public entry
point requires a configured environment. Update all production callers to use
the factory; update all checks to use `DictationVault(databaseURL:recoveryDirectoryURL:keyProvider:)`.

### 2. Foreign or nil bundle-ID can receive production defaults

**Risk:** Running in an unsigned/foreign bundle or in a test host with no
`Bundle.main.bundleIdentifier` can cause the app to resolve the wrong Application
Support path or Keychain namespace, potentially mixing test and production data.

**Fix:** Add a `BundleIdentifierPolicy` that rejects a nil/empty bundle ID and
rejects any ID that does not match the production identifier or a
check-injected QA identifier. Gate `ApplicationSupportRoot`, `UserDefaults`, and
`KeychainVaultKeyProvider` on this policy.

### 3. Path-replacement TOCTOU and non-fail-closed directory creation

**Risk:** `DictationVault.createPrivateDirectory(_:fileManager:)` silently
ignores `setAttributes` failures and does not validate the final path after
creation. A path replacement between `createDirectory` and `setAttributes` can
leave data directories with world-readable permissions.

**Fix:**
- After creating the directory, re-resolve the URL and verify it is a directory
  and that its resolved path is still under the intended parent.
- Throw if `setAttributes` fails or if the resolved permissions are not `0o700`.
- Make the directory creation helper throw; never swallow permission errors.

### 4. Weak recovery-audio path validation

**Risk:** `validatedRecoveryAudioURL(path:id:)` compares string paths without
resolving symlinks or mount points. A path crafted to look identical after
standardization could point outside the recovery directory.

**Fix:** Resolve both the supplied path and the expected recovery directory with
`realpath`/`.resolvingSymlinksInPath()` and verify the resolved supplied path is
strictly inside the resolved recovery directory. Reject any path that escapes.

### 5. QA Keychain namespace binding is weak

**Risk:** `KeychainVaultKeyProvider` uses the hardcoded production service
`dev.yashchaudhary.ZenVoice.vault`. Tests running with a different bundle ID
may still read or overwrite the production key.

**Fix:**
- Derive the Keychain service from the resolved bundle identifier policy.
- Add an explicit `qaServiceSuffix` parameter used only by checks, or require
  tests to pass an injected `VaultKeyProviding`.
- Ensure the production path always resolves to the production service/account
  and that any test path resolves to a distinct service/account.

## Verification gates

For this branch to be considered complete, the following must pass:

1. `swift build` succeeds.
2. `swift run ZenVoiceCoreChecks` succeeds.
3. `swift run ZenVoiceStorageChecks` succeeds.
4. `swift run ZenVoiceRuntimeChecks` succeeds (when a model is installed).
5. `./Scripts/check-release-readiness.sh` shows no new `BLOCK` items caused by
   this branch beyond the existing signing/notarization/QA gates.
6. A follow-up independent review re-checks the five findings above.

## Deferred gates (not in this branch)

- Manual QA scenarios from `docs/RELEASE_QA_RECORD.md`.
- Developer ID signing and Apple notarization.
- Accessibility and microphone-overlap QA.

Those gates are tracked in `docs/RELEASE_READINESS.md` and are intentionally
separate from this security-remediation branch.
