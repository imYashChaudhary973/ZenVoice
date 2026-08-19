#!/usr/bin/env python3
"""Verify artifact-bound baseline/candidate evidence and tamper rejection."""

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
    fixture = Path(
        tempfile.mkdtemp(prefix=".candidate-evidence-fixture-", dir=datasets)
    )
    try:
        locked = fixture / "locked"
        locked.mkdir()
        immutable: dict[str, str] = {}
        for name, content in (
            ("train.jsonl", "train\n"),
            ("validation.jsonl", "validation\n"),
            ("test.jsonl", "test\n"),
            ("summary.json", "{}\n"),
        ):
            artifact = locked / name
            artifact.write_text(content, encoding="utf-8")
            immutable[name] = sha256(artifact)
        frozen_test_sha = sha256(locked / "test.jsonl")
        write_json(
            locked / "FROZEN_TEST_LOCK.json",
            {
                "schema_version": 1,
                "dataset_version": "evidence-fixture-v1",
                "immutable_artifacts": immutable,
                "frozen_test_sha256": frozen_test_sha,
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

        collector = repo_root / "Scripts" / "collect-whisper-candidate-evidence.py"

        def collect(kind: str, identifier: str, real_wer: float) -> tuple[Path, Path]:
            runtime_model = fixture / f"{identifier}.bin"
            runtime_model.write_bytes(b"runtime-model")
            checkpoint = None
            adapter = None
            if kind == "candidate":
                checkpoint = fixture / "checkpoint-1"
                checkpoint.mkdir()
                adapter = checkpoint / "adapter_model.safetensors"
                adapter.write_bytes(b"adapter")
            runtime_inventory = fixture / f"{identifier}-inventory.json"
            inventory = {
                "schema_version": 1,
                "artifacts": {
                    "q5_0": {
                        "path": runtime_model.name,
                        "sha256": sha256(runtime_model),
                    }
                },
            }
            if adapter is not None:
                inventory["evaluation_candidate"] = {
                    "checkpoint_id": identifier,
                    "adapter_sha256": sha256(adapter),
                    "frozen_test_sha256": frozen_test_sha,
                    "promotion_authorized": False,
                }
            write_json(runtime_inventory, inventory)
            runtime_log = fixture / f"{identifier}.log"
            runtime_log.write_text(
                "\n".join(
                    [
                        f"model artifact: {runtime_model.resolve()}",
                        f"corpus input: {(locked / 'test.jsonl').resolve()}",
                        "  OVERALL 2.0% 5.0% +3.0 pts",
                        "  clean 0 violations",
                        "  agent prompt 0 violations",
                        "  1s silence suppressed raw: <empty>",
                        "  5s silence suppressed raw: <empty>",
                        "  10s silence suppressed raw: <empty>",
                        "  50s audio 0.0% 0 ins 0.0% repeat",
                        "  33s audio 0.0% 0 ins 0.0% repeat",
                        f"  REAL SPEECH {real_wer:.1f}% {real_wer:.1f}% +0.0 pts",
                        "  REAL PROTECTED whole quantities 2 negations 1",
                        "  REAL PROTECTED segmented quantities 3 negations 1",
                        "  real-speech decode 10.00 s for 200 s of audio (20x real time)",
                        "ZenVoiceAccuracyChecks passed",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            metrics = fixture / f"{identifier}-metrics.json"
            write_json(
                metrics,
                {
                    "schema_version": 1,
                    "manifest_sha256": frozen_test_sha,
                    "wer_percent": real_wer,
                },
            )
            evidence = fixture / f"{identifier}-evidence.json"
            lifecycle_logs: list[Path] = []
            for run_number in range(1, 4):
                lifecycle = fixture / f"{identifier}-lifecycle-{run_number}.log"
                lifecycle.write_text(
                    "\n".join(
                        [
                            f"model artifact: {runtime_model.resolve()}",
                            "hardware profile: 24 GB memory • 12 cores • Apple Silicon",
                            "  warm-up 0.30s (repeat 0.001s) · first decode 0.20s · second decode 0.18s",
                            "  memory 480 MB loaded · 120 MB after unload (reclaimed 360 MB) · reloaded on next decode",
                            "ZenVoice runtime checks passed",
                            "",
                        ]
                    ),
                    encoding="utf-8",
                )
                lifecycle_logs.append(lifecycle)
            arguments = [
                sys.executable,
                str(collector),
                "--evidence-kind",
                kind,
                "--checkpoint-id",
                identifier,
                "--runtime-model",
                str(runtime_model),
                "--runtime-inventory",
                str(runtime_inventory),
                "--runtime-log",
                str(runtime_log),
                "--hf-metrics",
                str(metrics),
                "--locked-dataset-dir",
                str(locked),
                "--license-review",
                str(license_review),
                "--output",
                str(evidence),
            ]
            for lifecycle in lifecycle_logs:
                arguments.extend(["--runtime-lifecycle-log", str(lifecycle)])
            if kind == "candidate":
                assert checkpoint is not None
                arguments.extend(["--checkpoint-dir", str(checkpoint)])
            run(arguments)
            return evidence, runtime_log

        baseline, _ = collect("baseline", "baseline", 20.0)
        candidate, candidate_log = collect("candidate", "candidate", 15.0)
        decision = fixture / "decision.json"
        selector = repo_root / "Scripts" / "select-whisper-checkpoint.py"
        selection_arguments = [
            sys.executable,
            str(selector),
            "--locked-dataset-dir",
            str(locked),
            "--baseline-evidence",
            str(baseline),
            "--candidate-evidence",
            str(candidate),
            "--output",
            str(decision),
        ]
        run(selection_arguments)
        selected = json.loads(decision.read_text(encoding="utf-8"))["selected"]
        if selected["checkpoint_id"] != "candidate":
            raise RuntimeError("artifact-bound candidate was not selected")

        candidate_log.write_text(
            candidate_log.read_text(encoding="utf-8") + "tampered\n",
            encoding="utf-8",
        )
        selection_arguments[-1] = str(fixture / "tampered-decision.json")
        run(selection_arguments, expected_exit=1)
        print(
            "Candidate evidence checks passed: baseline/candidate collection, "
            "selection, and post-collection tamper rejection"
        )
        return 0
    finally:
        if fixture.parent.resolve() != datasets.resolve():
            raise RuntimeError("refusing to remove fixture outside Datasets")
        shutil.rmtree(fixture)


if __name__ == "__main__":
    raise SystemExit(main())
