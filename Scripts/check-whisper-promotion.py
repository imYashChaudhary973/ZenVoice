#!/usr/bin/env python3
"""Verify promotion authorization and fail-closed artifact tamper handling."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def run(arguments: list[str], expected_exit: int = 0) -> None:
    result = subprocess.run(
        arguments,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != expected_exit:
        raise RuntimeError(
            f"expected exit {expected_exit}, got {result.returncode}: "
            f"{' '.join(arguments)}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    datasets = repo_root / "Datasets"
    fixture = Path(tempfile.mkdtemp(prefix=".promotion-fixture-", dir=datasets))
    try:
        artifact_dir = fixture / "artifact"
        artifact_dir.mkdir()
        q5 = artifact_dir / "ggml-model-q5_0.bin"
        q5.write_bytes(b"selected q5 model")
        gates = {
            "accuracy": True,
            "semantic_safety": True,
            "latency": True,
            "memory": True,
            "license": True,
        }
        decision = fixture / "selection.json"
        write_json(
            decision,
            {
                "schema_version": 1,
                "frozen_test_sha256": "f" * 64,
                "selected": {
                    "checkpoint_id": "checkpoint-1",
                    "passes_all_gates": True,
                    "gates": gates,
                    "metrics": {"q5_model_bytes": q5.stat().st_size},
                },
                "promotion_authorized": False,
            },
        )
        inventory = artifact_dir / "artifact-inventory.json"
        write_json(
            inventory,
            {
                "schema_version": 1,
                "selection": {
                    "selection_decision_sha256": sha256(decision),
                    "checkpoint_id": "checkpoint-1",
                    "frozen_test_sha256": "f" * 64,
                },
                "artifacts": {
                    "q5_0": {
                        "path": q5.name,
                        "bytes": q5.stat().st_size,
                        "sha256": sha256(q5),
                    }
                },
            },
        )
        license_review = fixture / "license-review.json"
        write_json(
            license_review,
            {
                "schema_version": 1,
                "approved": True,
                "attribution_recorded": True,
                "reviewed_by": "fixture-reviewer",
                "reviewed_at": "2026-08-14T12:00:00Z",
                "licenses": ["Apache-2.0", "CC-BY-4.0"],
                "attribution_notice": "Fixture model attribution",
            },
        )
        distribution = fixture / "distribution-review.json"
        write_json(
            distribution,
            {
                "schema_version": 1,
                "approved": True,
                "redistribution_allowed": True,
                "reviewed_by": "fixture-reviewer",
                "reviewed_at": "2026-08-14T12:00:00Z",
                "stable_download_url": "https://example.invalid/model.bin",
                "model_card_url": "https://example.invalid/model-card",
                "artifact_sha256": sha256(q5),
                "artifact_bytes": q5.stat().st_size,
            },
        )
        verifier = repo_root / "Scripts" / "verify-whisper-promotion.py"
        arguments = [
            sys.executable,
            str(verifier),
            "--selection-decision",
            str(decision),
            "--artifact-inventory",
            str(inventory),
            "--license-review",
            str(license_review),
            "--distribution-review",
            str(distribution),
            "--output",
            str(fixture / "promotion.json"),
        ]
        run(arguments)
        approval = json.loads((fixture / "promotion.json").read_text())
        if approval.get("promotion_authorized") is not True:
            raise RuntimeError("valid all-gates artifact was not authorized")

        q5.write_bytes(b"tampered q5 model")
        arguments[-1] = str(fixture / "tampered-promotion.json")
        run(arguments, expected_exit=1)
        print(
            "Whisper promotion checks passed: all-gates authorization and "
            "post-quantization tamper rejection"
        )
        return 0
    finally:
        if fixture.parent.resolve() != datasets.resolve():
            raise RuntimeError("refusing to remove fixture outside Datasets")
        shutil.rmtree(fixture)


if __name__ == "__main__":
    raise SystemExit(main())
