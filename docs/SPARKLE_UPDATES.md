# Sparkle Automatic Updates

ZenVoice uses [Sparkle](https://sparkle-project.org/) to deliver automatic updates
on macOS. This document describes how the Ed25519 keypair is generated, where the
keys live, and how the `appcast.xml` feed is produced for each release.

---

## What Sparkle needs

1. A public Ed25519 key embedded in the app bundle (`Resources/Info.plist` under
   the `SUPublicEDKey` key).
2. A matching private Ed25519 key kept secret and used to sign each release's
   DMG at build time.
3. An `appcast.xml` feed hosted at a public HTTPS URL listing each release.

The app uses the public key to verify that any downloaded update was signed by
the holder of the private key.

---

## Generating the Ed25519 keypair

Use Sparkle's `generate_keys` tool. If Sparkle is installed at the system level,
run:

```zsh
generate_keys -x zen
```

If the Sparkle tools are vendored inside the repo, run:

```zsh
vendor/sparkle/bin/generate_keys -x zen
```

The tool creates two items in your macOS login keychain:

- **Sparkle zen public key** — the public key to embed in the app.
- **Sparkle zen private key** — the private key used for signing.

To print the public key (base64) for embedding in `Info.plist`:

```zsh
generate_keys -x zen -p
```

Example output (this is **not** a real key):

```text
tE4W43bmZ8/8V0wSUw2A8gAqo0JdPfgHUnS9p0hDMVk=
```

Copy the value that `generate_keys` prints for your keypair.

---

## Embedding the public key

Add the `SUPublicEDKey` key to `Resources/Info.plist` inside the top-level
`<dict>`:

```xml
<key>SUPublicEDKey</key>
<string>YOUR_PUBLIC_KEY_HERE</string>
```

For example, with a placeholder key:

```xml
<key>SUPublicEDKey</key>
<string>tE4W43bmZ8/8V0wSUw2A8gAqo0JdPfgHUnS9p0hDMVk=</string>
```

The key above is only an example shape. Use the real value that
`generate_keys -x zen -p` prints for your keypair.

---

## Keeping the private key secret

The private key must **never** be committed, pasted into an issue/PR, logged, or
shared in chat. Store it in one of these locations only:

- A secure macOS keychain entry named `Sparkle zen private key` on the release
  machine.
- A GitHub Actions secret named `ZENVOICE_SPARKLE_PRIVATE_KEY` that contains the
  base64-encoded private key exported from `generate_keys`.

The release workflow can download or use the key at build time, but the
repository itself must contain only the public key in `Info.plist`.

---

## Generating the appcast feed

The `Scripts/generate-appcast.rb` script is run during a release. It takes the
release DMG, computes its SHA-256 and length, calls Sparkle's `sign_update` tool
to produce the Ed25519 signature, pulls the release notes for the requested
version from `CHANGELOG.md`, and writes an `appcast.xml` file.

Example usage:

```zsh
./Scripts/generate-appcast.rb \
  --version 0.4.2 \
  --dmg build/ZenVoice.dmg \
  --feed-url https://example.com/zenvoice/appcast.xml \
  --private-key /secure/path/to/sparkle-zen-private-key.pem \
  --output build/appcast.xml
```

Required arguments:

- `--version VERSION` — the release version, e.g. `0.4.2`.
- `--dmg PATH` — path to the notarized and stapled release DMG.
- `--feed-url URL` — public HTTPS URL where `appcast.xml` will be hosted.
- `--private-key PATH` — path to the Ed25519 private key file used by
  `sign_update`.

Optional arguments:

- `--output PATH` — where to write `appcast.xml` (defaults to `appcast.xml` in
  the working directory).

The script exits non-zero if the DMG or key is missing, if `sign_update` fails,
or if `CHANGELOG.md` cannot be read.

---

## Attaching the feed to a GitHub release

After generating `appcast.xml`, upload it alongside the DMG when the GitHub
release is created:

```yaml
- name: Generate appcast
  env:
    VERSION: ${{ github.event.inputs.version }}
    SPARKLE_PRIVATE_KEY: ${{ secrets.ZENVOICE_SPARKLE_PRIVATE_KEY }}
  run: |
    key_path=$(mktemp)
    printf '%s' "$SPARKLE_PRIVATE_KEY" > "$key_path"
    ./Scripts/generate-appcast.rb \
      --version "$VERSION" \
      --dmg build/ZenVoice.dmg \
      --feed-url https://zenvoice.example.com/appcast.xml \
      --private-key "$key_path" \
      --output build/appcast.xml
    rm -f "$key_path"

- name: Create GitHub Release
  uses: softprops/action-gh-release@c95fe14e0d0d351b72f4a6a93d6f7980c3bf4b1c # v2.2.0
  with:
    tag_name: v${{ github.event.inputs.version }}
    name: ZenVoice ${{ github.event.inputs.version }}
    body_path: build/RELEASE_NOTES.md
    make_latest: true
    files: |
      build/ZenVoice.dmg
      build/appcast.xml
    fail_on_unmatched_files: true
```

The `appcast.xml` URL in the app's Info.plist (`SUFeedURL` key) should point to
the hosted copy of the generated file.

---

## Example appcast output

A generated feed for version `0.4.2` looks like this (signature is shortened):

```xml
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>ZenVoice</title>
    <link>https://example.com/zenvoice/appcast.xml</link>
    <description>ZenVoice release feed</description>
    <language>en</language>
    <item>
      <title>ZenVoice 0.4.2</title>
      <pubDate>Thu, 27 Aug 2026 00:00:00 GMT</pubDate>
      <sparkle:version>0.4.2</sparkle:version>
      <sparkle:shortVersionString>0.4.2</sparkle:shortVersionString>
      <description>
        <![CDATA[
### Added
- Engine downloads in Models now show a determinate progress bar...
        ]]>
      </description>
      <enclosure
        url="https://github.com/imYashChaudhary973/ZenVoice/releases/download/v0.4.2/ZenVoice.dmg"
        length="12345678"
        type="application/octet-stream"
        sparkle:version="0.4.2"
        sparkle:shortVersionString="0.4.2"
        sparkle:edSignature="MEYCIQ...=="
      />
      <sparkle:digest algorithm="sha-256">abcdef...</sparkle:digest>
    </item>
  </channel>
</rss>
```

The signature and digest above are placeholders. A real feed uses the values
produced by `sign_update` and `sha256sum` for the actual release DMG.
