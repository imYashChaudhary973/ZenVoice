# AP1 Security Remediation Plan

Status: **Complete** on branch `security/ap1-remediation-and-release-gates`.

This plan tracks the independent AP1 review findings that must be remediated
before the release-candidate PR can be marked ready for merge. The findings are
current as of the 2026-08-01 independent review recorded in the project memory.
All five findings have been addressed and verified.

## Findings and fixes

### 1. Public `DictationVault.live()` bypass — Fixed

**Risk:** A test or attacker can call the production vault factory directly,
bypassing the injected test configuration used by checks.

**Fix:** `DictationVault.live()` now requires an explicit
`BundleIdentifierPolicy`. The policy can only be obtained from
`RuntimeIdentity.policy()`, which rejects missing, empty, and foreign bundle
identifiers. Production callers must resolve the policy from `Bundle.main`;
checks continue to use
`DictationVault(databaseURL:recoveryDirectoryURL:keyProvider:)`.

### 2. Foreign or nil bundle-ID can receive production defaults — Fixed

**Risk:** Running in an unsigned/foreign bundle or in a test host with no
`Bundle.main.bundleIdentifier` can cause the app to resolve the wrong Application
Support path or Keychain namespace, potentially mixing test and production data.

**Fix:** `RuntimeIdentity.BundleIdentifierPolicy` rejects a nil/empty bundle ID
and rejects any ID that does not match the production identifier or an
explicitly allowed QA identifier. `ApplicationSupportRoot`, `UserDefaults` suite
name, and `KeychainVaultKeyProvider` service name are all derived from this
policy. The app also validates the policy at launch and refuses to continue if
it is rejected.

### 3. Path-replacement TOCTOU and non-fail-closed directory creation — Fixed

**Risk:** `DictationVault.createPrivateDirectory(_:fileManager:)` silently
ignored `setAttributes` failures and did not validate the final path after
creation. A path replacement between `createDirectory` and `setAttributes` could
leave data directories with world-readable permissions.

**Fix:**
- After creating the directory, the URL is re-resolved and verified to be a
  directory whose path is still under the intended parent.
- `setAttributes` failures now throw.
- Permissions are verified after `setAttributes`; the directory is rejected if
  it is not `0o700`.

### 4. Weak recovery-audio path validation — Fixed

**Risk:** `validatedRecoveryAudioURL(path:id:)` compared string paths without
resolving symlinks or mount points. A path crafted to look identical after
standardization could point outside the recovery directory.

**Fix:** The supplied path, expected path, and recovery directory are all
resolved with `.resolvingSymlinksInPath()`. The supplied path must equal the
expected path, its parent must equal the resolved recovery directory, and its
path must have the resolved recovery directory as a strict prefix.

### 5. QA Keychain namespace binding is weak — Fixed

**Risk:** `KeychainVaultKeyProvider` used the hardcoded production service
`dev.yashchaudhary.ZenVoice.vault`. Tests running with a different bundle ID
may still have read or overwritten the production key.

**Fix:**
- `KeychainVaultKeyProvider` now requires a `BundleIdentifierPolicy` and derives
  its service from `RuntimeIdentity.keychainServiceName(policy:)`.
- Checks continue to pass an injected `VaultKeyProviding` (e.g.,
  `StaticKeyProvider`), so they never touch the Keychain.
- The production path resolves to the production service; any other path is
  rejected before a Keychain service is chosen.

## Verification gates

For this branch to be considered complete, the following must pass:

- [x] `swift build` succeeds.
- [x] `swift run ZenVoiceCoreChecks` succeeds.
- [x] `swift run ZenVoiceStorageChecks` succeeds.
- [ ] `swift run ZenVoiceRuntimeChecks` succeeds (when a model is installed).
- [x] `./Scripts/check-release-readiness.sh` shows no new `BLOCK` items caused by
      this branch beyond the existing signing/notarization/QA gates.
- [ ] A follow-up independent review re-checks the five findings above.

## Deferred gates (not in this branch)

- Manual QA scenarios from `docs/RELEASE_QA_RECORD.md`.
- Developer ID signing and Apple notarization.
- Accessibility and microphone-overlap QA.

Those gates are tracked in `docs/RELEASE_READINESS.md` and are intentionally
separate from this security-remediation branch.
