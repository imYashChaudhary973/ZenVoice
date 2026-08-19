#!/usr/bin/env python3
"""Exercise the consented-dictation data pipeline with disposable fixtures.

The generated audio is synthetic test data and is deleted before exit. It is
never a training source. The check drives the public command-line interfaces,
builds three speaker-disjoint splits, verifies the lock, then proves that a
mutated frozen test manifest is rejected.
"""

from __future__ import annotations

import hashlib
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path


SAMPLE_RATE = 16_000


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


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


def write_tone(path: Path, frequency: float) -> None:
    frames = SAMPLE_RATE
    samples = [
        int(1_500 * math.sin(2 * math.pi * frequency * index / SAMPLE_RATE))
        for index in range(frames)
    ]
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(SAMPLE_RATE)
        writer.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def write_json(path: Path, value: object) -> None:
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def create_session(
    repo_root: Path,
    fixture_root: Path,
    participant: str,
    frequency: float,
) -> Path:
    session_id = f"{participant}-session"
    session_dir = fixture_root / participant / session_id
    prepare = repo_root / "Scripts" / "prepare-dictation-corpus.py"
    run(
        [
            sys.executable,
            str(prepare),
            "init",
            "--output",
            str(session_dir),
            "--participant-id",
            participant,
            "--speaker-group-id",
            participant,
            "--session-id",
            session_id,
        ]
    )
    write_json(
        session_dir / "consent.json",
        {
            "schema_version": 1,
            "consent_text_version": "zenvoice-dictation-v1",
            "participant_id": participant,
            "consented_at": "2026-08-14T00:00:00+00:00",
            "participant_is_adult": True,
            "consent_statement_accepted": True,
            "local_training_allowed": True,
            "local_evaluation_allowed": True,
            "redistribution_allowed": False,
            "test_fixture_only": True,
        },
    )
    generated_session = json.loads(
        (session_dir / "session.json").read_text(encoding="utf-8")
    )
    generated_session.update(
        {
            "schema_version": 1,
            "participant_id": participant,
            "speaker_group_id": participant,
            "session_id": session_id,
            "recorded_at": "2026-08-14T00:00:00+00:00",
            "language": "en-IN",
            "accent_self_description": "synthetic fixture",
            "microphone": "fixture generator",
            "environment": "automated test",
            "notes": "not human speech and never eligible for training",
        }
    )
    write_json(session_dir / "session.json", generated_session)
    recordings = session_dir / "recordings"
    write_tone(recordings / "email-update.wav", frequency)
    (recordings / "email-update.txt").write_text(
        f"Synthetic fixture for {participant}.\n",
        encoding="utf-8",
    )
    manifest = fixture_root / "manifests" / f"{session_id}.jsonl"
    validate = run(
        [
            sys.executable,
            str(prepare),
            "validate",
            "--session-dir",
            str(session_dir),
            "--output-manifest",
            str(manifest),
        ]
    )
    if "Validated 1 clips" not in validate.stdout:
        raise RuntimeError("session validator did not report one fixture clip")
    return manifest


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    datasets = repo_root / "Datasets"
    fixture_root = Path(
        tempfile.mkdtemp(
            prefix=".consented-dictation-pipeline-fixture-",
            dir=datasets,
        )
    )
    try:
        prepare = repo_root / "Scripts" / "prepare-dictation-corpus.py"
        run(
            [
                sys.executable,
                str(prepare),
                "init",
                "--output",
                str(fixture_root / "rejected-partial-identity"),
                "--participant-id",
                "speaker-z",
            ],
            expected_exit=2,
        )
        manifests = [
            create_session(repo_root, fixture_root, "speaker-a", 220.0),
            create_session(repo_root, fixture_root, "speaker-b", 330.0),
            create_session(repo_root, fixture_root, "speaker-c", 440.0),
        ]
        policy = fixture_root / "split-policy.json"
        write_json(
            policy,
            {
                "schema_version": 2,
                "dataset_version": "fixture-v1",
                "created_at": "2026-08-14T00:00:00+00:00",
                "assignment_unit": "speaker_group_id",
                "splits": {
                    "train": {"speaker_group_ids": ["speaker-a"]},
                    "validation": {"speaker_group_ids": ["speaker-b"]},
                    "test": {"speaker_group_ids": ["speaker-c"]},
                },
                "representativeness": {
                    "minimum_total_clips": 3,
                    "minimum_total_hours": 0.0005,
                    "minimum_total_speaker_groups": 3,
                    "splits": {
                        split: {
                            "minimum_clips": 1,
                            "minimum_hours": 0.0002,
                            "minimum_speaker_groups": 1,
                            "required_categories": ["email"],
                            "minimum_clips_per_required_category": 1,
                        }
                        for split in ("train", "validation", "test")
                    },
                },
            },
        )
        split_tool = repo_root / "Scripts" / "build-consented-dictation-splits.py"
        empty_status = run(
            [
                sys.executable,
                str(split_tool),
                "status",
                "--policy",
                str(policy),
            ]
        )
        empty_report = json.loads(empty_status.stdout)
        if (
            empty_report.get("ready_to_freeze") is not False
            or empty_report.get("validated_clips") != 0
        ):
            raise RuntimeError("empty collection status was not fail closed")

        ready_status_arguments = [
            sys.executable,
            str(split_tool),
            "status",
        ]
        for manifest in manifests:
            ready_status_arguments.extend(
                ["--session-manifest", str(manifest)]
            )
        ready_status_arguments.extend(["--policy", str(policy)])
        ready_report = json.loads(run(ready_status_arguments).stdout)
        if (
            ready_report.get("ready_to_freeze") is not True
            or ready_report.get("validated_clips") != 3
        ):
            raise RuntimeError("complete collection status was not ready")

        frozen = fixture_root / "frozen-v1"
        build_arguments = [
            sys.executable,
            str(split_tool),
            "build",
        ]
        for manifest in manifests:
            build_arguments.extend(["--session-manifest", str(manifest)])
        build_arguments.extend(
            ["--policy", str(policy), "--output-dir", str(frozen)]
        )
        built = run(build_arguments)
        if "Built locked dataset fixture-v1" not in built.stdout:
            raise RuntimeError("split builder did not report the fixture dataset")
        summary = json.loads((frozen / "summary.json").read_text())
        if summary.get("representativeness", {}).get("passed") is not True:
            raise RuntimeError("representativeness evidence did not pass")

        narrow_policy = fixture_root / "narrow-policy.json"
        narrow = json.loads(policy.read_text(encoding="utf-8"))
        narrow["representativeness"]["splits"]["test"][
            "required_categories"
        ] = ["semantic-safety"]
        write_json(narrow_policy, narrow)
        rejected_narrow = run(
            [
                *build_arguments[:-4],
                "--policy",
                str(narrow_policy),
                "--output-dir",
                str(fixture_root / "rejected-narrow"),
            ],
            expected_exit=1,
        )
        if "representativeness requirements failed" not in rejected_narrow.stderr:
            raise RuntimeError("narrow category coverage was not rejected")

        false_duration_manifest = fixture_root / "manifests" / "false-duration.jsonl"
        false_duration_row = json.loads(
            manifests[0].read_text(encoding="utf-8").strip()
        )
        false_duration_row["duration_seconds"] = 29.0
        false_duration_manifest.write_text(
            json.dumps(false_duration_row, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        false_duration_arguments = [
            sys.executable,
            str(split_tool),
            "build",
            "--session-manifest",
            str(false_duration_manifest),
            "--session-manifest",
            str(manifests[1]),
            "--session-manifest",
            str(manifests[2]),
            "--policy",
            str(policy),
            "--output-dir",
            str(fixture_root / "rejected-false-duration"),
        ]
        rejected_duration = run(false_duration_arguments, expected_exit=1)
        if "audio duration changed" not in rejected_duration.stderr:
            raise RuntimeError("false manifest duration was not rejected")

        verified = run(
            [
                sys.executable,
                str(split_tool),
                "verify",
                "--dataset-dir",
                str(frozen),
            ]
        )
        if "Verified locked dataset fixture-v1" not in verified.stdout:
            raise RuntimeError("lock verifier did not report success")

        test_manifest = frozen / "test.jsonl"
        test_manifest.write_text(
            test_manifest.read_text(encoding="utf-8") + "\n",
            encoding="utf-8",
        )
        rejected = run(
            [
                sys.executable,
                str(split_tool),
                "verify",
                "--dataset-dir",
                str(frozen),
            ],
            expected_exit=1,
        )
        if "locked artifact changed" not in rejected.stderr:
            raise RuntimeError("mutated frozen test manifest was not rejected")

        consent_path = (
            fixture_root
            / "speaker-a"
            / "speaker-a-session"
            / "consent.json"
        )
        original_consent = json.loads(consent_path.read_text(encoding="utf-8"))
        false_consent = {**original_consent, "consent_statement_accepted": False}
        write_json(consent_path, false_consent)
        forged_manifest = fixture_root / "manifests" / "forged-consent.jsonl"
        forged_row = json.loads(manifests[0].read_text(encoding="utf-8").strip())
        forged_row["consent_sha256"] = sha256(consent_path)
        forged_manifest.write_text(
            json.dumps(forged_row, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        forged_status_arguments = [
            sys.executable,
            str(split_tool),
            "status",
            "--session-manifest",
            str(forged_manifest),
            "--session-manifest",
            str(manifests[1]),
            "--session-manifest",
            str(manifests[2]),
            "--policy",
            str(policy),
        ]
        rejected_consent = run(forged_status_arguments, expected_exit=1)
        if "consent field consent_statement_accepted" not in rejected_consent.stderr:
            raise RuntimeError("forged manifest simulated participant consent")
        write_json(consent_path, original_consent)

        prompt_pack = (
            fixture_root
            / "speaker-a"
            / "speaker-a-session"
            / "prompts.jsonl"
        )
        prompt_pack.write_text(
            prompt_pack.read_text(encoding="utf-8") + "\n",
            encoding="utf-8",
        )
        rejected_prompts = run(ready_status_arguments, expected_exit=1)
        if "unexpected prompt pack" not in rejected_prompts.stderr:
            raise RuntimeError("modified prompt pack was not rejected")

        print(
            "Consented dictation pipeline checks passed: validation, "
            "read-only status, representativeness, speaker-disjoint split, "
            "independent consent, prompt provenance, lock verification, "
            "tamper rejection"
        )
        return 0
    finally:
        if fixture_root.parent.resolve() != datasets.resolve():
            raise RuntimeError("refusing to remove fixture outside Datasets")
        shutil.rmtree(fixture_root)


if __name__ == "__main__":
    raise SystemExit(main())
