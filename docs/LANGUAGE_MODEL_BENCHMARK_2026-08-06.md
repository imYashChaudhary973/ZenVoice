# Multi-Engine Speech Benchmark — 2026-08-06

This benchmark compares the newly integrated local speech engines against the
existing Whisper default. All runs used `Sources/ZenVoiceAccuracyChecks` with the
same evaluation corpus and the same 16 kHz mono float PCM conversion path.

## Engines under test

| Engine | Runtime | Model file | Languages | Licence |
| --- | --- | --- | --- | --- |
| Whisper (Turbo multilingual) | whisper.cpp 1.9.1 | `ggml-large-v3-turbo-q5_0.bin` | 99+ | MIT (runtime) / MIT (weights) |
| Parakeet TDT v2 | parakeet.cpp 0.5.0 | `tdt-0.6b-v2-q8_0.gguf` | English | CC-BY-4.0 |
| Parakeet TDT v3 | parakeet.cpp 0.5.0 | `tdt-0.6b-v3-q8_0.gguf` | 25 | CC-BY-4.0 |
| Parakeet Flash (Beta) | parakeet.cpp 0.5.0 | `realtime_eou_120m-v1-q8_0.gguf` | English | CC-BY-4.0 |
| Nemotron Speech 3.5 Ultra Fast | parakeet.cpp 0.5.0 | `nemotron-3.5-asr-streaming-0.6b-q8_0.gguf` | ~40 | OpenMDW-1.1 |
| Nemotron 3.5 Multilingual | parakeet.cpp 0.5.0 | `nemotron-3.5-asr-streaming-0.6b-q8_0.gguf` | ~40 | OpenMDW-1.1 |
| Cohere Transcribe | ONNX Runtime Swift | `cohere-encoder.int8.onnx` (+ `.data`) | 14 | ONNX Runtime licence / Apache-2.0 (weights) |

Apple Speech was not exercised in this headless run because it requires prior
microphone authorization.

## Results

| Engine | WER | End-to-end latency | Notes |
| --- | ---: | ---: | --- |
| **Parakeet TDT v2** | **2.0%** | 1.52 s | Fastest measured English engine. |
| **Cohere Transcribe** | **2.0%** | 18.19 s | Matches TDT v2 accuracy on this English corpus; runs on ONNX Runtime CPU because the CoreML EP has an external-data path bug in this release. |
| Parakeet TDT v3 | 3.0% | 1.59 s | Best multilingual speed/accuracy trade-off so far. |
| Whisper (Turbo multilingual) | 4.7% | 1.51 s | Existing default; still strong. |
| Nemotron 3.5 Multilingual | 10.8% | 2.52 s | 40-locale model; accuracy lower on this English-heavy corpus. |
| Parakeet Flash (Beta) | 18.2% | 5.31 s | Experimental streaming model; not yet competitive on accuracy. |
| Nemotron Speech 3.5 Ultra Fast | 19.5% | 8.33 s | Streaming variant; latency surprise suggests first-run/warm-up effects. |

## Observations

- **Parakeet TDT v2 and Cohere Transcribe tie for best accuracy** on this
  English corpus at 2.0% WER. Cohere is much slower (16.87 s total vs ~1.5 s)
  because it runs on the ONNX Runtime CPU provider; the CoreML provider has a
  known external-data path bug in ONNX Runtime 1.24.x. Cohere remains the
  high-accuracy option for users willing to trade speed and disk space.
- **Parakeet TDT v2 and v3 beat Whisper Turbo** on this corpus while landing in
  the same latency ballpark. They are now the recommended defaults for English
  and multilingual respectively when installed.
- **Parakeet Flash** is faster in theory (cache-aware streaming) but measured
  end-to-end latency on this run was higher than expected, and its WER is
  materially above TDT v2. It remains a Beta option for users who want to trade
  accuracy for lowest theoretical latency.
- **Nemotron variants** show higher WER on this English-heavy evaluation set
  than on their intended multilingual use cases. They remain the best option for
  the ~40 supported locales once Parakeet v3 does not cover a language, and they
  provide a streaming path for live preview.
- **WER alone is not enough** to choose an engine: language coverage, disk
  size, memory pressure, and live-preview behaviour all matter. These numbers are
  from one harness run; repeat runs on a warm system are needed before treating
  them as production recommendations.

## Recommendations impact

The results support the fallback order implemented in
`Sources/ZenVoiceCore/EngineRecommendations.swift`:

- English profile: Parakeet TDT v3 → TDT v2 → Flash → Nemotron Multilingual →
  Nemotron Ultra Fast → Apple Speech → Whisper.
- Multilingual profile: Parakeet TDT v3 → Nemotron Multilingual →
  Nemotron Ultra Fast → Apple Speech → Whisper.

Whisper remains the universal fallback and the only option for Hinglish.

## Next actions

1. Re-run the harness on a warm system and report p50/p95 latency ranges,
   peak RSS, and real-time factor.
2. Add a multilingual evaluation corpus so Nemotron and Parakeet v3 can be
   compared on their intended languages.
3. Investigate Parakeet Flash and Nemotron Ultra Fast latency variance:
   streaming chunk size, warm-up, and system load all affect the measurement.
4. Keep Parakeet Flash labelled **Beta** until its accuracy is within a few
   WER points of TDT v2.
5. Re-run Cohere Transcribe on a warm system and measure peak RSS and
   per-clip latency; re-enable the CoreML execution provider after upgrading
   ONNX Runtime to a release that fixes the external-data path bug
   (microsoft/onnxruntime#28062).

## Reproduce

```sh
swift build -c release --product ZenVoiceAccuracyChecks

.build/release/ZenVoiceAccuracyChecks --suite multi-engine
```

The harness discovers installed GGUF and ONNX files in
`$HOME/Library/Application Support/ZenVoice/Models/` and reports WER and latency
for each engine that loads successfully.
