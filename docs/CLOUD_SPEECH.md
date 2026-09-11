# Cloud speech-to-text

Local engines stay. Cloud engines are first-class and built for **fast
insert**: stop speaking → upload the clip → text in the focused app.

**ZenPense** does not implement STT. It receives whatever ZenVoice pastes
into the focused field, same as Notes or Mail.

Grok (xAI) has **no public speech API**. It is not an engine.

## Speed rule

Do not decode locally first when a cloud engine is selected. Do not send the
transcript through Cloud AI Formatting afterwards. One network hop. Shared
TLS session, warmed on `prepare()` while the user is still speaking.

```
stop → POST wav → insert text
```

## Phases

### Phase 1 — OpenAI transcribe — done

BYO-key, `gpt-4o-mini-transcribe`, Models list, no silent cloud fallback,
skip Cloud Formatting on this path.

### Phase 2 — Feel instant — done

Shared `URLSession`, 12s timeout, TLS warm on dictation start, history
marking does not block the upload.

### Phase 3 — Gemini — done

`Gemini Transcribe` (`gemini-2.0-flash` generateContent + inline wav).
Separate Google AI Studio key in Keychain.

### Phase 4 — Pages and Grok — done

Help, Overview, and Privacy describe the opt-in. Grok is documented as
unavailable until xAI ships transcription — no fake engine.

## Privacy

Off by default. Key in Keychain. Body is file + model + language (OpenAI)
or audio + transcribe prompt (Gemini). No bundle ID, history, or device id.
