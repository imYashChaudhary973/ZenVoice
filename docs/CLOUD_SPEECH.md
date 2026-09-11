# Cloud speech-to-text

Local engines stay the default. Cloud engines are first-class and built for
**fast insert**: stop speaking → upload the clip → text in the focused app.

They do nothing until you paste a key in Models and tap **Use** on that
engine. Audio then leaves this Mac and is billed to your key.

## Engines

| Engine | Model | Endpoint | Auth |
| --- | --- | --- | --- |
| OpenAI Transcribe | `gpt-4o-mini-transcribe` | `https://api.openai.com/v1/audio/transcriptions` | `Authorization: Bearer` |
| Gemini Transcribe | `gemini-2.0-flash` | Google AI Studio `generateContent` | `x-goog-api-key` |
| Scribe v2 | `scribe_v2` | `https://api.elevenlabs.io/v1/speech-to-text` | `xi-api-key` |
| Grok Transcribe | xAI STT | `https://api.x.ai/v1/stt` | `Authorization: Bearer` |

Keys live in the Keychain, one account per provider. Turning the engine off
does not delete the key; deleting the key in Models does.

## Speed rule

Do not decode locally first when a cloud engine is selected. Do not send the
transcript through Cloud AI Formatting afterwards. One network hop. Shared
ephemeral `URLSession` (12 s request / 18 s resource), TLS warmed with a
`HEAD` on `prepare()` while the user is still speaking.

```
stop → POST wav → insert text
```

If the API fails, ZenVoice decodes the **same clip** with the local engine
and ZenBar says so. There is no silent cloud fallback the other way: a local
engine never uploads.

## Request bodies

Nothing but the clip, the model, and an optional language code. No bundle ID,
history, insights, voice-profile data, device id, or install id.

| Engine | Body |
| --- | --- |
| OpenAI | multipart: `model`, optional `language`, `file` (`audio/wav`) |
| Gemini | JSON: fixed transcribe prompt + inline `audio/wav` |
| Scribe v2 | multipart: `model_id`, `file` (`audio/wav`) |
| Grok | multipart: optional `format=true`, optional `language`, `file` last |

Cookies are never stored. The session is ephemeral.

## Privacy

Off by default. Once you tap Use, that clip is subject to the provider's
retention and training policies, which ZenVoice cannot control.

Cloud **formatting** is a separate opt-in and still sends finished text only,
never audio. See [Privacy](PRIVACY.md).
