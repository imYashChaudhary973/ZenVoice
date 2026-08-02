# Research: Code-Switched Hindi-English ASR

> Historical research snapshot. Model availability, conversion status, and the
> chosen implementation changed after this survey. See
> [05-update-2026-07.md](05-update-2026-07.md) and the
> [current model catalogue](../MODEL_CATALOG.md) for current behavior.

Survey of the literature, models and tooling relevant to making Hinglish
dictation work. Sources are listed at the end and linked inline.

## 1. Why code-switching is hard

Code-switched speech is not simply "two languages at once". The recognized
patterns, in increasing order of difficulty:

| Pattern | Example | Difficulty |
|---|---|---|
| Inter-sentential | "Main ghar ja raha hoon. I'll call you later." | Lowest — segments are monolingual |
| Intra-sentential | "Project ka status kya hai" | High — switch mid-utterance |
| Intra-word | "driving-wala", "book kar diya" | Highest — Hindi morphology on English roots |

ASR systems show a **30–50% relative increase in word error rate** on
code-switched speech versus monolingual input. A monolingual model does not
degrade gracefully; it fails structurally, producing confident and wrong output,
because it is decoding one phoneme inventory against audio drawn from another.

The SwitchLingua benchmark reports a WER spread of **26.97% to 69.53%** across
models on identical code-switched audio — the choice of model dominates
everything else.

Relevance to ZenVoice: intra-sentential and intra-word switching are the normal
case for a technical user dictating in Hinglish, and they are the two hardest
patterns. Findings [1](01-diagnosis.md#f1) and [2](01-diagnosis.md#f2) are the
architecture failing on exactly these.

## 2. Script: the fork in the road

Hinglish **has no standardized written form**. The same word appears in
Devanagari, Roman, or a mix, and romanized spellings vary by writer
(*kya/kyaa*, *hai/hae*, *nahi/nahin/nahee*).

This creates two viable target representations:

**(A) Devanagari output.** Well-supported by Whisper and IndicWhisper, matches
training data, easy to evaluate against standard benchmarks. But English words
get written in Devanagari, and converting back to Latin is lossy
([Finding 2](01-diagnosis.md#f2)).

**(B) Romanized Hinglish output.** Matches how people actually type, keeps
English words as English, and is what downstream LLMs handle best. But it is a
non-standard target with no canonical spelling, which makes evaluation harder and
requires a model trained specifically for it.

ZenVoice's product decision — a Hinglish profile emitting Latin script — commits
to **(B)**. The implementation mistake was trying to reach (B) *via* (A). The
literature's answer is to train the model to emit (B) directly.

> Deepgram's guidance is explicit that transliteration should be a post-processing
> step for downstream consistency, not the mechanism by which you obtain
> romanized text in the first place.

## 3. Models

### 3.1 Whisper-Hindi2Hinglish (Oriserve) — most relevant

Fine-tuned Whisper that **outputs Hinglish in Latin script natively**, which is
precisely ZenVoice's target representation.

| | Prime | Swift |
|---|---|---|
| Focus | Accuracy, noise resistance, hallucination mitigation | Speed |
| Base | Whisper large-v3 | Smaller |

WER versus base Whisper large-v3:

| Dataset | large-v3 | Prime | Swift |
|---|---|---|---|
| Common Voice | 61.94% | **32.43%** | 38.65% |
| FLEURS | 50.84% | **28.68%** | 35.09% |
| IndicVoices | 82.56% | **60.82%** | 65.21% |

- **License:** Apache 2.0 — compatible with redistribution
- **Training data:** ~550 h noisy Indian-accented Hindi, human-in-the-loop labels
- **Roughly 50% relative WER reduction**

**Caveats that must be checked before committing:**

- The reported baseline (large-v3 at 61.94% on Common Voice) is high enough to
  suggest the evaluation romanizes references in a particular way. A ~50%
  relative improvement is credible; the absolute numbers may not transfer.
- Trained on Hindi-dominant data. Behaviour on *English-dominant* Hinglish, or on
  pure English dictation, is unknown — ZenVoice users switch profiles, so a
  Hinglish model that mangles English is a problem.
- **No published GGML/whisper.cpp conversion.** This is the main integration
  risk; see §4.

### 3.2 IndicWhisper / Vistaar (AI4Bharat)

Whisper fine-tuned on 10.7k hours across 12 Indian languages. Lowest WER on
**39 of 59** benchmarks in the Vistaar suite, average reduction of 4.1 WER.

Strong for **Devanagari** Hindi. Does not solve the romanization problem, so it
is the right choice only if ZenVoice also wants a good Devanagari Hindi profile —
a separate goal from Hinglish. Vistaar is also valuable as an **evaluation**
resource regardless of which model ships.

### 3.3 Stock Whisper large-v3 / large-v3-turbo

Available as GGML directly from the whisper.cpp model repository, so integration
is nearly free — the catalog just needs new entries.

- `large-v3-turbo` — ~6× faster than `large-v3` with minimal accuracy loss;
  `q5_0` quantization is ~547 MiB
- **Quantization warning:** for multilingual work, prefer `f16` or `q8_0`.
  Aggressive quantization disproportionately harms languages with smaller
  representation in training — which includes Hindi

This is the cheapest meaningful improvement available: no conversion, no new
runtime, just catalog entries.

### 3.4 Comparison

| Option | Output | Integration cost | Expected Hinglish gain | Risk |
|---|---|---|---|---|
| large-v3-turbo (stock) | Devanagari | **Very low** — catalog entry | Moderate | Very low |
| large-v3 (stock) | Devanagari | **Very low** — catalog entry | Moderate | Low (slow) |
| IndicWhisper | Devanagari | Medium — conversion | Moderate for Hindi, none for romanization | Medium |
| **Whisper-Hindi2Hinglish Prime** | **Latin Hinglish** | **High — conversion unproven** | **Large — removes the whole broken step** | **Medium-High** |

## 4. Integration: HuggingFace → whisper.cpp

ZenVoice runs whisper.cpp via a pinned XCFramework, so any model must exist in
GGML format.

- Conversion uses `convert-h5-to-ggml.py`, which includes a `conv_map` for
  HuggingFace naming conventions
- **Known friction:** most modern checkpoints ship as `safetensors`, while the
  conversion scripts expect `.pt` with a `dims` key. Reports of `KeyError`,
  header errors and broken audio configs are common. A community workaround
  adapts the script to `safetensors.load_file`
- There is an **open request** for an official safetensors→GGUF utility for
  Whisper (whisper.cpp issue #3316), i.e. this is a known rough edge, not a
  solved path

**Implication:** converting Whisper-Hindi2Hinglish is a spike with a real chance
of failure. [03-plan.md](03-plan.md) treats it as a time-boxed experiment with a
fallback, not as a committed deliverable.

## 5. Decoding-level techniques

Available today through whisper.cpp with no new model.

**Beam search + temperature fallback.** Whisper's reference strategy starts with
a 5-beam search and falls back to stochastic sampling at increasing temperature
when generation looks unconfident. whisper.cpp defaults: `entropy_thold` 2.40,
`logprob_thold` −1.00, `temperature_inc` 0.20, up to temperature 1.0. Confidence
is ranked by average log-probability, compression ratio, and no-speech
probability. ZenVoice uses none of this ([Finding 5](01-diagnosis.md#f5)).

**Keyterm / vocabulary boosting.** Boosting up to ~100 domain terms at inference
substantially helps, because domain vocabulary is cited as the single biggest
reason production WER exceeds benchmark WER. Whisper's analogue is
`initial_prompt` conditioning — weaker than a dedicated keyterm API, but real.
ZenVoice already has an application-profile system that could supply per-app
terms.

**Word-level language identification.** Deepgram exposes `language=multi` for
per-word language detection rather than one label per utterance. Whisper has no
equivalent; its single language token is a structural limitation and part of why
[Finding 2](01-diagnosis.md#f2) happens.

## 6. LLM post-correction

An LLM pass over ASR output can fix phonetic confusions, broken compounds and
decoding artefacts while preserving spoken style and code-mixing. Reported
best results use few-shot in-context learning, where examples are built from
diffs between ASR output and ground truth, keeping erroneous segments with
surrounding context.

For ZenVoice this is attractive because the local-LLM runtime already exists.
The obstacle is [Finding 6](01-diagnosis.md#f6): the current guard forbids word
changes, and Hinglish repair is inherently a word change.

A dictionary of common Hinglish words and their romanizations is also recommended
in the practitioner literature — cheap, deterministic, and a natural complement
to (or safety net under) an LLM pass.

## 7. Evaluation resources

| Resource | Contents | Use |
|---|---|---|
| **HiACC** | First code-switched Hinglish corpus with adult *and* child speech | Purpose-built Hinglish benchmark |
| **MUCS / Hindi-English CS corpus** | Hindi-English code-switching speech | Established baseline |
| **Vistaar** (AI4Bharat) | Kathbath, FLEURS, CommonVoice, IndicTTS, MUCS, GramVaani ×12 languages | Broad Hindi benchmarking |
| **IndicVoices** | Natural Indian-language speech | Hardest of the three in reported numbers |

**Metric warning.** Standard WER is misleading for romanized Hinglish, because
*kya*/*kyaa* and *nahi*/*nahin* are both correct. Evaluation needs spelling
normalization before scoring, plus code-switch-aware metrics.
[04-evaluation.md](04-evaluation.md) addresses this.

## 8. What this implies

1. **The romanizer is not fixable** — schwa deletion is context-dependent and
   loanword identity is already lost. Replace the approach, don't tune it.
2. **A Hinglish-native model is the highest-value change**, and its main risk is
   GGML conversion rather than model quality.
3. **Stock `large-v3-turbo` is the cheapest real win** and should land first
   regardless of what happens with the Hinglish-native model.
4. **Decoding improvements are free of new models** but cost latency.
5. **LLM post-correction needs a new guard**, not the existing one.
6. **Nothing above is verifiable today.** Evaluation comes first.

---

## Sources

- [Whisper-Hindi2Hinglish (OriserveAI, GitHub)](https://github.com/OriserveAI/Whisper-Hindi2Hinglish)
- [Oriserve/Whisper-Hindi2Hinglish-Swift (Hugging Face)](https://huggingface.co/Oriserve/Whisper-Hindi2Hinglish-Swift)
- [Adapting Whisper for low-resource Hindi-English Code-Mix speech (Interspeech 2025)](https://www.isca-archive.org/interspeech_2025/biswas25_interspeech.pdf)
- [HiACC: Hinglish adult & children code-switched corpus (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC12329218/)
- [HiACC (ScienceDirect)](https://www.sciencedirect.com/science/article/pii/S2352340925006109)
- [A Comparative Study of LLM-based ASR and Whisper in Low Resource and Code Switching Scenarios (arXiv)](https://arxiv.org/pdf/2412.00721)
- [Hindi-English Code-Switching Speech Corpus (arXiv)](https://arxiv.org/pdf/1810.00662)
- [Vistaar: Diverse Benchmarks and Training Sets for Indian Language ASR (AI4Bharat, GitHub)](https://github.com/AI4Bharat/vistaar)
- [Vistaar (Interspeech 2023)](https://www.isca-archive.org/interspeech_2023/bhogale23_interspeech.pdf)
- [AI4Bharat — ASR research](https://ai4bharat.iitm.ac.in/areas/asr)
- [Hinglish Voice AI: Why ASR Fails and How to Fix It (Deepgram)](https://deepgram.com/learn/hinglish-voice-ai-speech-recognition)
- [whisper.cpp model formats and conversion](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md)
- [whisper.cpp issue #3316 — official safetensors→GGUF conversion](https://github.com/ggml-org/whisper.cpp/issues/3316)
- [whisper.cpp discussion #620 — decoding argument semantics](https://github.com/ggml-org/whisper.cpp/discussions/620)
- [whisper.cpp discussion #1087 — temperature threshold and hallucination](https://github.com/ggml-org/whisper.cpp/discussions/1087)
- [How does temperature fallback with beam search work? (openai/whisper)](https://github.com/openai/whisper/discussions/549)
- [openai/whisper-large-v3-turbo (Hugging Face)](https://huggingface.co/openai/whisper-large-v3-turbo)
