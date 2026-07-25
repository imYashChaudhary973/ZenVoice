# Evaluation: Measuring Hinglish Quality

Without this, "Hinglish got better" is an opinion. This document specifies how to
turn it into a number.

## Why standard WER is not enough

Romanized Hinglish has **no canonical spelling**. All of these are correct:

| | Variants |
|---|---|
| क्या | kya, kyaa, kia |
| नहीं | nahi, nahin, nahee, nahīn |
| है | hai, hae, he |
| मैं | main, mai, mein |

Naive WER counts *kyaa* against a *kya* reference as an error, so a genuinely
good transcript can score badly and a scoring difference can come entirely from
spelling convention. Three consequences:

1. Normalize spelling before scoring
2. Report character error rate alongside word error rate, since CER degrades more
   gracefully under spelling variation
3. Add a metric that captures the failure mode that actually matters here

## Metrics

### 1. Normalized WER

Apply before scoring both hypothesis and reference:

- lowercase; strip punctuation
- collapse repeated vowels (`kyaa`→`kya`, `nahee`→`nahi`)
- normalize final nasals (`nahin`→`nahi`, `mein`→`mein`)
- map a small equivalence table of known spelling variants
- strip ICU apostrophe artefacts (`da'una`→`dauna`) so today's baseline is not
  flattered or unfairly punished by them

The equivalence table is the honest weak point: it encodes a judgement about
which spellings are "the same". Keep it small, explicit and version-controlled so
score changes can be attributed.

### 2. Character error rate

Same normalization, character-level. Less sensitive to spelling disagreement;
useful as a sanity check when normalized WER moves a lot.

<a name="loanword"></a>
### 3. Loanword preservation rate — the key metric

This targets [Finding 2](01-diagnosis.md#f2) directly, and it is the number that
best reflects whether Hinglish output is usable.

> Of the English words present in the reference, what fraction appear in the
> hypothesis **as recognizable English**?

Given reference `project ka status kya hai`, the English tokens are
{`project`, `status`}.

- Current pipeline yields `projekta ka stetasa kya hai` → **0/2 = 0%**
- A Hinglish-native model should score near 100%

This metric is valuable because it is nearly binary today and does not depend on
the spelling equivalence table for the English half. It will move sharply and
unambiguously if Phase 2a works.

### 4. Latency

Wall-clock from end of audio to inserted text, at p50 and p95. Beam search
([Plan 1c](03-plan.md)) and `large-v3` ([Plan 1b](03-plan.md)) both spend
latency to buy accuracy, and for push-to-talk dictation that trade-off is felt
immediately. A WER win that doubles latency may not be worth shipping.

## Fixture set

### Personal golden set (primary)

~30 utterances recorded by the actual user, because a personal dictation tool
should be tuned to its user's speech, accent and vocabulary.

Deliberately cover all three switching patterns
([02 §1](02-research.md#1-why-code-switching-is-hard)):

| Category | Count | Example |
|---|---|---|
| Inter-sentential | 5 | "Main ghar ja raha hoon. I'll call you later." |
| Intra-sentential | 10 | "Project ka status kya hai" |
| Intra-word | 5 | "File download kar diya", "driving-wala" |
| English-dominant | 5 | "Let's sync at 4, theek hai?" |
| Hindi-dominant | 5 | "Mujhe kal subah jaldi uthna hai" |

Include the technical vocabulary actually dictated — product names, library
names, colleagues' names — since domain vocabulary is cited as the largest
contributor to production WER exceeding benchmark WER.

Store as 16 kHz mono WAV (matching `loadSamples`' expectations) with reference
transcripts in the natural Hinglish a person would type.

**Limitation to state plainly:** ~30 utterances from one speaker is a
*regression guard*, not a benchmark. It will detect "this change broke Hinglish"
reliably and estimate "this model is 20% better" only roughly.

### Public benchmarks (secondary)

For cross-checking that gains are not overfitted to one voice:

| Dataset | Why |
|---|---|
| **HiACC** | Purpose-built code-switched Hinglish |
| **MUCS Hindi-English** | Established code-switching baseline |
| **FLEURS-hi**, **Common Voice hi** | Comparable to published numbers |
| **IndicVoices** | Hardest in reported results |

These mostly have **Devanagari** references, so scoring a romanized hypothesis
against them requires transliterating the reference — which reintroduces exactly
the ambiguity being measured. Use them for relative model comparison, not
absolute quality.

## Harness

A `ZenVoiceHinglishBench` executable target alongside the existing `*Checks`
targets, matching their conventions.

```
swift run -c release ZenVoiceHinglishBench \
    --fixtures Tests/Fixtures/hinglish \
    --model whisper-large-v3-turbo \
    --profile hinglish
```

Output:

```
model: whisper-large-v3-turbo   profile: hinglish   beam: 5

  normalized WER          34.2%
  CER                     18.7%
  loanword preservation   12/47  (25.5%)
  latency p50 / p95       1.8s / 3.1s

  by switching pattern:
    inter-sentential      21.0%
    intra-sentential      37.4%
    intra-word            52.1%     ← worst, as expected
```

Breaking results down by switching pattern matters: an aggregate number hides
that intra-word switching is the hardest case, and a change may help one pattern
while hurting another.

## Baseline to capture first

Before any change, record the current state:

| Configuration | Why |
|---|---|
| `whisper-medium-en` + English profile | What the machine is actually running today ([Finding 3](01-diagnosis.md#f3)) |
| `whisper-medium-multilingual` + Hinglish profile | The intended path as designed |

The gap between these two quantifies how much of the badness is misconfiguration
versus architecture — which determines whether Phase 1a alone changes the
picture.

## Regression gate

Once a baseline exists, wire the harness into `check-release-readiness.sh` as a
**non-blocking report** initially. Promote it to blocking only after the numbers
prove stable across runs — Whisper decoding is not fully deterministic,
especially with temperature fallback, so a naive threshold will produce flaky
failures.

## Reproducing the diagnosis

The transliteration measurement in [01-diagnosis.md](01-diagnosis.md#f1) came
from a standalone script that mirrors `LocalTransliterator.latinScript`. It
should be checked in as `docs/hinglish/tools/translit-check.swift` so the claim
stays verifiable:

```bash
swiftc -O docs/hinglish/tools/translit-check.swift -o /tmp/translit-check
/tmp/translit-check
```

It needs no model or audio, and will keep reporting 8/8 until Phase 2 changes the
approach — at which point it should be updated or retired.

## Order of work

1. Record the personal golden set — **blocks everything else**
2. Implement normalized WER + CER
3. Implement loanword preservation
4. Build the runner
5. Capture both baselines
6. Only then start [Phase 1](03-plan.md)
