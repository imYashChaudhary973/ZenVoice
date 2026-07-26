# Language and Model Benchmark — 2026-07-26

This benchmark compares ZenVoice's installed Whisper models across accents,
languages, speaking rates, synthetic voices, and real multi-speaker Hinglish.

## Test machine

- MacBook Pro `Mac17,2`
- Apple M5, 10 cores (4 performance + 6 efficiency)
- 24 GB unified memory
- macOS 27.0 build `26A5388g`
- whisper.cpp 1.9.1 through ZenVoice's release build
- No thermal or performance warning was reported during the runs

Every model file passed ZenVoice's pinned size and SHA-256 verification before
the benchmark loaded it.

## Method

Synthetic audio used the same microphone stress profile as the accuracy harness:
gain `0.35` plus a deterministic `0.004` noise floor. Latency is measured after
the speaker stops and includes the full transcription call after a one-second
model warm-up.

The matrix contains:

- English: two technical examples, four voices (US, UK, and two Indian), at
  170 and 280 words per minute — 16 clips per model.
- Multilingual: two examples each in Hindi, Spanish, French, German, Tamil,
  Arabic, Japanese, and Mandarin, at 170 and 260 words per minute — 32 clips
  per model.
- Synthetic Hinglish: six technical code-switched examples at 150, 220, and
  300 words per minute — 18 clips per model.
- Real Hinglish: one code-switched segment from each of the 30 speakers in the
  [MUCS 2021 / OpenSLR SLR104](https://openslr.org/104/) Hindi-English test
  set. The selected audio totals 202 seconds.

Word error rate is not meaningful for Japanese and Mandarin because this small
harness does not include a language-specific word tokenizer. Use character
error rate for those languages. Real Hinglish also has no canonical Latin
spelling, so it is judged by English-loanword preservation instead of WER.

## English: accuracy, latency, and memory

| Model | WER | CER | p50 | p95 | RTF | Peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tiny English | 13.8% | 4.6% | 66 ms | 75 ms | 0.020 | 316 MB |
| **Base English** | **9.2%** | 2.7% | **149 ms** | 231 ms | 0.048 | 503 MB |
| Medium English (retired) | 6.6% | **0.8%** | 1,343 ms | 1,636 ms | 0.407 | 3,475 MB |
| Tiny multilingual | 15.8% | 3.9% | 83 ms | 135 ms | 0.026 | 316 MB |
| Medium multilingual | 8.6% | 1.5% | 1,213 ms | 1,653 ms | 0.379 | 3,475 MB |
| Turbo multilingual | 8.6% | 1.7% | 1,936 ms | 2,569 ms | 0.624 | 1,350 MB |
| Apex Hinglish specialist | 21.1% | 5.1% | 1,601 ms | 1,657 ms | 0.498 | 1,956 MB |

Base English is the strongest low-latency English option in this matrix: it
gives up 2.6 WER points to the retired Medium English model but is about nine
times faster at the median and uses roughly one seventh of the peak memory.
The current Turbo recommendation still favors accuracy over response time; the
right default depends on which trade-off the product wants.

Apex's 21.1% English WER confirms that it must remain restricted to the
Hinglish profile.

### Accent effect

| Model | US | UK | Indian Aman | Indian Tara |
| --- | ---: | ---: | ---: | ---: |
| Tiny English | 7.9% | 7.9% | 21.1% | 18.4% |
| Base English | 2.6% | 7.9% | 10.5% | 15.8% |
| Medium multilingual | 2.6% | 7.9% | 7.9% | 15.8% |

The difficult terms were consistently `pull request` and `Postgres`. A
personal Indian-English recording set is needed before treating the synthetic
accent gap as a production estimate.

## Multilingual results

### Overall

| Model | WER | CER | p50 | p95 | RTF |
| --- | ---: | ---: | ---: | ---: | ---: |
| Tiny multilingual | 64.5% | 34.8% | **91 ms** | 192 ms | 0.027 |
| **Medium multilingual** | 14.5% | **5.0%** | 1,173 ms | 1,932 ms | 0.347 |
| **Turbo multilingual** | **13.2%** | 5.1% | 1,451 ms | **1,602 ms** | 0.397 |

### Character error rate by language

| Language | Tiny | Medium | Turbo | Best measured |
| --- | ---: | ---: | ---: | --- |
| Hindi | 207.4% | 18.1% | **14.9%** | Turbo |
| Spanish | 26.2% | **0.5%** | 1.9% | Medium |
| French | 18.1% | **2.9%** | 4.8% | Medium |
| German | 3.3% | 1.4% | **0.0%** | Turbo |
| Tamil | 43.1% | 13.8% | **12.3%** | Turbo |
| Arabic | 7.6% | 1.9% | **1.3%** | Turbo |
| Japanese | 17.2% | 8.6% | **4.3%** | Turbo |
| Mandarin | 51.6% | **1.6%** | 16.1% | Medium |

There is no universal multilingual winner in this small matrix. Turbo wins five
of eight languages and uses about 61% less peak memory than Medium, while Medium
is faster at the median and is substantially better on this Mandarin sample.
Tiny is fast but not accurate enough to be the recommended multilingual model.

## Hinglish

### Synthetic stress set

| Model | Normalized WER | CER | Loanwords | p50 | p95 | RTF |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tiny multilingual | 78.4% | 34.2% | 17/66 (26%) | 78 ms | 91 ms | 0.029 |
| Medium multilingual | 92.2% | 49.8% | 0/66 (0%) | 1,491 ms | 3,814 ms | 0.589 |
| Turbo multilingual | 73.9% | 36.2% | 11/66 (17%) | 1,555 ms | 1,637 ms | 0.571 |
| **Apex, stressed audio** | **17.0%** | **7.7%** | **51/66 (77%)** | 807–1,757 ms | 860–3,219 ms | 0.299–0.678 |
| **Apex, clean audio** | **15.7%** | **5.2%** | **54/66 (82%)** | 817–1,445 ms | 867–1,916 ms | 0.301–0.510 |

Apex is the only viable Hinglish model. The general multilingual models either
phoneticize English words or lose them completely.

ZenVoice's existing regression fixture also passed at 23/26 loanwords (88%).
The larger stress set is intentionally harder and adds more technical terms.

### Apex by speaking rate under microphone stress

| Rate | WER | CER | Loanwords |
| --- | ---: | ---: | ---: |
| 150 wpm | 13.7% | 5.3% | 18/22 (82%) |
| 220 wpm | 17.6% | 7.0% | 17/22 (77%) |
| 300 wpm | 19.6% | 10.7% | 16/22 (73%) |

Fast speech mainly loses the first technical word and confuses `server`,
`pull request`, `build`, `database`, and `verify`.

### Apex on 30 real speakers

| Input | Loanwords | p50 | p95 | RTF | Throughput |
| --- | ---: | ---: | ---: | ---: | ---: |
| Published MUCS audio | **95/122 (78%)** | **824 ms** | **887 ms** | **0.123** | **8× real time** |
| Added microphone stress | 95/122 (78%) | 826 ms | 1,083 ms | 0.127 | 8× real time |

This sample covers one utterance from every available speaker, not 30 clips from
one person. The downloaded official archive was
`Hindi-English_test.tar.gz`, 443,929,204 bytes, SHA-256
`93e358b3bf8233a897fcd353c1f4f98fdda6b8c01b7eed17a70c7dd26e984b37`.

## Findings and next actions

1. Offer Base English as the responsive English choice. Keep Turbo as the
   accuracy-first default unless the product explicitly prioritizes subsecond
   insertion latency.
2. Keep Apex exclusive to Hinglish. Its real 30-speaker result supports the
   current recommendation.
3. Prefer Turbo as the broad multilingual recommendation when memory matters;
   retain Medium as an override, especially for Mandarin and Spanish.
4. Do not recommend Tiny multilingual when accuracy matters.
5. Add a personal recorded set for Indian English and conversational Hinglish.
   Synthetic voices and tutorial speech do not represent hesitant dictation.
6. Apex emitted isolated Cyrillic or Korean characters in 3 of 18 clean
   synthetic clips. The regression check now rejects every unexpected
   alphabetic script, not only Devanagari. A narrowly scoped app-side cleanup
   policy remains an open product fix.
7. Apex latency varied materially between the first post-build runs and later
   warm system-cache runs despite no macOS thermal warning. Preserve p50/p95
   ranges and do not advertise a single guaranteed latency.

## Reproduce

```sh
swift build -c release --product ZenVoiceLanguageBench

.build/release/ZenVoiceLanguageBench \
  --model "$HOME/Library/Application Support/ZenVoice/Models/ggml-base.en.bin" \
  --suite english

.build/release/ZenVoiceLanguageBench \
  --model "$HOME/Library/Application Support/ZenVoice/Models/ggml-large-v3-turbo-q5_0.bin" \
  --suite multilingual

.build/release/ZenVoiceLanguageBench \
  --model "$HOME/Library/Application Support/ZenVoice/Models/ggml-hindi2hinglish-apex-q8_0.bin" \
  --suite hinglish
```
