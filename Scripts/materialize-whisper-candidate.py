#!/usr/bin/env python3
"""Merge one LoRA checkpoint into an evaluation-only Whisper model.

This closes the preselection loop: each retained adapter can be converted to a
temporary GGML/Q5 model and exercised by the native ZenVoice runtime. The
output is explicitly non-promotable; final merging still requires an all-gates
selection decision.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import torch
from peft import PeftModel
from transformers import WhisperForConditionalGeneration, WhisperProcessor


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def require_inside_datasets(path: Path, repo_root: Path, label: str) -> Path:
    resolved = path.resolve()
    datasets = (repo_root / "Datasets").resolve()
    try:
        resolved.relative_to(datasets)
    except ValueError as error:
        raise ValueError(f"{label} must be inside {datasets}") from error
    return resolved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint-dir", type=Path, required=True)
    parser.add_argument("--training-result", type=Path, required=True)
    parser.add_argument("--base-model-dir", type=Path, required=True)
    parser.add_argument("--base-model-revision", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    checkpoint = require_inside_datasets(
        args.checkpoint_dir, repo_root, "--checkpoint-dir"
    )
    training_result_path = require_inside_datasets(
        args.training_result, repo_root, "--training-result"
    )
    base_model = require_inside_datasets(
        args.base_model_dir, repo_root, "--base-model-dir"
    )
    output = require_inside_datasets(args.output_dir, repo_root, "--output-dir")
    if output.exists() and any(output.iterdir()):
        parser.error("--output-dir must be empty or absent")

    expected_checkpoints = training_result_path.parent / "checkpoints"
    if checkpoint.parent != expected_checkpoints:
        raise ValueError(
            f"checkpoint must be directly inside {expected_checkpoints}"
        )
    adapter = checkpoint / "adapter_model.safetensors"
    base_weights = base_model / "model.safetensors"
    for path in (adapter, base_weights):
        if not path.is_file():
            raise ValueError(f"required model artifact is missing: {path}")

    training_result = read_json(training_result_path)
    if training_result.get("schema_version") != 1:
        raise ValueError("training result schema_version must be 1")
    if training_result.get("selection_required") is not True:
        raise ValueError("training result is not a conservative candidate run")
    if training_result.get("merged_model_written") is not False:
        raise ValueError("training result unexpectedly wrote a merged model")
    if training_result.get("base_revision") != args.base_model_revision:
        raise ValueError("base model revision does not match training result")
    if training_result.get("base_model_sha256") != sha256(base_weights):
        raise ValueError("base model weights changed after training")
    locked = training_result.get("locked_dataset")
    if not isinstance(locked, dict) or not locked.get("frozen_test_sha256"):
        raise ValueError("training result has no frozen dataset provenance")

    processor = WhisperProcessor.from_pretrained(
        base_model,
        local_files_only=True,
        trust_remote_code=False,
    )
    base = WhisperForConditionalGeneration.from_pretrained(
        base_model,
        local_files_only=True,
        trust_remote_code=False,
        dtype=torch.float32,
    )
    adapted = PeftModel.from_pretrained(base, checkpoint, is_trainable=False)
    merged = adapted.merge_and_unload()
    merged.config.use_cache = True
    output.mkdir(parents=True, exist_ok=True)
    merged.save_pretrained(output, safe_serialization=True)
    processor.save_pretrained(output)

    merged_weights = output / "model.safetensors"
    provenance = {
        "schema_version": 1,
        "purpose": "checkpoint evaluation only",
        "evaluation_only": True,
        "promotion_authorized": False,
        "base_model": str(base_model.relative_to(repo_root)),
        "base_model_revision": args.base_model_revision,
        "base_model_sha256": sha256(base_weights),
        "training_result": str(training_result_path.relative_to(repo_root)),
        "training_result_sha256": sha256(training_result_path),
        "frozen_test_sha256": locked["frozen_test_sha256"],
        "checkpoint_id": checkpoint.name,
        "checkpoint_path": str(checkpoint.relative_to(repo_root)),
        "adapter_sha256": sha256(adapter),
        "merged_model_sha256": sha256(merged_weights),
        "quantized": False,
    }
    (output / "candidate-merge-provenance.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(provenance, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
