# Voice Profile and Corrections

ZenVoice's Voice Profile summarizes language use from local encrypted history.
It is not a voiceprint and does not identify, authenticate, or compare people
by their voice.

## Profile inputs

The profile analyzes at most the 500 most recent records that contain a final
saved transcript. Analysis occurs in-process after the vault decrypts each
record:

- most-used words exclude a small set of common English function words;
- recurring phrases are repeated two- or three-word sequences with at least
  two meaningful words;
- most-active time is the local calendar hour containing the most records;
- correction rankings use only explicit ZenVoice rule usage.

The bounded window keeps profile refresh predictable as history grows. Profile
terms and phrases are calculated when the screen refreshes and are not written
back to the database.

## Personal corrections

A correction rule has a heard phrase and a replacement phrase. Both fields:

- are chosen explicitly by the user;
- are limited to 120 characters;
- are encrypted with field-bound AES-GCM in the local vault;
- never leave the Mac through ZenVoice.

Exact matching is case-insensitive and requires Unicode word boundaries around
the entire heard phrase. For example, `zen pens` can become `ZenPense`, while
`zen pencil` remains unchanged. Single Latin words of at least five characters
may also use a uniquely close approved spelling; short words, multiword rules,
ambiguous candidates, and unrelated words remain exact-only. Uncertain matches
are suggestions that require explicit acceptance.

Usage counts are committed only after the corrected transcript is saved to
history. Private Dictation can use the rules without producing a transcript or
usage event. ZenVoice does not monitor changes made later in the destination
application, so those edits are never represented as ZenVoice corrections.

Rules may apply to all languages or only to Hinglish. Hinglish-only rules also
bias Whisper with approved replacement vocabulary before decoding. See
[Hinglish spelling personalization](HINGLISH_SPELLING.md) for the review and
private-corpus workflow.
