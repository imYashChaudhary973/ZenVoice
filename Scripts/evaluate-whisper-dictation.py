#!/usr/bin/env python3
"""Evaluate a local Hugging Face Whisper model on a ZenVoice manifest.

The evaluator reports normalized WER, error counts, latency, real-time factor,
and silence hallucinations. Predictions are written locally for auditability;
nothing is uploaded.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import sys
import time
import wave
from pathlib import Path
from typing import Any

import jiwer
import numpy as np
import torch
from transformers import WhisperForConditionalGeneration, WhisperProcessor


SAMPLE_RATE = 16_000


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_pcm16_mono(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as reader:
        if (
            reader.getnchannels() != 1
            or reader.getsampwidth() != 2
            or reader.getframerate() != SAMPLE_RATE
        ):
            raise ValueError(f"expected 16 kHz mono 16-bit PCM WAV: {path}")
        frames = reader.readframes(reader.getnframes())
    return np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0


def read_manifest(path: Path, repo_root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            audio = (repo_root / row["audio"]).resolve()
            try:
                audio.relative_to(repo_root)
            except ValueError as error:
                raise ValueError(
                    f"manifest audio escapes repository at line {line_number}"
                ) from error
            if not audio.is_file():
                raise ValueError(f"missing audio at line {line_number}: {audio}")
            text = " ".join(str(row["text"]).split())
            if not text:
                raise ValueError(f"empty text at line {line_number}")
            rows.append(
                {
                    "audio": audio,
                    "text": text,
                    "duration_seconds": float(row["duration_seconds"]),
                }
            )
    if not rows:
        raise ValueError(f"empty manifest: {path}")
    return rows


def synchronize(device: torch.device) -> None:
    if device.type == "mps":
        torch.mps.synchronize()


def transcribe(
    samples: np.ndarray,
    processor: WhisperProcessor,
    model: WhisperForConditionalGeneration,
    device: torch.device,
) -> tuple[str, float]:
    inputs = processor.feature_extractor(
        samples,
        sampling_rate=SAMPLE_RATE,
        return_tensors="pt",
        return_attention_mask=True,
    )
    input_features = inputs.input_features.to(device)
    attention_mask = inputs.attention_mask.to(device)
    synchronize(device)
    started = time.perf_counter()
    with torch.inference_mode():
        predicted = model.generate(
            input_features=input_features,
            attention_mask=attention_mask,
            max_new_tokens=224,
        )
    synchronize(device)
    elapsed = time.perf_counter() - started
    text = processor.tokenizer.batch_decode(
        predicted,
        skip_special_tokens=True,
    )[0].strip()
    return text, elapsed


def percentile(values: list[float], percentile_value: float) -> float:
    return float(np.percentile(np.asarray(values), percentile_value))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--model-revision", required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--max-samples", type=int)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    datasets_root = (repo_root / "Datasets").resolve()
    model_dir = args.model_dir.resolve()
    output = args.output_dir.resolve()
    for path, label in [(model_dir, "--model-dir"), (output, "--output-dir")]:
        try:
            path.relative_to(datasets_root)
        except ValueError:
            parser.error(f"{label} must be inside the gitignored Datasets directory")
    if output.exists() and any(output.iterdir()):
        parser.error("--output-dir must be empty or absent")

    rows = read_manifest(args.manifest, repo_root)
    if args.max_samples is not None:
        rows = rows[: args.max_samples]
    output.mkdir(parents=True, exist_ok=True)

    processor = WhisperProcessor.from_pretrained(
        model_dir,
        local_files_only=True,
        trust_remote_code=False,
    )
    model = WhisperForConditionalGeneration.from_pretrained(
        model_dir,
        local_files_only=True,
        trust_remote_code=False,
        dtype=torch.float32,
    )
    device = torch.device(
        "mps" if torch.backends.mps.is_available() else "cpu"
    )
    model.to(device)
    model.eval()

    predictions: list[dict[str, Any]] = []
    latencies: list[float] = []
    references: list[str] = []
    hypotheses: list[str] = []
    normalize = processor.tokenizer.normalize

    for index, row in enumerate(rows, start=1):
        samples = load_pcm16_mono(row["audio"])
        hypothesis, latency = transcribe(samples, processor, model, device)
        reference_normalized = normalize(row["text"])
        hypothesis_normalized = normalize(hypothesis)
        references.append(reference_normalized)
        hypotheses.append(hypothesis_normalized)
        latencies.append(latency)
        predictions.append(
            {
                "audio": str(row["audio"].relative_to(repo_root)),
                "reference": row["text"],
                "prediction": hypothesis,
                "reference_normalized": reference_normalized,
                "prediction_normalized": hypothesis_normalized,
                "latency_seconds": round(latency, 4),
            }
        )
        if index == 1 or index % 20 == 0 or index == len(rows):
            print(f"evaluated {index}/{len(rows)}", flush=True)

    word_output = jiwer.process_words(references, hypotheses)
    silence_predictions = []
    for seconds in (1, 5, 10):
        text, latency = transcribe(
            np.zeros(SAMPLE_RATE * seconds, dtype=np.float32),
            processor,
            model,
            device,
        )
        silence_predictions.append(
            {
                "seconds": seconds,
                "prediction": text,
                "latency_seconds": round(latency, 4),
            }
        )

    total_audio_seconds = sum(row["duration_seconds"] for row in rows)
    total_latency_seconds = sum(latencies)
    metrics = {
        "schema_version": 1,
        "model_revision": args.model_revision,
        "model_directory": str(model_dir.relative_to(repo_root)),
        "model_sha256": sha256(model_dir / "model.safetensors"),
        "manifest": str(args.manifest),
        "manifest_sha256": sha256(args.manifest),
        "device": device.type,
        "clips": len(rows),
        "audio_hours": round(total_audio_seconds / 3600, 4),
        "wer_percent": round(word_output.wer * 100, 3),
        "hits": word_output.hits,
        "substitutions": word_output.substitutions,
        "deletions": word_output.deletions,
        "insertions": word_output.insertions,
        "latency_p50_seconds": round(statistics.median(latencies), 4),
        "latency_p95_seconds": round(percentile(latencies, 95), 4),
        "real_time_factor": round(
            total_latency_seconds / total_audio_seconds,
            4,
        ),
        "silence_predictions": silence_predictions,
    }
    with (output / "predictions.jsonl").open(
        "w", encoding="utf-8", newline="\n"
    ) as handle:
        for row in predictions:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    (output / "metrics.json").write_text(
        json.dumps(metrics, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(metrics, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, wave.Error, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
