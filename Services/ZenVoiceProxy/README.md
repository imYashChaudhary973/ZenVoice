# ZenVoice Proxy

Joins Zoom / Meet / Teams as a visible **ZenVoice Notetaker** guest via
Playwright Chromium. The Mac app then records with ScreenCaptureKit.

Meet requires a Google account. Sign in once in the bot window; the profile
is `~/Library/Application Support/ZenVoice/BotProfile` (or `ZENVOICE_BOT_PROFILE`).
`join.mjs` exits 1 on a sign-in wall or invalid meeting and does not claim joined.

`ZENVOICE_PROXY_TOKEN` is required for the HTTP proxy.

## Bot worker

```
cd Services/ZenVoiceProxy/bot
npm install
npx playwright install chromium
```

## Run

From the repo root:

```
ZENVOICE_PROXY_TOKEN=dev swift run --package-path Services/ZenVoiceProxy
```
`ZENVOICE_PROXY_PORT` defaults to 8787.
`ZENVOICE_BOT_SCRIPT` overrides the path to `bot/join.mjs`.

Without a running proxy, the Mac app joins locally with the same script (`ZENVOICE_BOT_SCRIPT` or `Services/ZenVoiceProxy/bot/join.mjs`).

## HTTP

```
GET  /health
POST /bot/join   Authorization: Bearer $TOKEN  {"url":"..."}
POST /bot/leave  Authorization: Bearer $TOKEN  {"id":"..."}
```

`/bot/join` spawns Chromium, returns `202` `{ id, status: joining, url, pid }`.
`/bot/leave` SIGTERMs that process.
