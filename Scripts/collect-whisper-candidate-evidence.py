#!/usr/bin/env python3
"""Build checkpoint-selection evidence from verified evaluator artifacts.

The collector ties Hugging Face metrics and the native ZenVoice runtime log to
the exact frozen test manifest, runtime model, and adapter hashes. It parses
clean/real WER, semantic safety, silence probes, long-form insertions, and
repetition. A runtime log without the final pass marker is rejected.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import statistics
import sys
from pathlib import Path
from typing import Any


OVERALL = re.compile(r"^\s*OVERALL\s+(\d+(?:\.\d+)?)%\s+(\d+(?:\.\d+)?)%", re.MULTILINE)
REAL_SPEECH = re.compile(r"^\s*REAL SPEECH\s+(\d+(?:\.\d+)?)%\s+(\d+(?:\.\d+)?)%", re.MULTILINE)
REAL_PROTECTED = re.compile(
    r"^\s*REAL PROTECTED\s+(whole|segmented)\s+quantities\s+(\d+)\s+"
    r"negations\s+(\d+)$",
    re.MULTILINE,
)
SEMANTIC = re.compile(r"^\s*(?:clean|agent prompt)\s+(\d+) violations$", re.MULTILINE)
SILENCE = re.compile(r"^\s*(1|5|10)s silence\s+(suppressed|SURVIVED)\b", re.MULTILINE)
LONG_FORM = re.compile(
    r"^\s*\d+s audio\s+\d+(?:\.\d+)?%\s+(\d+) ins\s+"
    r"(\d+(?:\.\d+)?)% repeat$",
    re.MULTILINE,
)
REAL_SPEED = re.compile(
    r"^\s*real-speech decode\s+(\d+(?:\.\d+)?) s for\s+"
    r"(\d+(?:\.\d+)?) s of audio\s+\((\d+(?:\.\d+)?)x real time\)$",
    re.MULTILINE,
)
RUNTIME_TIMING = re.compile(
    r"^\s*warm-up\s+(\d+(?:\.\d+)?)s\s+\(repeat\s+"
    r"(\d+(?:\.\d+)?)s\)\s+·\s+first decode\s+"
    r"(\d+(?:\.\d+)?)s\s+·\s+second decode\s+"
    r"(\d+(?:\.\d+)?)s$",
    re.MULTILINE,
)
RUNTIME_MEMORY = re.compile(
    r"^\s*memory\s+(\d+(?:\.\d+)?) MB loaded\s+·\s+"
    r"(\d+(?:\.\d+)?) MB after unload\s+\(reclaimed\s+"
    r"(\d+(?:\.\d+)?) MB\)",
    re.MULTILINE,
)
HARDWARE = re.compile(r"^hardware profile:\s+(.+)$", re.MULTILINE)


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
    artifacts = lock.get("immutable_artifacts")
    if lock.get("schema_version") != 1 or not isinstance(artifacts, dict):
        raise ValueError(f"invalid frozen lock: {lock_path}")
    for name, expected in artifacts.items():
        path = directory / str(name)
        if Path(str(name)).name != name or not path.is_file():
            raise ValueError(f"invalid frozen artifact: {name!r}")
        if sha256(path) != expected:
            raise ValueError(f"frozen artifact changed: {path}")
    test_manifest = directory / "test.jsonl"
    expected_test_hash = (
        lock.get("frozen_test_sha256")
        if lock_path == private_lock
        else lock.get("held_out_test_sha256")
    )
    if sha256(test_manifest) != expected_test_hash:
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


def single_match(expression: re.Pattern[str], text: str, label: str) -> re.Match[str]:
    matches = list(expression.finditer(text))
    if len(matches) != 1:
        raise ValueError(f"expected exactly one {label} in runtime log")
    return matches[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--evidence-kind",
        choices=("baseline", "candidate"),
        default="candidate",
    )
    parser.add_argument("--checkpoint-id", required=True)
    parser.add_argument("--checkpoint-dir", type=Path)
    parser.add_argument("--runtime-model", type=Path, required=True)
    parser.add_argument("--runtime-inventory", type=Path, required=True)
    parser.add_argument("--runtime-log", type=Path, required=True)
    parser.add_argument(
        "--runtime-lifecycle-log",
        type=Path,
        action="append",
        required=True,
        help="repeat at least three times for median latency/memory evidence",
    )
    parser.add_argument("--hf-metrics", type=Path, required=True)
    parser.add_argument("--locked-dataset-dir", type=Path, required=True)
    parser.add_argument("--license-review", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    checkpoint = None
    adapter = None
    if args.evidence_kind == "candidate":
        if args.checkpoint_dir is None:
            parser.error("candidate evidence requires --checkpoint-dir")
        checkpoint = require_inside_datasets(
            args.checkpoint_dir, repo_root, "--checkpoint-dir"
        )
        adapter = checkpoint / "adapter_model.safetensors"
    elif args.checkpoint_dir is not None:
        parser.error("baseline evidence must not use --checkpoint-dir")
    runtime_model = require_inside_datasets(
        args.runtime_model, repo_root, "--runtime-model"
    )
    runtime_inventory_path = require_inside_datasets(
        args.runtime_inventory, repo_root, "--runtime-inventory"
    )
    runtime_log = require_inside_datasets(
        args.runtime_log, repo_root, "--runtime-log"
    )
    lifecycle_logs = [
        require_inside_datasets(path, repo_root, "--runtime-lifecycle-log")
        for path in args.runtime_lifecycle_log
    ]
    if len(lifecycle_logs) < 3:
        parser.error("at least three --runtime-lifecycle-log values are required")
    hf_metrics_path = require_inside_datasets(
        args.hf_metrics, repo_root, "--hf-metrics"
    )
    dataset = require_inside_datasets(
        args.locked_dataset_dir, repo_root, "--locked-dataset-dir"
    )
    license_path = require_inside_datasets(
        args.license_review, repo_root, "--license-review"
    )
    output = require_inside_datasets(args.output, repo_root, "--output")
    if output.exists():
        parser.error(f"refusing to overwrite evidence: {output}")

    required_paths = [
        runtime_model,
        runtime_inventory_path,
        runtime_log,
        *lifecycle_logs,
        hf_metrics_path,
        license_path,
    ]
    if adapter is not None:
        required_paths.append(adapter)
    for path in required_paths:
        if not path.is_file():
            raise ValueError(f"required evidence artifact is missing: {path}")
    lock, locked_dataset_kind, representative = verify_lock(dataset)
    test_manifest = (dataset / "test.jsonl").resolve()
    runtime_inventory = read_json(runtime_inventory_path)
    artifacts = runtime_inventory.get("artifacts")
    if not isinstance(artifacts, dict):
        raise ValueError("runtime inventory has no artifacts object")
    q5_artifact = artifacts.get("q5_0")
    if not isinstance(q5_artifact, dict):
        raise ValueError("runtime inventory has no Q5 artifact")
    if runtime_inventory.get("schema_version") != 1:
        raise ValueError("runtime inventory schema_version must be 1")
    if q5_artifact.get("path") != runtime_model.name:
        raise ValueError("runtime inventory identifies a different Q5 model")
    if q5_artifact.get("sha256") != sha256(runtime_model):
        raise ValueError("runtime Q5 model hash does not match its inventory")
    if args.evidence_kind == "candidate":
        assert adapter is not None
        candidate = runtime_inventory.get("evaluation_candidate")
        if not isinstance(candidate, dict):
            raise ValueError("candidate runtime inventory lacks evaluation provenance")
        if candidate.get("checkpoint_id") != args.checkpoint_id:
            raise ValueError("runtime inventory identifies a different checkpoint")
        if candidate.get("adapter_sha256") != sha256(adapter):
            raise ValueError("runtime inventory identifies a different adapter")
        if candidate.get("frozen_test_sha256") != lock.get("frozen_test_sha256"):
            raise ValueError("runtime inventory identifies a different frozen test")
        if candidate.get("promotion_authorized") is not False:
            raise ValueError("evaluation runtime improperly authorizes promotion")
    hf_metrics = read_json(hf_metrics_path)
    if hf_metrics.get("manifest_sha256") != lock.get("frozen_test_sha256"):
        raise ValueError("Hugging Face metrics used the wrong frozen test")
    license_review = read_json(license_path)
    if license_review.get("schema_version") != 1:
        raise ValueError("license review schema_version must be 1")

    log_text = runtime_log.read_text(encoding="utf-8")
    if "ZenVoiceAccuracyChecks passed" not in log_text:
        raise ValueError("runtime harness did not finish with a pass")
    expected_model_line = f"model artifact: {runtime_model}"
    expected_corpus_line = f"corpus input: {test_manifest}"
    if expected_model_line not in log_text:
        raise ValueError("runtime log does not identify the supplied model")
    if expected_corpus_line not in log_text:
        raise ValueError("runtime log does not identify the frozen test manifest")

    clean = single_match(OVERALL, log_text, "clean OVERALL result")
    real = single_match(REAL_SPEECH, log_text, "REAL SPEECH result")
    protected = {
        strategy: {
            "quantity": int(quantity),
            "negation": int(negation),
        }
        for strategy, quantity, negation in REAL_PROTECTED.findall(log_text)
    }
    if set(protected) != {"whole", "segmented"}:
        raise ValueError("runtime log lacks protected-token ASR evidence")
    semantic_counts = [int(value) for value in SEMANTIC.findall(log_text)]
    if len(semantic_counts) != 2:
        raise ValueError("runtime log does not contain both semantic stages")
    silence_results = {
        int(seconds): result for seconds, result in SILENCE.findall(log_text)
    }
    if set(silence_results) != {1, 5, 10}:
        raise ValueError("runtime log lacks the required silence probes")
    long_form = [
        (int(insertions), float(repetition))
        for insertions, repetition in LONG_FORM.findall(log_text)
    ]
    if len(long_form) < 2:
        raise ValueError("runtime log lacks long-form evidence")
    speed = single_match(REAL_SPEED, log_text, "real-speech throughput result")

    lifecycle_results: list[dict[str, float]] = []
    hardware_profiles: set[str] = set()
    expected_lifecycle_model = f"model artifact: {runtime_model}"
    for lifecycle_log in lifecycle_logs:
        lifecycle_text = lifecycle_log.read_text(encoding="utf-8")
        if "ZenVoice runtime checks passed" not in lifecycle_text:
            raise ValueError(f"runtime lifecycle did not pass: {lifecycle_log}")
        if expected_lifecycle_model not in lifecycle_text:
            raise ValueError(
                f"runtime lifecycle identifies another model: {lifecycle_log}"
            )
        timing = single_match(
            RUNTIME_TIMING,
            lifecycle_text,
            f"runtime timing result in {lifecycle_log.name}",
        )
        memory = single_match(
            RUNTIME_MEMORY,
            lifecycle_text,
            f"runtime memory result in {lifecycle_log.name}",
        )
        hardware = single_match(
            HARDWARE,
            lifecycle_text,
            f"hardware profile in {lifecycle_log.name}",
        )
        hardware_profiles.add(hardware.group(1).strip())
        lifecycle_results.append(
            {
                "warmup_seconds": float(timing.group(1)),
                "repeat_warmup_seconds": float(timing.group(2)),
                "first_decode_seconds": float(timing.group(3)),
                "second_decode_seconds": float(timing.group(4)),
                "loaded_memory_mb": float(memory.group(1)),
                "unloaded_memory_mb": float(memory.group(2)),
                "reclaimed_memory_mb": float(memory.group(3)),
            }
        )
    if len(hardware_profiles) != 1:
        raise ValueError("runtime lifecycle logs used different hardware profiles")

    def median(key: str) -> float:
        return round(statistics.median(row[key] for row in lifecycle_results), 4)

    evidence = {
        "schema_version": 1,
        "evidence_kind": args.evidence_kind,
        "checkpoint_id": args.checkpoint_id,
        "runtime_model_path": str(runtime_model.relative_to(repo_root)),
        "runtime_model_sha256": sha256(runtime_model),
        "runtime_inventory": str(runtime_inventory_path.relative_to(repo_root)),
        "runtime_inventory_sha256": sha256(runtime_inventory_path),
        "runtime_log": str(runtime_log.relative_to(repo_root)),
        "runtime_log_sha256": sha256(runtime_log),
        "runtime_lifecycle_logs": [
            str(path.relative_to(repo_root)) for path in lifecycle_logs
        ],
        "runtime_lifecycle_log_sha256": [sha256(path) for path in lifecycle_logs],
        "hf_metrics": str(hf_metrics_path.relative_to(repo_root)),
        "hf_metrics_sha256": sha256(hf_metrics_path),
        "hf_wer_percent": hf_metrics.get("wer_percent"),
        "frozen_test_sha256": lock["frozen_test_sha256"],
        "locked_dataset_kind": locked_dataset_kind,
        "representative_zenvoice_dictation": representative,
        "dictation_wer_percent": float(real.group(1)),
        "dictation_segmented_wer_percent": float(real.group(2)),
        "native_realtime_multiple": float(speed.group(3)),
        "q5_model_bytes": runtime_model.stat().st_size,
        "hardware_profile": next(iter(hardware_profiles)),
        "warmup_median_seconds": median("warmup_seconds"),
        "first_decode_median_seconds": median("first_decode_seconds"),
        "second_decode_median_seconds": median("second_decode_seconds"),
        "loaded_memory_max_mb": max(
            row["loaded_memory_mb"] for row in lifecycle_results
        ),
        "unloaded_memory_max_mb": max(
            row["unloaded_memory_mb"] for row in lifecycle_results
        ),
        "reclaimed_memory_min_mb": min(
            row["reclaimed_memory_mb"] for row in lifecycle_results
        ),
        "clean_whole_wer_percent": float(clean.group(1)),
        "clean_segmented_wer_percent": float(clean.group(2)),
        "whole_quantity_failures": protected["whole"]["quantity"],
        "whole_negation_failures": protected["whole"]["negation"],
        "segmented_quantity_failures": protected["segmented"]["quantity"],
        "segmented_negation_failures": protected["segmented"]["negation"],
        "semantic_violations": sum(semantic_counts),
        "silence_failures": sum(
            result != "suppressed" for result in silence_results.values()
        ),
        "silence_probe_durations_seconds": sorted(silence_results),
        "repetition_failures": sum(repetition > 0 for _, repetition in long_form),
        "long_form_insertion_failures": sum(
            insertions > 0 for insertions, _ in long_form
        ),
        "runtime_harness_passed": True,
        "license_review": str(license_path.relative_to(repo_root)),
        "license_review_sha256": sha256(license_path),
        "license_review_passed": license_review.get("approved") is True,
        "attribution_recorded": license_review.get("attribution_recorded") is True,
    }
    if checkpoint is not None and adapter is not None:
        evidence["checkpoint_path"] = str(checkpoint.relative_to(repo_root))
        evidence["adapter_sha256"] = sha256(adapter)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(evidence, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
