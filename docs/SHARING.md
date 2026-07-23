# Private Highlight Cards

ZenVoice can turn four local insight metrics into a 1200×630 image:

- total words dictated;
- weighted average words per minute;
- current streak days;
- distinct applications used.

`ShareCardSummary` is deliberately numeric-only. It has no field for transcript
text, application identity, voice-profile terms, correction rules, user name,
or account information. The rendered card uses ZenVoice branding and a general
on-device privacy message.

## User-controlled flow

1. The user selects **Share Highlights** in Insights.
2. ZenVoice renders and shows the exact card preview locally.
3. The user may close the preview without creating or transmitting anything.
4. **Save PNG** opens the macOS save panel.
5. **Share…** opens the macOS Share menu with the rendered image.

ZenVoice does not choose a folder, sharing service, recipient, or audience. It
does not automatically upload, publish, or retain a hidden copy of the card.
