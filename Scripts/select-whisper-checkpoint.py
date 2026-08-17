#!/usr/bin/env python3
"""Select a Whisper checkpoint from composite, gate-backed evidence.

The selector never treats validation loss as release evidence. Every candidate
must reference the exact frozen test hash, improve representative dictation WER
by the configured relative margin, stay within the clean-speech regression
budget, report zero semantic/silence/repetition failures, and carry license and
attribution review. Only passing candidates participate in the composite score.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any


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


def require_number(value: Any, label: str) -> float:
    if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise ValueError(f"{label} must be a finite number")
    if float(value) < 0:
        raise ValueError(f"{label} must not be negative")
    return float(value)


def require_count(value: Any, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{label} must be a non-negative integer")
    return value


def verify_lock(directory: Path) -> tuple[dict[str, Any], str, bool]:
    private_lock = directory / "FROZEN_TEST_LOCK.json"
    public_lock = directory / "PUBLIC_CORPUS_LOCK.json"
    present = [path for path in (private_lock, public_lock) if path.is_file()]
    if len(present) != 1:
        raise ValueError(
            "locked dataset must contain exactly one of "
            "FROZEN_TEST_LOCK.json or PUBLIC_CORPUS_LOCK.json"
        )
    lock_path = present[0]
    lock = read_json(lock_path)
    if lock.get("schema_version") != 1:
        raise ValueError("frozen lock schema_version must be 1")
    artifacts = lock.get("immutable_artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        raise ValueError("frozen lock contains no immutable artifacts")
    for name, expected in artifacts.items():
        if not isinstance(name, str) or Path(name).name != name:
            raise ValueError(f"invalid frozen artifact name: {name!r}")
        path = directory / name
        if not path.is_file() or sha256(path) != expected:
            raise ValueError(f"frozen artifact changed: {path}")
    test_hash = sha256(directory / "test.jsonl")
    expected_test_hash = (
        lock.get("frozen_test_sha256")
        if lock_path == private_lock
        else lock.get("held_out_test_sha256")
    )
    if test_hash != expected_test_hash:
        raise ValueError("frozen test manifest hash changed")
    lock["frozen_test_sha256"] = expected_test_hash
    if lock_path == public_lock:
        provenance = read_json(directory / "provenance.json")
        summary = read_json(directory / "summary.json")
        if (
            provenance.get("representative_dictation") is not False
            or summary.get("representative_zenvoice_dictation") is not False
        ):
            raise ValueError("public corpus must be explicitly non-representative")
        return lock, "public_spontaneous_supplement", False
    return lock, "private_zenvoice_dictation", True


def verify_bound_artifacts(
    evidence_path: Path,
    evidence: dict[str, Any],
    frozen_test_sha256: str,
    repo_root: Path,
) -> None:
    for path_key, hash_key in (
        ("runtime_model_path", "runtime_model_sha256"),
        ("runtime_inventory", "runtime_inventory_sha256"),
        ("runtime_log", "runtime_log_sha256"),
        ("hf_metrics", "hf_metrics_sha256"),
        ("license_review", "license_review_sha256"),
    ):
        value = evidence.get(path_key)
        expected = evidence.get(hash_key)
        if not isinstance(value, str) or not isinstance(expected, str):
            raise ValueError(
                f"{evidence_path} is missing bound artifact {path_key}"
            )
        artifact = require_inside_datasets(
            repo_root / value,
            repo_root,
            f"{evidence_path.name} {path_key}",
        )
        if not artifact.is_file() or sha256(artifact) != expected:
            raise ValueError(f"evidence artifact changed: {artifact}")

    lifecycle_values = evidence.get("runtime_lifecycle_logs")
    lifecycle_hashes = evidence.get("runtime_lifecycle_log_sha256")
    if (
        not isinstance(lifecycle_values, list)
        or not isinstance(lifecycle_hashes, list)
        or len(lifecycle_values) < 3
        or len(lifecycle_values) != len(lifecycle_hashes)
    ):
        raise ValueError(f"invalid runtime lifecycle evidence: {evidence_path}")
    if len(set(lifecycle_values)) != len(lifecycle_values):
        raise ValueError(f"duplicate runtime lifecycle logs: {evidence_path}")
    for value, expected in zip(lifecycle_values, lifecycle_hashes, strict=True):
        if not isinstance(value, str) or not isinstance(expected, str):
            raise ValueError(f"invalid runtime lifecycle artifact: {evidence_path}")
        lifecycle = require_inside_datasets(
            repo_root / value,
            repo_root,
            f"{evidence_path.name} runtime lifecycle log",
        )
        if not lifecycle.is_file() or sha256(lifecycle) != expected:
            raise ValueError(f"runtime lifecycle evidence changed: {lifecycle}")

    hf_metrics = read_json(repo_root / str(evidence["hf_metrics"]))
    if hf_metrics.get("manifest_sha256") != frozen_test_sha256:
        raise ValueError(f"HF metrics used the wrong frozen test: {evidence_path}")
    if require_number(
        hf_metrics.get("wer_percent"), "HF WER"
    ) != require_number(evidence.get("hf_wer_percent"), "evidence HF WER"):
        raise ValueError(f"HF WER does not match its evidence: {evidence_path}")

    runtime_inventory = read_json(
        repo_root / str(evidence["runtime_inventory"])
    )
    artifacts = runtime_inventory.get("artifacts")
    q5_artifact = artifacts.get("q5_0") if isinstance(artifacts, dict) else None
    runtime_model = repo_root / str(evidence["runtime_model_path"])
    if (
        runtime_inventory.get("schema_version") != 1
        or not isinstance(q5_artifact, dict)
        or q5_artifact.get("path") != runtime_model.name
        or q5_artifact.get("sha256") != evidence.get("runtime_model_sha256")
    ):
        raise ValueError(f"runtime inventory does not bind Q5 model: {evidence_path}")

    license_review = read_json(repo_root / str(evidence["license_review"]))
    if license_review.get("schema_version") != 1:
        raise ValueError(f"invalid license review: {evidence_path}")
    if (
        evidence.get("license_review_passed")
        != (license_review.get("approved") is True)
        or evidence.get("attribution_recorded")
        != (license_review.get("attribution_recorded") is True)
    ):
        raise ValueError(f"license review does not match evidence: {evidence_path}")


def validate_baseline(
    path: Path,
    baseline: dict[str, Any],
    frozen_test_sha256: str,
    repo_root: Path,
    locked_dataset_kind: str,
    representative: bool,
) -> None:
    if baseline.get("schema_version") != 1:
        raise ValueError("baseline evidence schema_version must be 1")
    if baseline.get("evidence_kind") != "baseline":
        raise ValueError("baseline evidence_kind must be baseline")
    if baseline.get("frozen_test_sha256") != frozen_test_sha256:
        raise ValueError("baseline used the wrong frozen test manifest")
    if baseline.get("locked_dataset_kind") != locked_dataset_kind:
        raise ValueError("baseline used the wrong locked dataset kind")
    if baseline.get("representative_zenvoice_dictation") is not representative:
        raise ValueError("baseline representativeness does not match the lock")
    verify_bound_artifacts(path, baseline, frozen_test_sha256, repo_root)
    for key in (
        "dictation_wer_percent",
        "clean_whole_wer_percent",
        "clean_segmented_wer_percent",
        "native_realtime_multiple",
        "q5_model_bytes",
        "warmup_median_seconds",
        "first_decode_median_seconds",
        "second_decode_median_seconds",
        "loaded_memory_max_mb",
        "unloaded_memory_max_mb",
        "reclaimed_memory_min_mb",
    ):
        require_number(baseline.get(key), f"baseline {key}")
    if not isinstance(baseline.get("hardware_profile"), str):
        raise ValueError("baseline hardware_profile is missing")
    for key in (
        "whole_quantity_failures",
        "whole_negation_failures",
        "segmented_quantity_failures",
        "segmented_negation_failures",
    ):
        require_count(baseline.get(key), f"baseline {key}")


def evaluate_candidate(
    evidence_path: Path,
    evidence: dict[str, Any],
    baseline: dict[str, Any],
    frozen_test_sha256: str,
    repo_root: Path,
    minimum_relative_improvement: float,
    maximum_clean_regression: float,
    minimum_relative_throughput: float,
    maximum_latency_regression: float,
    maximum_loaded_memory_regression_mb: float,
    maximum_unloaded_memory_regression_mb: float,
    maximum_q5_size_regression: float,
    locked_dataset_kind: str,
    representative: bool,
) -> dict[str, Any]:
    if evidence.get("schema_version") != 1:
        raise ValueError(f"candidate schema_version must be 1: {evidence_path}")
    if evidence.get("evidence_kind") != "candidate":
        raise ValueError(f"candidate evidence_kind is invalid: {evidence_path}")
    checkpoint_id = evidence.get("checkpoint_id")
    if not isinstance(checkpoint_id, str) or not checkpoint_id.strip():
        raise ValueError(f"candidate checkpoint_id is missing: {evidence_path}")
    checkpoint_value = evidence.get("checkpoint_path")
    if not isinstance(checkpoint_value, str):
        raise ValueError(f"candidate checkpoint_path is missing: {evidence_path}")
    checkpoint = require_inside_datasets(
        repo_root / checkpoint_value,
        repo_root,
        "candidate checkpoint_path",
    )
    adapter = checkpoint / "adapter_model.safetensors"
    if not adapter.is_file():
        raise ValueError(f"candidate adapter is missing: {adapter}")
    adapter_hash = sha256(adapter)
    if evidence.get("adapter_sha256") != adapter_hash:
        raise ValueError(f"candidate adapter hash changed: {adapter}")
    if evidence.get("frozen_test_sha256") != frozen_test_sha256:
        raise ValueError(
            f"candidate used the wrong frozen test manifest: {evidence_path}"
        )
    if evidence.get("locked_dataset_kind") != locked_dataset_kind:
        raise ValueError(f"candidate used the wrong locked dataset kind: {evidence_path}")
    if evidence.get("representative_zenvoice_dictation") is not representative:
        raise ValueError(
            f"candidate representativeness does not match the lock: {evidence_path}"
        )
    verify_bound_artifacts(
        evidence_path,
        evidence,
        frozen_test_sha256,
        repo_root,
    )
    inventory = read_json(repo_root / str(evidence["runtime_inventory"]))
    runtime_candidate = inventory.get("evaluation_candidate")
    if (
        not isinstance(runtime_candidate, dict)
        or runtime_candidate.get("checkpoint_id") != checkpoint_id
        or runtime_candidate.get("adapter_sha256") != adapter_hash
        or runtime_candidate.get("frozen_test_sha256") != frozen_test_sha256
        or runtime_candidate.get("promotion_authorized") is not False
    ):
        raise ValueError(
            f"runtime inventory does not bind candidate adapter: {evidence_path}"
        )

    dictation_wer = require_number(
        evidence.get("dictation_wer_percent"),
        f"{checkpoint_id} dictation WER",
    )
    clean_whole = require_number(
        evidence.get("clean_whole_wer_percent"),
        f"{checkpoint_id} clean whole WER",
    )
    clean_segmented = require_number(
        evidence.get("clean_segmented_wer_percent"),
        f"{checkpoint_id} clean segmented WER",
    )
    semantic = require_count(
        evidence.get("semantic_violations"),
        f"{checkpoint_id} semantic violations",
    )
    silence = require_count(
        evidence.get("silence_failures"),
        f"{checkpoint_id} silence failures",
    )
    repetition = require_count(
        evidence.get("repetition_failures"),
        f"{checkpoint_id} repetition failures",
    )
    long_form_insertions = require_count(
        evidence.get("long_form_insertion_failures"),
        f"{checkpoint_id} long-form insertion failures",
    )
    protected_counts = {
        key: require_count(evidence.get(key), f"{checkpoint_id} {key}")
        for key in (
            "whole_quantity_failures",
            "whole_negation_failures",
            "segmented_quantity_failures",
            "segmented_negation_failures",
        )
    }
    baseline_protected_counts = {
        key: require_count(baseline.get(key), f"baseline {key}")
        for key in protected_counts
    }
    performance = {
        key: require_number(evidence.get(key), f"{checkpoint_id} {key}")
        for key in (
            "native_realtime_multiple",
            "q5_model_bytes",
            "warmup_median_seconds",
            "first_decode_median_seconds",
            "second_decode_median_seconds",
            "loaded_memory_max_mb",
            "unloaded_memory_max_mb",
            "reclaimed_memory_min_mb",
        )
    }
    baseline_performance = {
        key: require_number(baseline.get(key), f"baseline {key}")
        for key in performance
    }
    hardware_profile = evidence.get("hardware_profile")
    if not isinstance(hardware_profile, str) or not hardware_profile:
        raise ValueError(f"{checkpoint_id} hardware_profile is missing")
    latency_multiplier = 1.0 + maximum_latency_regression / 100.0
    minimum_throughput = baseline_performance["native_realtime_multiple"] * (
        minimum_relative_throughput / 100.0
    )
    maximum_q5_bytes = baseline_performance["q5_model_bytes"] * (
        1.0 + maximum_q5_size_regression / 100.0
    )
    silence_probes = evidence.get("silence_probe_durations_seconds")
    if silence_probes != [1, 5, 10]:
        raise ValueError(
            f"{checkpoint_id} must record 1, 5, and 10 second silence probes"
        )

    baseline_dictation = require_number(
        baseline.get("dictation_wer_percent"), "baseline dictation WER"
    )
    baseline_clean_whole = require_number(
        baseline.get("clean_whole_wer_percent"), "baseline clean whole WER"
    )
    baseline_clean_segmented = require_number(
        baseline.get("clean_segmented_wer_percent"),
        "baseline clean segmented WER",
    )
    required_wer = baseline_dictation * (
        1.0 - minimum_relative_improvement / 100.0
    )

    gates = {
        "representative_zenvoice_dictation": representative,
        "dictation_improvement": dictation_wer <= required_wer,
        "clean_whole_regression": (
            clean_whole - baseline_clean_whole <= maximum_clean_regression
        ),
        "clean_segmented_regression": (
            clean_segmented - baseline_clean_segmented
            <= maximum_clean_regression
        ),
        "semantic_safety": semantic == 0,
        "silence_safety": silence == 0,
        "repetition_safety": repetition == 0,
        "long_form_insertion_safety": long_form_insertions == 0,
        **{
            f"{key}_no_new_failures": (
                protected_counts[key] <= baseline_protected_counts[key]
            )
            for key in protected_counts
        },
        "same_performance_hardware": (
            hardware_profile == baseline.get("hardware_profile")
        ),
        "native_throughput": (
            performance["native_realtime_multiple"] >= minimum_throughput
        ),
        "warmup_latency": (
            performance["warmup_median_seconds"]
            <= baseline_performance["warmup_median_seconds"] * latency_multiplier
        ),
        "first_decode_latency": (
            performance["first_decode_median_seconds"]
            <= baseline_performance["first_decode_median_seconds"]
            * latency_multiplier
        ),
        "second_decode_latency": (
            performance["second_decode_median_seconds"]
            <= baseline_performance["second_decode_median_seconds"]
            * latency_multiplier
        ),
        "loaded_memory": (
            performance["loaded_memory_max_mb"]
            <= baseline_performance["loaded_memory_max_mb"]
            + maximum_loaded_memory_regression_mb
        ),
        "unloaded_memory": (
            performance["unloaded_memory_max_mb"]
            <= baseline_performance["unloaded_memory_max_mb"]
            + maximum_unloaded_memory_regression_mb
        ),
        "memory_reclaimed": performance["reclaimed_memory_min_mb"] > 200.0,
        "q5_size": performance["q5_model_bytes"] <= maximum_q5_bytes,
        "runtime_harness": evidence.get("runtime_harness_passed") is True,
        "license_review": evidence.get("license_review_passed") is True,
        "attribution": evidence.get("attribution_recorded") is True,
    }
    composite_score = (
        dictation_wer
        + (clean_whole + clean_segmented) / 2.0
        + 100.0 * (
            semantic + silence + repetition + long_form_insertions
        )
    )
    return {
        "checkpoint_id": checkpoint_id,
        "checkpoint_path": str(checkpoint.relative_to(repo_root)),
        "adapter_sha256": adapter_hash,
        "evidence_path": str(evidence_path.relative_to(repo_root)),
        "metrics": {
            "dictation_wer_percent": dictation_wer,
            "clean_whole_wer_percent": clean_whole,
            "clean_segmented_wer_percent": clean_segmented,
            "semantic_violations": semantic,
            "silence_failures": silence,
            "repetition_failures": repetition,
            "long_form_insertion_failures": long_form_insertions,
            **protected_counts,
            **performance,
            "hardware_profile": hardware_profile,
            "silence_probe_durations_seconds": silence_probes,
        },
        "gates": gates,
        "passes_all_gates": all(gates.values()),
        "composite_score": round(composite_score, 6),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--locked-dataset-dir", type=Path, required=True)
    parser.add_argument("--baseline-evidence", type=Path, required=True)
    parser.add_argument(
        "--candidate-evidence", type=Path, action="append", required=True
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--minimum-relative-improvement", type=float, default=10.0
    )
    parser.add_argument("--maximum-clean-regression", type=float, default=1.0)
    parser.add_argument("--minimum-relative-throughput", type=float, default=80.0)
    parser.add_argument("--maximum-latency-regression", type=float, default=25.0)
    parser.add_argument(
        "--maximum-loaded-memory-regression-mb", type=float, default=50.0
    )
    parser.add_argument(
        "--maximum-unloaded-memory-regression-mb", type=float, default=25.0
    )
    parser.add_argument("--maximum-q5-size-regression", type=float, default=2.0)
    args = parser.parse_args()

    if not 0 <= args.minimum_relative_improvement < 100:
        parser.error("--minimum-relative-improvement must be in [0, 100)")
    if args.maximum_clean_regression < 0:
        parser.error("--maximum-clean-regression must not be negative")
    for value, label in (
        (args.minimum_relative_throughput, "--minimum-relative-throughput"),
        (args.maximum_latency_regression, "--maximum-latency-regression"),
        (
            args.maximum_loaded_memory_regression_mb,
            "--maximum-loaded-memory-regression-mb",
        ),
        (
            args.maximum_unloaded_memory_regression_mb,
            "--maximum-unloaded-memory-regression-mb",
        ),
        (args.maximum_q5_size_regression, "--maximum-q5-size-regression"),
    ):
        if value < 0:
            parser.error(f"{label} must not be negative")
    if args.minimum_relative_throughput > 100:
        parser.error("--minimum-relative-throughput must be at most 100")

    repo_root = Path(__file__).resolve().parent.parent
    dataset = require_inside_datasets(
        args.locked_dataset_dir, repo_root, "--locked-dataset-dir"
    )
    baseline_path = require_inside_datasets(
        args.baseline_evidence, repo_root, "--baseline-evidence"
    )
    evidence_paths = [
        require_inside_datasets(path, repo_root, "--candidate-evidence")
        for path in args.candidate_evidence
    ]
    output = require_inside_datasets(args.output, repo_root, "--output")
    if output.exists():
        parser.error(f"refusing to overwrite selection decision: {output}")

    lock, locked_dataset_kind, representative = verify_lock(dataset)
    baseline = read_json(baseline_path)
    validate_baseline(
        baseline_path,
        baseline,
        str(lock["frozen_test_sha256"]),
        repo_root,
        locked_dataset_kind,
        representative,
    )
    candidates = [
        evaluate_candidate(
            path,
            read_json(path),
            baseline,
            str(lock["frozen_test_sha256"]),
            repo_root,
            args.minimum_relative_improvement,
            args.maximum_clean_regression,
            args.minimum_relative_throughput,
            args.maximum_latency_regression,
            args.maximum_loaded_memory_regression_mb,
            args.maximum_unloaded_memory_regression_mb,
            args.maximum_q5_size_regression,
            locked_dataset_kind,
            representative,
        )
        for path in evidence_paths
    ]
    passing = [candidate for candidate in candidates if candidate["passes_all_gates"]]
    selected = min(
        passing,
        key=lambda candidate: (
            candidate["composite_score"],
            candidate["checkpoint_id"],
        ),
        default=None,
    )
    decision = {
        "schema_version": 1,
        "selection_method": (
            "all gates, then minimum dictation WER plus mean clean WER"
        ),
        "locked_dataset": str(dataset.relative_to(repo_root)),
        "frozen_test_sha256": lock["frozen_test_sha256"],
        "locked_dataset_kind": locked_dataset_kind,
        "representative_zenvoice_dictation": representative,
        "baseline_evidence": str(baseline_path.relative_to(repo_root)),
        "minimum_relative_improvement_percent": (
            args.minimum_relative_improvement
        ),
        "maximum_clean_regression_points": args.maximum_clean_regression,
        "minimum_relative_throughput_percent": args.minimum_relative_throughput,
        "maximum_latency_regression_percent": args.maximum_latency_regression,
        "maximum_loaded_memory_regression_mb": (
            args.maximum_loaded_memory_regression_mb
        ),
        "maximum_unloaded_memory_regression_mb": (
            args.maximum_unloaded_memory_regression_mb
        ),
        "maximum_q5_size_regression_percent": args.maximum_q5_size_regression,
        "candidates": candidates,
        "selected": selected,
        "promotion_authorized": False,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(decision, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if selected is None:
        print(f"No candidate passed every gate; decision: {output}")
        return 2
    print(
        f"Selected {selected['checkpoint_id']} with composite score "
        f"{selected['composite_score']}; promotion remains unauthorized"
    )
    print(f"Decision: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
