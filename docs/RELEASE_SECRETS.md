# Release Secrets Setup

The [`.github/workflows/release.yml`](../.github/workflows/release.yml) workflow builds, signs, notarizes, and publishes ZenVoice releases from GitHub Actions. It reads all signing and notarization material from repository secrets, so the private keys never need to be checked into git.

This guide lists each required secret, explains how to extract it from your local Mac, and gives the exact `gh secret set` command to upload it. The manual v0.4.1 release was performed locally; future releases should use this workflow after these secrets are configured.

> ⚠️ **Security warning**
> The `.p12` (Developer ID certificate + private key) and `.p8` (App Store Connect API private key) files contain cryptographic secrets. They, and any base64-encoded copies of them, must **never** be committed, pasted into issues/PRs, logged, or shared in chat. If one is ever exposed, rotate it immediately in the Apple Developer portal and App Store Connect.

---

## Required repository secrets

| Secret | What it is | Local source |
|--------|------------|--------------|
| `ZENVOICE_SIGNING_IDENTITY` | Full codesigning identity string | macOS keychain / `security find-identity` |
| `ZENVOICE_SIGNING_CERTIFICATE` | Base64-encoded Developer ID `.p12` | Exported from Keychain Access |
| `ZENVOICE_SIGNING_CERTIFICATE_PASSWORD` | Password protecting the `.p12` | The password you chose on export |
| `ZENVOICE_NOTARY_KEY` | Base64-encoded App Store Connect API `.p8` | Downloaded from App Store Connect |
| `ZENVOICE_NOTARY_KEY_ID` | App Store Connect API key ID | App Store Connect API Keys page |
| `ZENVOICE_NOTARY_ISSUER_ID` | App Store Connect API issuer ID | App Store Connect API Keys page |

---

## `ZENVOICE_SIGNING_IDENTITY`

The full identity string used by `codesign`, exactly as macOS displays it.

Example value:

```text
Developer ID Application: Jane Doe (TEAM_ID)
```

### Extract locally

```zsh
security find-identity -v -p codesigning
```

Look for the line that starts with `Developer ID Application:` and ends with your Apple Developer team ID in parentheses, e.g.:

```text
1) ABCDEF1234567890ABCDEF1234567890 "Developer ID Application: Jane Doe (TEAM_ID)"
```

Use the full quoted string (without the surrounding quotes) as the secret value.

### Upload

```zsh
gh secret set ZENVOICE_SIGNING_IDENTITY --body "Developer ID Application: Your Name (TEAM_ID)"
```

---

## `ZENVOICE_SIGNING_CERTIFICATE`

A base64-encoded `.p12` file containing your **Developer ID Application** certificate and its private key. The workflow decodes this in the runner and imports it into a temporary keychain.

### Extract locally

1. Open **Keychain Access** and select **My Certificates**.
2. Select your **Developer ID Application** certificate and its private key together.
3. Choose **File > Export Items…**, select `.p12`, set a strong password, and save it to a temporary location such as `~/Desktop/ZenVoiceSigningCert.p12`.
4. Base64-encode the file:

```zsh
base64 -i ~/Desktop/ZenVoiceSigningCert.p12 -o ~/Desktop/ZenVoiceSigningCert.p12.base64
```

The `.base64` file is safe to pipe into `gh secret set`, but treat it as a secret file and delete it after uploading.

### Upload

```zsh
gh secret set ZENVOICE_SIGNING_CERTIFICATE < ~/Desktop/ZenVoiceSigningCert.p12.base64
```

---

## `ZENVOICE_SIGNING_CERTIFICATE_PASSWORD`

The password you entered when exporting the `.p12` from Keychain Access.

### Upload securely

To avoid leaving the password in your shell history, set it from an interactive prompt:

```zsh
read -s ZENVOICE_SIGNING_CERTIFICATE_PASSWORD
gh secret set ZENVOICE_SIGNING_CERTIFICATE_PASSWORD --body "$ZENVOICE_SIGNING_CERTIFICATE_PASSWORD"
unset ZENVOICE_SIGNING_CERTIFICATE_PASSWORD
```

---

## `ZENVOICE_NOTARY_KEY`

A base64-encoded `.p8` file containing the private key for an App Store Connect API key. The workflow decodes this and passes it to `notarytool`.

### Extract locally

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com/).
2. Go to **Users and Access > Keys**.
3. Create or select an API key with permission to use `notarytool` (the **Developer** role is sufficient).
4. Download the `.p8` file. Apple only lets you download it once.
5. Base64-encode the file:

```zsh
base64 -i ~/Downloads/AuthKey_KEYID.p8 -o ~/Downloads/AuthKey_KEYID.p8.base64
```

### Upload

```zsh
gh secret set ZENVOICE_NOTARY_KEY < ~/Downloads/AuthKey_KEYID.p8.base64
```

---

## `ZENVOICE_NOTARY_KEY_ID`

The key identifier for the App Store Connect API key used by `notarytool`. It is also the suffix of the downloaded `.p8` filename (`AuthKey_<KEY_ID>.p8`).

Example value:

```text
2X9R4H5X6B
```

### Upload

```zsh
gh secret set ZENVOICE_NOTARY_KEY_ID --body "2X9R4H5X6B"
```

---

## `ZENVOICE_NOTARY_ISSUER_ID`

The issuer ID of your Apple Developer team / App Store Connect account. It is shown at the top of the API Keys page as a UUID.

Example value:

```text
12345678-1234-1234-1234-1234567890ab
```

### Upload

```zsh
gh secret set ZENVOICE_NOTARY_ISSUER_ID --body "12345678-1234-1234-1234-1234567890ab"
```

---

## Helper script

[`Scripts/prepare-release-secrets.sh`](../Scripts/prepare-release-secrets.sh) validates that your local credential files exist and prints the `gh secret set` commands for you to run. It never prints or exports the secret values themselves.

Set the required environment variables and run it from the repo root:

```zsh
export ZENVOICE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
export ZENVOICE_SIGNING_CERTIFICATE_PASSWORD="..."
export ZENVOICE_NOTARY_KEY_ID="..."
export ZENVOICE_NOTARY_ISSUER_ID="..."
export ZENVOICE_SIGNING_CERTIFICATE_PATH="/path/to/ZenVoiceSigningCert.p12.base64"
export ZENVOICE_NOTARY_KEY_PATH="/path/to/AuthKey_KEYID.p8.base64"

./Scripts/prepare-release-secrets.sh
```

---

## Verification

After uploading, confirm the six required secrets are listed in **GitHub Settings > Secrets and Variables > Actions**. No certificate, key, password, or base64 payload should appear in any tracked file.
