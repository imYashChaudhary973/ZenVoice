#!/usr/bin/env python3
"""Merge only the Whisper LoRA adapter selected by composite evidence.

The decision, adapter, and base hashes are verified before loading. The merged
model remains below ``Datasets`` and carries provenance linking it to the frozen
test hash and selection gates. This step does not quantize or authorize release.
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
    parser.add_argument("--selection-decision", type=Path, required=True)
    parser.add_argument("--base-model-dir", type=Path, required=True)
    parser.add_argument("--base-model-revision", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    decision_path = require_inside_datasets(
        args.selection_decision, repo_root, "--selection-decision"
    )
    base_model = require_inside_datasets(
        args.base_model_dir, repo_root, "--base-model-dir"
    )
    output = require_inside_datasets(args.output_dir, repo_root, "--output-dir")
    if output.exists() and any(output.iterdir()):
        parser.error("--output-dir must be empty or absent")

    decision = read_json(decision_path)
    if decision.get("schema_version") != 1:
        raise ValueError("selection decision schema_version must be 1")
    selected = decision.get("selected")
    if not isinstance(selected, dict) or not selected.get("passes_all_gates"):
        raise ValueError("selection decision contains no all-gates candidate")
    gates = selected.get("gates")
    if not isinstance(gates, dict) or not gates or not all(gates.values()):
        raise ValueError("selected checkpoint does not pass every recorded gate")
    checkpoint_value = selected.get("checkpoint_path")
    if not isinstance(checkpoint_value, str):
        raise ValueError("selected checkpoint path is missing")
    checkpoint = require_inside_datasets(
        repo_root / checkpoint_value,
        repo_root,
        "selected checkpoint",
    )
    adapter = checkpoint / "adapter_model.safetensors"
    if not adapter.is_file():
        raise ValueError(f"selected adapter is missing: {adapter}")
    if sha256(adapter) != selected.get("adapter_sha256"):
        raise ValueError("selected adapter hash changed after evaluation")

    base_weights = base_model / "model.safetensors"
    if not base_weights.is_file():
        raise ValueError(f"base model weights are missing: {base_weights}")
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
    adapted = PeftModel.from_pretrained(
        base,
        checkpoint,
        is_trainable=False,
    )
    merged = adapted.merge_and_unload()
    merged.config.use_cache = True
    output.mkdir(parents=True, exist_ok=True)
    merged.save_pretrained(output, safe_serialization=True)
    processor.save_pretrained(output)

    merged_weights = output / "model.safetensors"
    provenance = {
        "schema_version": 1,
        "base_model": str(base_model.relative_to(repo_root)),
        "base_model_revision": args.base_model_revision,
        "base_model_sha256": sha256(base_weights),
        "selection_decision": str(decision_path.relative_to(repo_root)),
        "selection_decision_sha256": sha256(decision_path),
        "frozen_test_sha256": decision.get("frozen_test_sha256"),
        "checkpoint_id": selected.get("checkpoint_id"),
        "adapter_sha256": sha256(adapter),
        "selection_metrics": selected.get("metrics"),
        "selection_gates": gates,
        "merged_model_sha256": sha256(merged_weights),
        "quantized": False,
        "promotion_authorized": False,
    }
    (output / "merge-provenance.json").write_text(
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
