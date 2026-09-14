# ADR 0017 — MCP connections for Notetaker

## Status

Accepted — 2026-09-15.

## Context

A public MCP relay exists at `mcp.builderhelm.com`. OAuth grants now
require the Mac's pairing code (#55). The Mac app does not register, does
not poll `/pull`, and `ZenVoiceMCP` is not a package target.
`MeetingVaultStore` refers to a type that is not `MeetingStore`.

Mail/Slack under `Sources/ZenVoice/Connectors/` are search helpers, not MCP.

## Decision

1. **Transport stays the current relay.** No new endpoints. `server.mjs`
   stays pairing-gated and is not grown in this change.
2. **The Mac is a pull client.** Enabling AI connectors registers the
   device, shows the pairing code, and polls `/pull`. Disable stops the
   loop and revokes tokens. That on/off switch *is* device-side grant.
   The OAuth HTML page stays generic (Semgrep). Pairing is the bind.
3. **Tools read `MeetingStore`.** Ready means an original transcript
   exists. Recap maps to `followUpDraft`. Claims/notes are empty until
   that phase exists. Transcripts decrypt on this Mac; the relay still
   stores none.
4. **No silent connect.** Off by default. No pull while locked or off.
5. **Local stdio MCP is not this change.** If desktop agents later spawn
   a local server, they reuse `MeetingMCPServer.handle` and this store.

## Consequences

- AI tools still talk to the public origin. They cannot bind without the
  code shown in Meetings.
- Turning connectors off drops the pull loop, so no tool can reach
  meetings even with an old pairing until the user turns them on again
  and shares the code.
- `MeetingVault` is deleted. Package.swift owns `ZenVoiceMCP`.
