# Language Profiles

ZenVoice keeps language choice explicit. The default profile is **English**,
even when a multilingual model is selected. This prevents short English
phrases from being guessed as Hindi, Urdu, or another language simply because
automatic detection is available.

## Profiles

- **English:** English speech is decoded as English.
- **Hinglish:** Hindi and English speech is decoded with Hindi as the primary
  language, then native-script text is transliterated locally into Latin
  characters. Existing English words remain unchanged.
- **Automatic detection:** Whisper chooses one primary language for each
  completed dictation. This is optional because short or heavily mixed phrases
  are harder to classify reliably.
- **Custom:** choose any supported spoken language and one output mode.

## Output modes

| Mode | Result | Processing |
| --- | --- | --- |
| As spoken | Keeps the spoken language and native script | Local Whisper |
| Translate to English | Produces an English translation | Local Whisper translation |
| Latin script | Keeps the language but converts supported scripts to Latin characters | Foundation transliteration on-device |

Translation is not transliteration. For example, Hindi “नमस्ते दुनिया” becomes
“hello world” in translation mode and “namaste duniya” in Latin-script mode.

## Model compatibility

English works with either an English-only or Multilingual model. Hinglish,
automatic detection, and every non-English language require a Multilingual
model. ZenVoice refuses an incompatible model/profile combination rather than
silently falling back to a different language.

The catalogue currently exposes 64 Whisper language codes. Recommended
languages have the strongest initial product focus; Preview languages are
available but still need broader real-microphone validation. The label is a
ZenVoice release-readiness classification, not a claim that all listed
languages have equal accuracy.

## Privacy

Language selection, transcription, translation, and transliteration stay on
the Mac. ZenVoice does not send speech or text to a language service.

## Known limitations

- Whisper uses one primary language token per dictation. Rapid switching
  between several languages can still be imperfect.
- Hinglish quality depends on the selected multilingual model and the amount
  of English mixed into the phrase.
- Latin transliteration is deterministic, but spelling may not match every
  person’s preferred romanization.
- Real-microphone QA is required for English, Hinglish, Spanish, French,
  Mandarin Chinese, and Arabic before this milestone is release-approved.
