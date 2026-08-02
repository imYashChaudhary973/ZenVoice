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

| tier | model | WER | decode | size |
| --- | --- | --- | --- | --- |
| tiny | `tiny.en` | 5.4% | 100x real time | 74 MB |
| base | `base.en` | 4.8% | 63x | 141 MB |
| high | **`large-v3-turbo`** | **3.3%** | 9x | **547 MB** |
| high | `medium.en` | 2.9% | 10x | 1.5 GB |
| high | `medium` (multilingual) | **2.7%** | 9x | 1.5 GB |

`large-v3-turbo` is the shipped default on any Metal Mac and had never been
measured. It is 1.5 points better than base for the same speed as medium at a
third of the size. The code comment claiming it "matches Whisper Medium's
accuracy" was **not accurate** — medium is 0.6 points better, about a fifth of
the remaining errors — but at three times the disk for no speed gain, so turbo
remains the right default. The claim had simply never been through the
harness.

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

**Word error rate is the wrong instrument here and its numbers should be
ignored.** A code-switched reference writes Hindi in Devanagari and English in
Latin. A model that romanizes the Hindi scores catastrophically while having
heard every word correctly, and one that writes the English phonetically in
Devanagari scores similarly while producing something no Hinglish user wants.
Both come out near 100% and the figure distinguishes nothing.

What can be judged is whether the English words came back **as English**:

| model | loanwords kept | decode | 30-clip corpus |
| --- | --- | --- | --- |
| `hindi2hinglish-apex` | **82/96 (85%)** | 9x real time | 29 s |
| `medium` (multilingual) | **0/31 (0%)** | 4x real time | over 15 min, abandoned |

```
reference  लिबर ऑफिस impress में एक प्रस्तुति document बनाना … formatting … spoken tutorial
Apex       ,Labor office impress mein ek prastuti document banaana … formatting … spoken tutorial
medium     लिबर आफिस इमप्रेस में एक प्रस्तुती डोक्यूमेंट बनाना … फॉर्मेटिंग … सपोकेन टिटूटूरल
```

Apex keeps every English word in Latin and romanizes the Hindi around it,
which is what Hinglish looks like. Medium turns `document` into डोक्यूमेंट and
`tutorial` into टिटूटूरल — every English word phonetically respelled in a
script its reader did not want, and not one preserved across the corpus.

**The specialist is also dramatically faster**, which was not expected. Apex
decoded the whole corpus in 29 seconds; `medium` was abandoned after fifteen
minutes on the same audio, and `tiny` produced hallucination loops — one clip
emitted "We are in India" roughly a hundred times. General multilingual models
do not merely transcribe code-switched speech badly, they fail to terminate on
it, and the decoder then runs to its token limit on every window.

So there is no Hinglish accuracy problem to solve: the shipped specialist
already handles it, at 85% loanword preservation and 9x real time. The
remaining 15% is the measurable target, and this corpus is how to work on it.

### A correction

An earlier draft of this section concluded that Hinglish was "a script
convention problem" that `LocalTransliterator` would need to solve. That was
measured on `tiny` and `medium` — the general multilingual models — without
checking that the catalogue already ships a specialist for exactly this case.
It does, it was installed on the machine throughout, and it emits Latin script
natively. The conclusion was drawn from the wrong models and the transliterator
is not on the critical path for this at all.

## Rejected: shrinking the encoder window

whisper pads every input to a 30-second window and runs the encoder across all
1500 of its positions whatever was said, so a four-second dictation costs the
same as a twenty-nine second one. `whisper_full_params.audio_ctx` truncates
that. It is the largest latency lever in the runtime and it cannot be used.

Scaling the window to the audio with 50% headroom over the speech, on
whisper-large-v3-turbo:

|                     | default | scaled |
| ------------------- | ------- | ------ |
| decode, whole       | 10.90s  | 6.44s  |
| decode, segmented   | 27.96s  | 10.28s |
| synthetic whole WER | 3.0%    | 24.2%  |
| synthetic segmented | 3.4%    | 125.6% |
| clean speech WER    | 3.0%    | 29.3%  |
| Hinglish loanwords  | 4/26    | 0/26   |

41% faster and eight times worse. The decoder cross-attends to an encoding that
stops before the utterance does, then loops on whatever it was last confident
about — repeating a full clause six times, or collapsing into `-e-d-e-d-e-d`.
Hindi transliteration was lost outright. This is the same fabrication failure
that ruled out beam search on Apex, at far greater magnitude.

Flash attention was the suspected culprit and is not: with `flash_attn` off the
repetition is tidier but reaches 218% and 520% word error rate on single clips.
The model wants the window it was trained on.

## Open

- **Hinglish needs its own metric before it has a number.** Word error rate
  against a code-switched reference measures script convention as much as
  hearing, so the loudest figure in this document — 52.6% — is not an accuracy
  result. The loanword-preservation scoring already in the harness is the
  right instrument; it has not yet been run against this corpus.
- ~~Hallucination loops~~ Fully defended. The decode deadline caps the
  wasted minutes, `TranscriptRepetition.collapsingRunaway` cuts the looped
  text, and when a collapse removes more than
  `wordsCutBeforeDistrust` words the ZenBar now says so — "inserted — the
  decoder looped; check the inserted text" — instead of presenting a failed
  decode as a clean one.
- **Read speech is not dictation.** LibriSpeech speakers are reading prepared
  prose, so they are fluent, evenly paced and well recorded. Real dictation is
  hesitant and often noisy. These numbers are a floor.
- **Worst cases are unexplained.** One utterance scored 60% and two others
  above 20%, against a 4.4% average. Whatever is happening in those recordings
  is worth more than another point off the mean.
