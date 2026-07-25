# Transcription Accuracy

Refinement is finished work: on real data the deterministic rules take word
error rate from 23.2% to 7.2%, and nothing further has meaningful headroom
(see [Refinement R&D](REFINEMENT_RD.md) section 8.9). What remains in a
finished transcript is *misheard words*, which is a transcription problem.

This is the first measurement of ZenVoice against real human speech rather
than synthesized fixtures.

## The corpus

[LibriSpeech](https://www.openslr.org/31/) mini `dev-clean-2`, CC BY 4.0 —
1,089 utterances from 26 speakers with reference transcripts. Two sets are
built from it, neither committed to the repository:

- **single** — 24 utterances, one per speaker. Baseline accuracy on real
  voices.
- **dictation** — 8 recordings, each four consecutive utterances from one
  speaker joined by 1.2 s of silence. Real voices in a multi-sentence shape,
  which is what a dictation actually looks like and what makes live
  segmentation fire.

Point `ZENVOICE_ACCURACY_CORPUS` at either directory. The build steps are in
`Scripts/` — audio stays out of git, since it is 15 MB of someone else's
recordings and the harness only needs it locally.

## What real speech says

```
                         whole   segmented   segmentation cost
synthetic fixtures        4.4%        7.7%          +3.4 pts
real, single utterance    4.4%        4.6%          +0.2 pts
real, multi-sentence      2.1%        3.7%          +1.6 pts
```

**The harness is honest about absolute accuracy.** Real speech scores 4.4%
against the fixtures' 4.4%. The synthesized voices are not flattering the
numbers, which is worth knowing given how much rests on them.

**The synthetic fixtures badly overstate segmentation cost.** They claim
+3.4 points; real multi-sentence speech costs +1.6, and single utterances
+0.2. The fixtures insert 1.4 s pauses *between clauses*, so live
segmentation cuts mid-sentence in a way a real speaker rarely does.

**Multi-sentence dictation decodes better than single utterances** — 2.1%
against 4.4% — because Whisper conditions on its own preceding text and a
longer recording gives it more to work with. Short commands are the hard case,
not long dictation.

### Segmentation cost is a fallback path

Worth stating plainly, because it changes the priority: the final text a user
receives comes from `wholeRecordingUpgrade`, which decodes the complete
recording. The segmented transcript only survives when the inserted preview
cannot be safely replaced. So the +1.6 points is what a user gets on a
*fallback*, not on a normal dictation, and improving live segmentation is
worth less than the raw number suggests.

## The lever that matters: model choice

```
              real speech   fixtures   decode time      relative
base.en             4.4%       4.4%    1.79 s / 12    ~83x faster than real time
medium.en           2.9%       2.0%   10.13 s / 12    ~15x faster than real time
```

**Medium removes a third of the errors on real speech** — 4.4% to 2.9% — for
5.7× the decode time. That decode is still an order of magnitude faster than
the recording it is transcribing: a 60-second dictation finishes in roughly
four seconds rather than one.

For comparison, every refinement improvement in this project moved
*disfluency*, never a misheard word. Model choice moves the thing refinement
cannot touch, and it moves it further than anything else measured.

The costs are a 769 MB download against 148 MB, and more memory. That is a
recommendation question rather than a technical one — see
`ModelRecommendations` — but the evidence says the larger model earns its
place on hardware that can hold it.

## Accuracy against speed

Every installed model, on the same 24 real English utterances. Decode is
expressed as a multiple of the audio's own length, because that is what
decides usability: a dictation finishes in its duration divided by this.

| tier | model | WER | decode |
| --- | --- | --- | --- |
| tiny | `tiny.en` | 5.4% | 100x real time |
| base | `base.en` | 4.8% | 63x |
| medium | `medium.en` | **2.9%** | 10x |
| tiny | `tiny` (multilingual) | 5.9% | 95x |
| medium | `medium` (multilingual) | **2.7%** | 9x |

Three things fall out.

**The tiny-to-base step is nearly free and nearly worthless** — 0.6 points for
a third of the speed. **The base-to-medium step is where the accuracy is**:
1.9 points, almost 40% of the remaining errors, for 6x the decode.

**Ten times real time is still fast.** A 60-second dictation decodes in six
seconds on medium. Since decoding starts when the user stops talking, the
question is whether six seconds of waiting is worse than one — not whether the
machine can keep up.

**The multilingual build is not a compromise for English.** `medium`
multilingual scored 2.7% against `medium.en`'s 2.9%, and `tiny` multilingual
5.9% against 5.4%. At the medium tier the English-only build buys nothing,
which matters because only the multilingual builds can do Hindi at all.

## Hinglish

30 real code-switched utterances from the
[MUCS 2021](https://www.openslr.org/104/) Hindi-English test set — genuine
Hinglish, 16 kHz, human transcribed.

**The headline number is not reportable, and the reason matters more than the
number.** Scored as word error rate against the corpus reference, `medium`
reaches 52.6% on a clip it essentially heard correctly:

```
reference  लिबर ऑफिस impress में एक प्रस्तुति document बनाना और बुनियादी formatting …
medium     लिबर आफिस इमप्रेस में एक प्रस्तुती डोक्यूमेंट बनाना और बुन्यादी फॉर्मेटिंग …
```

The words are right. Whisper writes the English ones phonetically in
Devanagari; the reference writes them in Latin. Most of that 52.6% is a
disagreement about **writing convention**, not about what was said — which is
exactly why the harness scores Hinglish on loanword preservation rather than
on script.

Two findings do survive:

- **`tiny` is unusable for Hinglish.** It produces romanized approximations
  ("Libar office in impressed me, a prostitute document banaana") and falls
  into hallucination loops — one clip emitted "We are in India," roughly a
  hundred times, scoring 411%. The loops are also pathologically slow, because
  the decoder runs to its token limit on every window instead of stopping. A
  five-minute corpus took over fifty minutes.
- **`medium` hears code-switched speech well.** The content is close to
  correct; what it gets wrong is which alphabet to use for the English words.

That reframes the Hinglish problem. It is not primarily an accuracy problem to
be solved with a bigger model — it is a **script convention** problem, which is
what `LanguageProfile.hinglish` and `LocalTransliterator` already exist to
handle. Whether they handle it well is a separate measurement, and this corpus
is now the way to make it.

## Open

- **Hinglish is unmeasured here.** LibriSpeech is read English. The
  Hindi/Hinglish path has no equivalent real-speech baseline, and given that
  refinement measured 15.9 points for English against 0.5 for Hindi before it
  was fixed, assuming parity would be unwise.
- **Read speech is not dictation.** LibriSpeech speakers are reading prepared
  prose, so they are fluent, evenly paced and well recorded. Real dictation is
  hesitant and often noisy. These numbers are a floor.
- **Worst cases are unexplained.** One utterance scored 60% and two others
  above 20%, against a 4.4% average. Whatever is happening in those recordings
  is worth more than another point off the mean.
