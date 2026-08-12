# ADR 0012 — Auto-Updates: Signed Feed and Beta Channel

## Status

Accepted — Phase 5 implemented, shipped disabled pending a shipping decision
(ADR 0004).

## Context

ZenVoice is distributed as a direct download rather than through the Mac App
Store, because the App Store sandbox cannot host the Accessibility paste the
product depends on. Direct distribution means there is no platform updater, so
shipping publicly implies owning the update path.

An updater is the most security-sensitive component in a desktop app: it runs
with the user's privileges, fetches code from the network, and replaces the
application binary. A compromised or spoofed update feed is a straight path to
arbitrary code execution on every install. It deserves more caution than any
feature it delivers.

## Decision

The updater is opt-in, verifies before it trusts, and fails closed.

1. **Disabled until public shipping is approved.** The code ships inert. This
   phase builds the mechanism; ADR 0004 still defers the decision to use it.
2. **Opt-in when it is enabled.** Automatic checking is a user choice, with
   manual check as the alternative. There is no silent background install.
3. **The feed is signed with Ed25519** and verified against a public key
   compiled into the app. An unsigned feed, a malformed signature, a signature
   over different bytes, or a key mismatch all reject the update.
4. **Verification is fail-closed and total.** Any failure — signature, hash,
   transport, parse — rejects the update. There is no "warn and continue", no
   user override, and no fallback to unverified installation. A rejected update
   leaves the installed app untouched.
5. **The downloaded archive is hashed and compared** against the SHA-256 in the
   signed feed before anything is replaced. The signature covers the feed; the
   hash binds the feed to the actual bytes. Both must pass.
6. **HTTPS only**, for both feed and archive. A non-HTTPS URL anywhere in the
   feed rejects it.
7. **Downgrades are rejected.** An update is offered only when the feed version
   is strictly greater than the running version, so a replayed old feed cannot
   walk a user back to a version with a known vulnerability.
8. **Beta channel is a separate opt-in.** Stable installs never see beta builds.
   A beta feed is signed with the same key and held to identical verification.

### Framework choice

Sparkle is the obvious candidate and is well-regarded. It is not used here.
The verification surface ZenVoice needs is small — fetch JSON, check one
signature, compare one hash, compare one version — and CryptoKit provides
Ed25519 directly. Taking Sparkle would add a large dependency, its own update
UI, and its own historical CVE surface, in exchange for features (delta
updates, installer scripts) this product does not want. The trade-off is that
ZenVoice owns this code and its bugs; the mitigating factor is that it is
roughly two hundred auditable lines with no dynamic behaviour.

Squirrel was not considered seriously — it targets Electron.

## Consequences

- The update path is small enough to read in full during a security review.
- Losing the signing key means losing the ability to ship updates to existing
  installs; key custody becomes a release-process concern, not a code concern.
- No delta updates: every update is a full download. At ZenVoice's size this is
  an acceptable cost for a much smaller trust surface.
- Because the public key is compiled in, rotating it requires shipping a build
  signed with the old key first. That ordering constraint is a release-process
  requirement, not something the code can enforce.
- The updater cannot install anything the user did not accept, so a hostile feed
  degrades to a denial of updates rather than to code execution.

## Implementation notes

- `Sources/ZenVoiceCore/UpdateFeed.swift` — the feed model, channel, and
  version comparison.
- `Sources/ZenVoiceCore/UpdateVerifier.swift` — Ed25519 verification and hash
  binding. Pure and fully testable without a network.
- `UpdatePreferences` — enabled, channel, last-check timestamp.
- Checks cover the rejection paths specifically: tampered payload, wrong key,
  absent signature, hash mismatch, non-HTTPS URL, and downgrade. Verifying that
  a *valid* feed passes is the easy half; the rejections are the point.

## Privacy

- An update check sends only what fetching a static URL requires. No install
  identifier, no usage data, no user content.
- Checks happen only when enabled or explicitly requested.

## Related decisions

- ADR 0004 — Internal-use-first, defer shipping
- ADR 0011 — Cloud AI Enhancement (the other Phase 5 trust boundary)
- `docs/RELEASE_READINESS.md`
