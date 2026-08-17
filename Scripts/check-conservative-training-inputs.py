#!/usr/bin/env python3
"""Verify conservative training input validation and fail-closed tamper checks."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def write_wav(path: Path, sample: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16_000)
        output.writeframes(int(sample).to_bytes(2, "little", signed=True) * 16_000)


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
        tempfile.mkdtemp(prefix=".training-input-fixture-", dir=datasets)
    )
    try:
        locked = fixture / "locked"
        locked.mkdir()
        split_paths: list[Path] = []
        for index, split in enumerate(("train", "validation", "test"), start=1):
            audio = fixture / f"dictation-{split}.wav"
            write_wav(audio, index)
            manifest = locked / f"{split}.jsonl"
            write_jsonl(
                manifest,
                [
                    {
                        "audio": str(audio.relative_to(repo_root)),
                        "text": f"dictation {split}",
                        "audio_sha256": sha256(audio),
                    }
                ],
            )
            split_paths.append(manifest)
        summary = locked / "summary.json"
        write_json(
            summary,
            {
                "fixture": True,
                "representativeness": {"passed": True, "failures": []},
            },
        )
        write_json(
            locked / "FROZEN_TEST_LOCK.json",
            {
                "schema_version": 1,
                "dataset_version": "training-input-fixture-v1",
                "immutable_artifacts": {
                    path.name: sha256(path) for path in [*split_paths, summary]
                },
                "frozen_test_sha256": sha256(locked / "test.jsonl"),
            },
        )

        general = fixture / "general"
        general.mkdir()
        general_audio = general / "general.wav"
        write_wav(general_audio, 9)
        general_manifest = general / "train.jsonl"
        source = "General speech fixture"
        license_name = "CC-BY-4.0"
        write_jsonl(
            general_manifest,
            [
                {
                    "audio": str(general_audio.relative_to(repo_root)),
                    "text": "general speech",
                    "audio_sha256": sha256(general_audio),
                    "source": source,
                    "license": license_name,
                }
            ],
        )
        archive = general / "source.archive"
        archive.write_bytes(b"pinned source")
        write_json(
            general / "provenance.json",
            {
                "schema_version": 1,
                "manifest": general_manifest.name,
                "manifest_sha256": sha256(general_manifest),
                "source": source,
                "publisher": "Fixture Publisher",
                "source_url": "https://example.invalid/source",
                "source_landing_page": "https://example.invalid/",
                "license": license_name,
                "license_url": "https://creativecommons.org/licenses/by/4.0/",
                "required_attribution": "Fixture attribution",
                "representative_dictation": False,
                "redistribution_review": "pending",
                "archive": str(archive.relative_to(repo_root)),
                "archive_sha256": sha256(archive),
            },
        )

        validator = repo_root / "Scripts" / "train-whisper-dictation.py"
        output = fixture / "training-output"
        arguments = [
            sys.executable,
            str(validator),
            "--model-dir",
            str(fixture / "unused-base-model"),
            "--model-revision",
            "fixture-revision",
            "--locked-dataset-dir",
            str(locked),
            "--general-train-manifest",
            str(general_manifest),
            "--approved-general-license",
            license_name,
            "--output-dir",
            str(output),
            "--validate-inputs-only",
        ]
        result = run(arguments)
        validation = json.loads(result.stdout)
        if (
            validation.get("status") != "inputs-valid"
            or validation.get("general_train_samples") != 1
            or validation.get("dictation_train_samples") != 1
        ):
            raise RuntimeError("input validation returned unexpected evidence")

        archive.write_bytes(b"tampered source")
        run(arguments, expected_exit=1)
        archive.write_bytes(b"pinned source")
        write_json(
            summary,
            {
                "fixture": True,
                "representativeness": {
                    "passed": False,
                    "failures": ["fixture coverage failure"],
                },
            },
        )
        lock_path = locked / "FROZEN_TEST_LOCK.json"
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
        lock["immutable_artifacts"][summary.name] = sha256(summary)
        write_json(lock_path, lock)
        rejected = run(arguments, expected_exit=1)
        if "lacks passing representativeness evidence" not in rejected.stderr:
            raise RuntimeError("failed representativeness evidence was accepted")
        print(
            "Conservative training input checks passed: locked manifests, "
            "representativeness, licensed provenance, overlap scan, and "
            "archive tamper rejection"
        )
        return 0
    finally:
        if fixture.parent.resolve() != datasets.resolve():
            raise RuntimeError("refusing to remove fixture outside Datasets")
        shutil.rmtree(fixture)


if __name__ == "__main__":
    raise SystemExit(main())
