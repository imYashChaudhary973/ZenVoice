# Accuracy harness

`ZenVoiceAccuracyChecks` measures transcription accuracy so changes to the
dictation path can be verified rather than assumed.

```sh
swift run ZenVoiceAccuracyChecks
```

It skips itself — exit code 0 — when no verified model is installed or when
speech synthesis is unavailable, so it is safe in CI on a clean runner.

## What it measures

The harness renders deterministic speech fixtures, then decodes each one two
ways through the same `WhisperTranscriber` the app uses:

| Strategy | What it represents |
| --- | --- |
| `whole` | the finished recording decoded in a single pass |
| `segments` | decoded in the pieces live dictation cuts at, then concatenated |

The gap between them is the **cost of segmented decoding**. It is reported per
clip and overall:

```
  clip                          whole   segments   segments cost
  ------------------------------------------------------------
  migration@170wpm               0.0%       7.4%     +7.4 pts  3 seg
  ------------------------------------------------------------
  OVERALL                        1.0%       2.7%     +1.7 pts
```

## Fixtures

Four sentences chosen to be hostile to dictation — technical vocabulary, proper
nouns, and minimal pairs small models confuse (`bearer`/`barrier`,
`pull request`/`full request`) — each rendered at 170, 280 and 380 words per
minute.

Sentences are split into clauses separated by a 1.4 s silence — comfortably
above the 0.70 s of quiet a phrase boundary requires, so every fixture segments
the same way on every run.

The margin used to matter far more than it does now. Stability was evaluated
only when the preview timer fired every 0.35 s, so a pause barely over 0.70 s
was noticed only if a tick happened to land inside it, and boundaries went
missing at random. `AudioRecorder` now latches a boundary the moment it occurs
and holds it until consumed, which makes detection independent of when anyone
looks. The generous pause stays anyway: fixtures should measure decoding, not
the pause detector.

Rendered audio is cached, so repeat runs skip synthesis. Delete the cache
directory to re-render.

## Long-form dictation

Two extra fixtures run past Whisper's 30-second window boundary, where it starts
a fresh decode conditioned on what it produced for the previous window. Word
error rate hides the two failures that causes, so both are reported directly:

- **insertions** — words in the output the speaker never said. Tracked
  separately from substitutions because invented content is the more dangerous
  failure for a dictation tool: the user may never notice text they did not say.
- **repeat %** — fraction of 5-grams that have appeared before, which catches
  the classic decode loop. A loop barely moves word error rate if it replaces a
  similar amount of text, so it needs its own detector.

Measured 2026-07-25: clean across Base, Medium and Turbo at both normal and
degraded input — 0% repetition, at most 3 insertions. Long-form is not currently
a problem; the detectors stay as regression guards.

## Hindi

Runs when the model is multilingual and the `Lekha` voice is installed,
otherwise skipped. Covers two things English never touches: multilingual
decoding, and the transliteration behind Hinglish output.

Hinglish has no single correct spelling, so asserting a word error rate against
it would be measuring taste. The harness checks the property the feature
actually promises instead — that nothing is left in the original script.

## Hinglish loanword preservation

The script check above is necessary but nowhere near sufficient. It is passed
equally by both of these:

```
kampyutara par kama kara raha hum     ← what ZenVoice produces today
computer par kaam kar raha hoon       ← what a person would write
```

Neither contains Devanagari, so neither trips the assertion — while only one of
them is usable. The defect that makes Hinglish bad is therefore invisible to it.

What *can* be scored without a canonical spelling is whether the English half of
a code-switched sentence survived as English. Four fixtures carry the loanword
set, and each records the English spellings
those words must come back as:

```
  hin-status@170wpm               0/3      0%   lost: project, status, email
  hin-review@170wpm               0/4      0%   lost: pull request, review, computer, test
  ------------------------------------------------------------
  OVERALL                        0/26      0%
```

The English words are written in Devanagari in the fixture on purpose. `Lekha`
is a Hindi voice, so `स्टेटस` gets voiced the way an Indian speaker actually
says *status* — which is the audio the Hinglish profile has to survive. Latin
text handed to a Hindi voice would produce a pronunciation no Hinglish speaker
uses.

**Baseline, measured 2026-07-25 on Whisper Medium: 0/26.** Every English word is
destroyed. That is the defect, not a harness fault: any model that transcribes
Hinglish as Devanagari and then romanizes it turns `computer` into `कंप्यूटर`
into `kampyutara`. The fix is a Hinglish-native model that writes Latin script
directly — see [Hinglish spelling](HINGLISH_SPELLING.md) and the catalogue entry
for Hinglish Apex in [Model catalogue](MODEL_CATALOG.md).

Because a metric that always returned zero would print exactly that baseline,
the harness first scores a known-good and a known-broken string and fails if it
cannot tell them apart. The zero means something only because that check passed.

## Real speech

```sh
ZENVOICE_ACCURACY_CORPUS=~/zenvoice-corpus swift run ZenVoiceAccuracyChecks
```

Each `name.wav` pairs with a `name.txt` holding what was actually said. `aiff`,
`m4a`, `mp3` and `caf` also work, at any sample rate or channel count —
recordings are converted to 16 kHz mono automatically, because silently decoding
a 44.1 kHz file at the wrong rate produces nonsense that looks like a
transcription failure.

Synthetic degradation is deliberately **not** applied to these; real recordings
already arrive at whatever level they were captured at.

This is the escape hatch from synthetic speech. Twenty recordings of one real
voice are worth more than any amount of additional `say` output.

## Assertions

The run fails when:

- segmentation never fires, which would mean both strategies are the same
  measurement
- any fixture produces no transcript at all
- segmented decoding scores *better* than whole-recording decoding, which would
  undermine the reason the release path decodes the whole recording
- whole-recording word error rate exceeds 35%, a deliberately generous ceiling
  that catches catastrophic breakage rather than drift
- long-form output invents more than 5% of the reference length, or repeats more
  than 10% of its 5-grams
- Hindi produces no transcript, or Hinglish output contains any non-Latin
  alphabetic script
- the loanword metric cannot distinguish natural Hinglish from romanized mush
- Hinglish coverage should have run but produced no measurements at all, which
  would turn lost coverage into a clean run
- a **Hinglish-capable model** preserves fewer than 18 of the 26 loanwords

That last floor applies **only** to a model that declares
`ModelLanguageCapability.hinglish`. A general multilingual model scores 0/26 by
construction — it writes English words in Devanagari and the romanizer cannot
recover them — and failing it for that would be failing it for the defect a
Hinglish model exists to fix.

Whisper-Hindi2Hinglish-Apex measures 21/26, so the floor at 18 absorbs a clip of
drift while still catching a collapse back towards the 0/26 baseline.

## Environment

| Variable | Effect |
| --- | --- |
| `ZENVOICE_MODEL_PATH` | use a specific model instead of the usual discovery |
| `ZENVOICE_ACCURACY_GAIN` | input gain applied before decoding (default `0.35`) |
| `ZENVOICE_ACCURACY_NOISE` | noise floor added before decoding (default `0.004`) |
| `ZENVOICE_ACCURACY_CLEAN` | `1` measures studio-clean audio instead |
| `ZENVOICE_ACCURACY_FIXTURES` | cache directory for rendered audio |
| `ZENVOICE_ACCURACY_CORPUS` | directory of real recordings (`name.wav` + `name.txt`) |
| `ZENVOICE_ACCURACY_VERBOSE` | `1` prints every hypothesis |

The default gain and noise approximate a laptop microphone across a desk.
Studio-clean audio flatters every configuration and hides the differences worth
measuring — on clean input a strong model scores near 0% either way.

## Reading the numbers honestly

Fixtures are synthetic speech, which is cleaner and more evenly paced than a
person. Absolute percentages are therefore optimistic. Comparisons between
configurations are reliable, because every configuration processes byte-identical
audio.

The reported segmentation cost is also a **lower bound**: fixture pauses fall at
clean clause boundaries, which is the best case for segmented decoding. Real
fast speech causes the pause detector to cut mid-phrase, where the damage is
larger.
