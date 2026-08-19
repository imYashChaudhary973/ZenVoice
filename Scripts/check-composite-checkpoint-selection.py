#!/usr/bin/env python3
"""Verify fail-closed composite Whisper checkpoint selection."""

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


def run(arguments: list[str], expected_exit: int = 0) -> subprocess.CompletedProcess[str]:
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
    return result


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    datasets = repo_root / "Datasets"
    fixture = Path(
        tempfile.mkdtemp(prefix=".checkpoint-selection-fixture-", dir=datasets)
    )
    try:
        locked = fixture / "locked"
        locked.mkdir()
        artifacts = []
        for name, content in (
            ("train.jsonl", "train\n"),
            ("validation.jsonl", "validation\n"),
            ("test.jsonl", "test\n"),
            ("summary.json", "{}\n"),
        ):
            path = locked / name
            path.write_text(content, encoding="utf-8")
            artifacts.append(path)
        write_json(
            locked / "FROZEN_TEST_LOCK.json",
            {
                "schema_version": 1,
                "dataset_version": "selection-fixture-v1",
                "immutable_artifacts": {
                    path.name: sha256(path) for path in artifacts
                },
                "frozen_test_sha256": sha256(locked / "test.jsonl"),
            },
        )

        baseline = fixture / "baseline.json"
        runtime_model = fixture / "runtime-model.bin"
        runtime_model.write_bytes(b"runtime-model")
        baseline_inventory = fixture / "baseline-inventory.json"
        write_json(
            baseline_inventory,
            {
                "schema_version": 1,
                "artifacts": {
                    "q5_0": {
                        "path": runtime_model.name,
                        "sha256": sha256(runtime_model),
                    }
                },
            },
        )
        runtime_log = fixture / "runtime.log"
        runtime_log.write_text("verified runtime log\n", encoding="utf-8")
        lifecycle_logs = []
        for index in range(3):
            lifecycle = fixture / f"lifecycle-{index}.log"
            lifecycle.write_text(f"lifecycle {index}\n", encoding="utf-8")
            lifecycle_logs.append(lifecycle)
        hf_metrics = fixture / "hf-metrics.json"
        write_json(
            hf_metrics,
            {
                "manifest_sha256": sha256(locked / "test.jsonl"),
                "wer_percent": 20.0,
            },
        )
        license_review = fixture / "license-review.json"
        write_json(
            license_review,
            {
                "schema_version": 1,
                "approved": True,
                "attribution_recorded": True,
            },
        )
        common_evidence = {
            "runtime_model_path": str(runtime_model.relative_to(repo_root)),
            "runtime_model_sha256": sha256(runtime_model),
            "runtime_inventory": str(baseline_inventory.relative_to(repo_root)),
            "runtime_inventory_sha256": sha256(baseline_inventory),
            "runtime_log": str(runtime_log.relative_to(repo_root)),
            "runtime_log_sha256": sha256(runtime_log),
            "runtime_lifecycle_logs": [
                str(path.relative_to(repo_root)) for path in lifecycle_logs
            ],
            "runtime_lifecycle_log_sha256": [
                sha256(path) for path in lifecycle_logs
            ],
            "hf_metrics": str(hf_metrics.relative_to(repo_root)),
            "hf_metrics_sha256": sha256(hf_metrics),
            "hf_wer_percent": 20.0,
            "license_review": str(license_review.relative_to(repo_root)),
            "license_review_sha256": sha256(license_review),
            "license_review_passed": True,
            "attribution_recorded": True,
            "frozen_test_sha256": sha256(locked / "test.jsonl"),
            "locked_dataset_kind": "private_zenvoice_dictation",
            "representative_zenvoice_dictation": True,
            "native_realtime_multiple": 20.0,
            "q5_model_bytes": runtime_model.stat().st_size,
            "hardware_profile": "24 GB memory • 12 cores • Apple Silicon",
            "warmup_median_seconds": 0.3,
            "first_decode_median_seconds": 0.2,
            "second_decode_median_seconds": 0.18,
            "loaded_memory_max_mb": 480.0,
            "unloaded_memory_max_mb": 120.0,
            "reclaimed_memory_min_mb": 360.0,
        }
        write_json(
            baseline,
            {
                "schema_version": 1,
                "evidence_kind": "baseline",
                "dictation_wer_percent": 20.0,
                "clean_whole_wer_percent": 2.0,
                "clean_segmented_wer_percent": 5.0,
                "whole_quantity_failures": 2,
                "whole_negation_failures": 1,
                "segmented_quantity_failures": 3,
                "segmented_negation_failures": 1,
                **common_evidence,
            },
        )

        def candidate(
            checkpoint_id: str,
            dictation: float,
            clean_whole: float,
            clean_segmented: float,
            semantic: int,
            whole_quantity_failures: int = 2,
            native_realtime_multiple: float = 20.0,
        ) -> Path:
            checkpoint = fixture / checkpoint_id
            checkpoint.mkdir()
            adapter = checkpoint / "adapter_model.safetensors"
            adapter.write_bytes(checkpoint_id.encode("utf-8"))
            candidate_inventory = fixture / f"{checkpoint_id}-inventory.json"
            write_json(
                candidate_inventory,
                {
                    "schema_version": 1,
                    "artifacts": {
                        "q5_0": {
                            "path": runtime_model.name,
                            "sha256": sha256(runtime_model),
                        }
                    },
                    "evaluation_candidate": {
                        "checkpoint_id": checkpoint_id,
                        "adapter_sha256": sha256(adapter),
                        "frozen_test_sha256": sha256(locked / "test.jsonl"),
                        "promotion_authorized": False,
                    },
                },
            )
            evidence = fixture / f"{checkpoint_id}.json"
            write_json(
                evidence,
                {
                    "schema_version": 1,
                    "evidence_kind": "candidate",
                    "checkpoint_id": checkpoint_id,
                    "checkpoint_path": str(checkpoint.relative_to(repo_root)),
                    "adapter_sha256": sha256(adapter),
                    "frozen_test_sha256": sha256(locked / "test.jsonl"),
                    "dictation_wer_percent": dictation,
                    "clean_whole_wer_percent": clean_whole,
                    "clean_segmented_wer_percent": clean_segmented,
                    "whole_quantity_failures": whole_quantity_failures,
                    "whole_negation_failures": 1,
                    "segmented_quantity_failures": 3,
                    "segmented_negation_failures": 1,
                    "semantic_violations": semantic,
                    "silence_failures": 0,
                    "repetition_failures": 0,
                    "long_form_insertion_failures": 0,
                    "silence_probe_durations_seconds": [1, 5, 10],
                    "runtime_harness_passed": True,
                    **common_evidence,
                    "native_realtime_multiple": native_realtime_multiple,
                    "runtime_inventory": str(
                        candidate_inventory.relative_to(repo_root)
                    ),
                    "runtime_inventory_sha256": sha256(candidate_inventory),
                },
            )
            return evidence

        unsafe = candidate("unsafe-low-wer", 5.0, 1.0, 3.0, 1)
        clean_regression = candidate("clean-regression", 10.0, 4.0, 8.0, 0)
        protected_regression = candidate(
            "protected-regression", 8.0, 2.0, 5.0, 0, 3
        )
        performance_regression = candidate(
            "performance-regression", 7.0, 2.0, 5.0, 0, 2, 10.0
        )
        safe = candidate("safe-checkpoint", 15.0, 2.5, 5.5, 0)
        selector = repo_root / "Scripts" / "select-whisper-checkpoint.py"
        decision_path = fixture / "decision.json"
        run(
            [
                sys.executable,
                str(selector),
                "--locked-dataset-dir",
                str(locked),
                "--baseline-evidence",
                str(baseline),
                "--candidate-evidence",
                str(unsafe),
                "--candidate-evidence",
                str(clean_regression),
                "--candidate-evidence",
                str(protected_regression),
                "--candidate-evidence",
                str(performance_regression),
                "--candidate-evidence",
                str(safe),
                "--output",
                str(decision_path),
            ]
        )
        decision = json.loads(decision_path.read_text(encoding="utf-8"))
        if decision["selected"]["checkpoint_id"] != "safe-checkpoint":
            raise RuntimeError("selector did not choose the only safe checkpoint")
        if decision["promotion_authorized"] is not False:
            raise RuntimeError("checkpoint selection improperly authorized promotion")

        no_pass_path = fixture / "no-pass-decision.json"
        run(
            [
                sys.executable,
                str(selector),
                "--locked-dataset-dir",
                str(locked),
                "--baseline-evidence",
                str(baseline),
                "--candidate-evidence",
                str(unsafe),
                "--output",
                str(no_pass_path),
            ],
            expected_exit=2,
        )
        no_pass = json.loads(no_pass_path.read_text(encoding="utf-8"))
        if no_pass["selected"] is not None:
            raise RuntimeError("selector chose a candidate that failed safety")

        (locked / "FROZEN_TEST_LOCK.json").unlink()
        provenance = locked / "provenance.json"
        write_json(
            provenance,
            {"representative_dictation": False},
        )
        summary = locked / "summary.json"
        write_json(summary, {"representative_zenvoice_dictation": False})
        write_json(
            locked / "PUBLIC_CORPUS_LOCK.json",
            {
                "schema_version": 1,
                "immutable_artifacts": {
                    path.name: sha256(path) for path in [*artifacts, provenance]
                },
                "held_out_test_sha256": sha256(locked / "test.jsonl"),
            },
        )
        for evidence_path in (baseline, safe):
            evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
            evidence["locked_dataset_kind"] = "public_spontaneous_supplement"
            evidence["representative_zenvoice_dictation"] = False
            write_json(evidence_path, evidence)
        public_decision_path = fixture / "public-decision.json"
        run(
            [
                sys.executable,
                str(selector),
                "--locked-dataset-dir",
                str(locked),
                "--baseline-evidence",
                str(baseline),
                "--candidate-evidence",
                str(safe),
                "--output",
                str(public_decision_path),
            ],
            expected_exit=2,
        )
        public_decision = json.loads(
            public_decision_path.read_text(encoding="utf-8")
        )
        public_candidate = public_decision["candidates"][0]
        if public_candidate["gates"]["representative_zenvoice_dictation"]:
            raise RuntimeError("public corpus passed the representativeness gate")
        if public_decision["selected"] is not None:
            raise RuntimeError("selector chose a public-corpus-only candidate")

        print(
            "Composite checkpoint selection checks passed: unsafe and "
            "clean/protected/performance-regressing candidates rejected, "
            "safe candidate selected, public-only candidate blocked"
        )
        return 0
    finally:
        if fixture.parent.resolve() != datasets.resolve():
            raise RuntimeError("refusing to remove fixture outside Datasets")
        shutil.rmtree(fixture)


if __name__ == "__main__":
    raise SystemExit(main())
