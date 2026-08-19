#!/usr/bin/env python3
"""Convert a local Hugging Face Whisper checkpoint and quantize it to Q5_0.

The converter and quantizer must already be present locally. This wrapper uses
argument arrays rather than a shell, records exact tool revisions and hashes,
and restricts all model artifacts to ZenVoice's gitignored ``Datasets`` tree.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_revision(directory: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(directory), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def require_inside(path: Path, parent: Path, label: str) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(parent)
    except ValueError as error:
        raise ValueError(f"{label} must be inside {parent}") from error
    return resolved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--whisper-cpp-dir", type=Path, required=True)
    parser.add_argument("--openai-whisper-dir", type=Path, required=True)
    parser.add_argument("--model-revision", required=True)
    parser.add_argument(
        "--language-capability",
        choices=("english", "multilingual", "hinglish"),
        default="multilingual",
        help=(
            "runtime language capability; controls the Q5 filename so "
            "ZenVoice cannot misclassify an evaluation artifact"
        ),
    )
    parser.add_argument(
        "--require-selection-provenance",
        action="store_true",
        help="require an all-gates merge-provenance.json beside the model",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    datasets_root = (repo_root / "Datasets").resolve()
    model_dir = require_inside(args.model_dir, datasets_root, "--model-dir")
    output = require_inside(args.output_dir, datasets_root, "--output-dir")
    whisper_cpp = require_inside(
        args.whisper_cpp_dir, datasets_root, "--whisper-cpp-dir"
    )
    openai_whisper = require_inside(
        args.openai_whisper_dir, datasets_root, "--openai-whisper-dir"
    )
    if output.exists() and any(output.iterdir()):
        parser.error("--output-dir must be empty or absent")

    converter = whisper_cpp / "models" / "convert-h5-to-ggml.py"
    quantizer = whisper_cpp / "build" / "bin" / "whisper-quantize"
    mel_filters = openai_whisper / "whisper" / "assets" / "mel_filters.npz"
    for path in (converter, quantizer, mel_filters):
        if not path.is_file():
            raise ValueError(f"required conversion input not found: {path}")
    for name in ("config.json", "vocab.json", "added_tokens.json"):
        if not (model_dir / name).is_file():
            raise ValueError(f"model conversion input not found: {model_dir / name}")

    selection_provenance = None
    candidate_provenance = None
    selection_provenance_path = model_dir / "merge-provenance.json"
    candidate_provenance_path = model_dir / "candidate-merge-provenance.json"
    if selection_provenance_path.is_file() and candidate_provenance_path.is_file():
        raise ValueError("model has conflicting selection and candidate provenance")
    if selection_provenance_path.is_file():
        selection_provenance = json.loads(
            selection_provenance_path.read_text(encoding="utf-8")
        )
        if not isinstance(selection_provenance, dict):
            raise ValueError("merge-provenance.json must contain an object")
        if selection_provenance.get("merged_model_sha256") != sha256(
            model_dir / "model.safetensors"
        ):
            raise ValueError("merged model hash does not match its provenance")
    elif candidate_provenance_path.is_file():
        candidate_provenance = json.loads(
            candidate_provenance_path.read_text(encoding="utf-8")
        )
        if not isinstance(candidate_provenance, dict):
            raise ValueError("candidate-merge-provenance.json must contain an object")
        if (
            candidate_provenance.get("evaluation_only") is not True
            or candidate_provenance.get("promotion_authorized") is not False
        ):
            raise ValueError("candidate provenance is not evaluation-only")
        if candidate_provenance.get("merged_model_sha256") != sha256(
            model_dir / "model.safetensors"
        ):
            raise ValueError("candidate model hash does not match its provenance")
    if args.require_selection_provenance:
        if selection_provenance is None:
            raise ValueError("selection merge provenance is required")
        gates = selection_provenance.get("selection_gates")
        if not isinstance(gates, dict) or not gates or not all(gates.values()):
            raise ValueError("selection provenance does not pass every gate")
        if selection_provenance.get("quantized") is not False:
            raise ValueError("selection provenance has an invalid quantized state")

    output.mkdir(parents=True, exist_ok=True)
    conversion_log = output / "conversion.log"
    offline_environment = os.environ.copy()
    offline_environment["HF_HUB_OFFLINE"] = "1"
    offline_environment["TRANSFORMERS_OFFLINE"] = "1"
    with conversion_log.open("w", encoding="utf-8", newline="\n") as log:
        subprocess.run(
            [
                sys.executable,
                str(converter),
                str(model_dir),
                str(openai_whisper),
                str(output),
            ],
            check=True,
            stdout=log,
            stderr=subprocess.STDOUT,
            env=offline_environment,
        )

    f16_model = output / "ggml-model.bin"
    capability_marker = {
        "english": ".en.",
        "multilingual": "-",
        "hinglish": ".hinglish.",
    }[args.language_capability]
    q5_model = output / f"ggml-model{capability_marker}q5_0.bin"
    subprocess.run(
        [str(quantizer), str(f16_model), str(q5_model), "q5_0"],
        check=True,
    )

    inventory = {
        "schema_version": 1,
        "source_model": str(model_dir.relative_to(repo_root)),
        "source_model_revision": args.model_revision,
        "format": "whisper.cpp GGML",
        "quantization": "q5_0",
        "language_capability": args.language_capability,
        "tooling": {
            "whisper_cpp_revision": git_revision(whisper_cpp),
            "openai_whisper_revision": git_revision(openai_whisper),
        },
        "selection": (
            {
                "merge_provenance_sha256": sha256(selection_provenance_path),
                "frozen_test_sha256": selection_provenance.get(
                    "frozen_test_sha256"
                ),
                "checkpoint_id": selection_provenance.get("checkpoint_id"),
                "selection_decision_sha256": selection_provenance.get(
                    "selection_decision_sha256"
                ),
            }
            if selection_provenance is not None
            else None
        ),
        "evaluation_candidate": (
            {
                "candidate_merge_provenance_sha256": sha256(
                    candidate_provenance_path
                ),
                "frozen_test_sha256": candidate_provenance.get(
                    "frozen_test_sha256"
                ),
                "checkpoint_id": candidate_provenance.get("checkpoint_id"),
                "adapter_sha256": candidate_provenance.get("adapter_sha256"),
                "promotion_authorized": False,
            }
            if candidate_provenance is not None
            else None
        ),
        "artifacts": {
            "f16": {
                "path": f16_model.name,
                "bytes": f16_model.stat().st_size,
                "sha256": sha256(f16_model),
            },
            "q5_0": {
                "path": q5_model.name,
                "bytes": q5_model.stat().st_size,
                "sha256": sha256(q5_model),
            },
        },
    }
    (output / "artifact-inventory.json").write_text(
        json.dumps(inventory, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(inventory, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
