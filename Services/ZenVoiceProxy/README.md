# ZenVoice Proxy

Local stub for meeting bots. Join is queued only — it does not join Zoom, Meet, or Teams.

`ZENVOICE_PROXY_TOKEN` is required. The process exits if it is missing. Listens on loopback.

## Run

From the repo root:

```
ZENVOICE_PROXY_TOKEN=dev swift run --package-path Services/ZenVoiceProxy
```

Or:

```
cd Services/ZenVoiceProxy
ZENVOICE_PROXY_TOKEN=dev swift run
```

`ZENVOICE_PROXY_PORT` defaults to 8787.

## HTTP

```
GET  /health
POST /bot/join   Authorization: Bearer $ZENVOICE_PROXY_TOKEN  {"url":"..."}
POST /bot/leave  Authorization: Bearer $ZENVOICE_PROXY_TOKEN  {"id":"..."}
```

`/health` is unauthenticated and returns `200` with body `ok`.
`/bot/join` returns `202` `{ "id", "status": "queued", "url" }`.
