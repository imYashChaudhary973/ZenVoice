#!/usr/bin/env python3
"""Build and verify checksum-locked consented-dictation data splits.

Speaker groups are assigned explicitly through a policy file. The builder
refuses overlap, missing assignments, duplicate audio, invalid consent hashes,
under-representative split coverage, and any existing output directory. A lock
file records every generated artifact, including the frozen test manifest, so
later mutation is detectable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SPLITS = ("train", "validation", "test")
POLICY_SCHEMA_VERSION = 2
CONSENT_VERSION = "zenvoice-dictation-v1"
PROMPT_PACK_VERSION = "zenvoice-dictation-prompts-v2"
PROMPT_PACK_SHA256 = (
    "e5bcb34857e491cd91483fc9180eebb092eca456941c5cff3afb2a4407268dfd"
)
REQUIRED_PROMPT_CATEGORIES = (
    "email",
    "technical",
    "numbers-dates",
    "semantic-safety",
    "self-correction",
    "punctuation",
    "long-form",
    "speaking-rate",
    "names-loanwords",
    "environment",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_inside_datasets(path: Path, repo_root: Path, label: str) -> Path:
    resolved = path.resolve()
    datasets = (repo_root / "Datasets").resolve()
    try:
        resolved.relative_to(datasets)
    except ValueError as error:
        raise ValueError(f"{label} must be inside {datasets}") from error
    return resolved


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def inspect_wav_duration(path: Path) -> float:
    with wave.open(str(path), "rb") as reader:
        if (
            reader.getnchannels() != 1
            or reader.getsampwidth() != 2
            or reader.getframerate() != 16_000
        ):
            raise ValueError(f"unexpected WAV format: {path}")
        duration = reader.getnframes() / reader.getframerate()
    if not 0.5 <= duration <= 30.0:
        raise ValueError(f"unexpected WAV duration {duration:.3f}s: {path}")
    return duration


def require_iso_timestamp(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"missing {label}")
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError(f"invalid {label}") from error
    return value


def validate_source_consent(
    consent: dict[str, Any],
    row: dict[str, Any],
    label: str,
) -> None:
    if consent.get("schema_version") != 1:
        raise ValueError(f"invalid consent schema at {label}")
    if consent.get("consent_text_version") != CONSENT_VERSION:
        raise ValueError(f"unexpected consent version at {label}")
    require_iso_timestamp(consent.get("consented_at"), f"consented_at at {label}")
    for field in (
        "participant_is_adult",
        "consent_statement_accepted",
        "local_training_allowed",
        "local_evaluation_allowed",
    ):
        if consent.get(field) is not True:
            raise ValueError(f"consent field {field} is not true at {label}")
    if consent.get("redistribution_allowed") is not False:
        raise ValueError(f"consent permits redistribution at {label}")
    if consent.get("participant_id") != row.get("participant_id"):
        raise ValueError(f"consent participant differs at {label}")


def validate_source_session(
    session: dict[str, Any],
    row: dict[str, Any],
    label: str,
) -> None:
    if session.get("schema_version") != 1:
        raise ValueError(f"invalid session schema at {label}")
    if session.get("prompt_pack_version") != PROMPT_PACK_VERSION:
        raise ValueError(f"unexpected session prompt version at {label}")
    if session.get("prompt_pack_sha256") != PROMPT_PACK_SHA256:
        raise ValueError(f"unexpected session prompt checksum at {label}")
    require_iso_timestamp(session.get("recorded_at"), f"recorded_at at {label}")
    for field in (
        "participant_id",
        "speaker_group_id",
        "session_id",
        "recorded_at",
        "language",
        "accent_self_description",
        "microphone",
        "environment",
        "prompt_pack_version",
        "prompt_pack_sha256",
    ):
        if session.get(field) != row.get(field):
            raise ValueError(f"session field {field} differs at {label}")


def initialize_policy(path: Path, repo_root: Path) -> None:
    path = require_inside_datasets(path, repo_root, "--output")
    if path.exists():
        raise ValueError(f"refusing to overwrite policy: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    policy = {
        "schema_version": POLICY_SCHEMA_VERSION,
        "dataset_version": "replace-with-version",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "assignment_unit": "speaker_group_id",
        "splits": {
            "train": {"speaker_group_ids": []},
            "validation": {"speaker_group_ids": []},
            "test": {"speaker_group_ids": []},
        },
        "representativeness": {
            "minimum_total_clips": 500,
            "minimum_total_hours": 3.0,
            "minimum_total_speaker_groups": 9,
            "splits": {
                "train": {
                    "minimum_clips": 300,
                    "minimum_hours": 2.0,
                    "minimum_speaker_groups": 5,
                    "required_categories": list(REQUIRED_PROMPT_CATEGORIES),
                    "minimum_clips_per_required_category": 5,
                },
                "validation": {
                    "minimum_clips": 100,
                    "minimum_hours": 0.25,
                    "minimum_speaker_groups": 2,
                    "required_categories": list(REQUIRED_PROMPT_CATEGORIES),
                    "minimum_clips_per_required_category": 2,
                },
                "test": {
                    "minimum_clips": 100,
                    "minimum_hours": 0.75,
                    "minimum_speaker_groups": 2,
                    "required_categories": list(REQUIRED_PROMPT_CATEGORIES),
                    "minimum_clips_per_required_category": 2,
                },
            },
        },
    }
    path.write_text(
        json.dumps(policy, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Created split-policy template at {path}")
    print("Assign every speaker group to exactly one non-empty split.")
    print(
        "Review the explicit representativeness thresholds before collection; "
        "the builder will fail closed when any threshold is missed."
    )


def require_positive_number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be a positive number")
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise ValueError(f"{label} must be a positive number")
    return number


def require_positive_integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{label} must be a positive integer")
    return value


def load_representativeness(policy: dict[str, Any]) -> dict[str, Any]:
    requirements = policy.get("representativeness")
    if not isinstance(requirements, dict):
        raise ValueError("split policy lacks representativeness requirements")
    require_positive_integer(
        requirements.get("minimum_total_clips"),
        "representativeness.minimum_total_clips",
    )
    require_positive_number(
        requirements.get("minimum_total_hours"),
        "representativeness.minimum_total_hours",
    )
    require_positive_integer(
        requirements.get("minimum_total_speaker_groups"),
        "representativeness.minimum_total_speaker_groups",
    )
    split_requirements = requirements.get("splits")
    if not isinstance(split_requirements, dict):
        raise ValueError("representativeness.splits must be an object")
    for split in SPLITS:
        config = split_requirements.get(split)
        if not isinstance(config, dict):
            raise ValueError(
                f"representativeness.splits.{split} must be an object"
            )
        require_positive_integer(
            config.get("minimum_clips"),
            f"representativeness.splits.{split}.minimum_clips",
        )
        require_positive_number(
            config.get("minimum_hours"),
            f"representativeness.splits.{split}.minimum_hours",
        )
        require_positive_integer(
            config.get("minimum_speaker_groups"),
            f"representativeness.splits.{split}.minimum_speaker_groups",
        )
        categories = config.get("required_categories")
        if not isinstance(categories, list) or not categories:
            raise ValueError(
                f"representativeness.splits.{split}.required_categories "
                "must be a non-empty list"
            )
        if len(categories) != len(set(categories)) or any(
            not isinstance(category, str) or not category.strip()
            for category in categories
        ):
            raise ValueError(
                f"representativeness.splits.{split}.required_categories "
                "must contain unique non-empty strings"
            )
        unknown = set(categories) - set(REQUIRED_PROMPT_CATEGORIES)
        if unknown:
            raise ValueError(
                f"representativeness.splits.{split} contains unknown "
                f"categories: {', '.join(sorted(unknown))}"
            )
        require_positive_integer(
            config.get("minimum_clips_per_required_category"),
            "representativeness.splits."
            f"{split}.minimum_clips_per_required_category",
        )
    return requirements


def load_policy(
    path: Path,
    *,
    allow_incomplete: bool = False,
) -> tuple[dict[str, str], dict[str, Any]]:
    policy = read_json(path)
    if policy.get("schema_version") != POLICY_SCHEMA_VERSION:
        raise ValueError(
            f"split policy schema_version must be {POLICY_SCHEMA_VERSION}"
        )
    if policy.get("assignment_unit") != "speaker_group_id":
        raise ValueError("assignment_unit must be 'speaker_group_id'")
    version = policy.get("dataset_version")
    if (
        not isinstance(version, str)
        or not version.strip()
        or (not allow_incomplete and version == "replace-with-version")
    ):
        raise ValueError("dataset_version must be set")
    raw_splits = policy.get("splits")
    if not isinstance(raw_splits, dict):
        raise ValueError("split policy must contain a splits object")

    assignments: dict[str, str] = {}
    for split in SPLITS:
        split_config = raw_splits.get(split)
        if not isinstance(split_config, dict):
            raise ValueError(f"missing split policy for {split}")
        groups = split_config.get("speaker_group_ids")
        if not isinstance(groups, list) or (not allow_incomplete and not groups):
            raise ValueError(f"{split} speaker_group_ids must be non-empty")
        for group in groups:
            if not isinstance(group, str) or not group.strip():
                raise ValueError(f"invalid speaker group in {split}")
            if group in assignments:
                raise ValueError(
                    f"speaker group {group!r} appears in multiple splits"
                )
            assignments[group] = split
    load_representativeness(policy)
    return assignments, policy


def evaluate_representativeness(
    split_rows: dict[str, list[dict[str, Any]]],
    requirements: dict[str, Any],
    *,
    fail_on_miss: bool = True,
) -> dict[str, Any]:
    all_rows = [row for split in SPLITS for row in split_rows[split]]
    total_clips = len(all_rows)
    total_hours = sum(float(row["duration_seconds"]) for row in all_rows) / 3600
    total_groups = len({str(row["speaker_group_id"]) for row in all_rows})
    failures: list[str] = []
    if total_clips < int(requirements["minimum_total_clips"]):
        failures.append(
            f"total clips {total_clips} < "
            f"{requirements['minimum_total_clips']}"
        )
    if total_hours < float(requirements["minimum_total_hours"]):
        failures.append(
            f"total hours {total_hours:.4f} < "
            f"{requirements['minimum_total_hours']}"
        )
    if total_groups < int(requirements["minimum_total_speaker_groups"]):
        failures.append(
            f"total speaker groups {total_groups} < "
            f"{requirements['minimum_total_speaker_groups']}"
        )

    split_evidence: dict[str, Any] = {}
    for split in SPLITS:
        rows = split_rows[split]
        config = requirements["splits"][split]
        clips = len(rows)
        hours = sum(float(row["duration_seconds"]) for row in rows) / 3600
        groups = len({str(row["speaker_group_id"]) for row in rows})
        category_counts: dict[str, int] = {}
        for row in rows:
            category = row.get("category")
            if not isinstance(category, str) or not category.strip():
                raise ValueError(f"missing category in {split} split")
            category_counts[category] = category_counts.get(category, 0) + 1
        if clips < int(config["minimum_clips"]):
            failures.append(
                f"{split} clips {clips} < {config['minimum_clips']}"
            )
        if hours < float(config["minimum_hours"]):
            failures.append(
                f"{split} hours {hours:.4f} < {config['minimum_hours']}"
            )
        if groups < int(config["minimum_speaker_groups"]):
            failures.append(
                f"{split} speaker groups {groups} < "
                f"{config['minimum_speaker_groups']}"
            )
        minimum_per_category = int(
            config["minimum_clips_per_required_category"]
        )
        for category in config["required_categories"]:
            count = category_counts.get(category, 0)
            if count < minimum_per_category:
                failures.append(
                    f"{split} category {category!r} clips {count} < "
                    f"{minimum_per_category}"
                )
        split_evidence[split] = {
            "actual": {
                "clips": clips,
                "hours": round(hours, 6),
                "speaker_groups": groups,
                "category_clips": dict(sorted(category_counts.items())),
            },
            "required": config,
        }

    evidence = {
        "passed": not failures,
        "actual": {
            "total_clips": total_clips,
            "total_hours": round(total_hours, 6),
            "total_speaker_groups": total_groups,
        },
        "required": {
            key: requirements[key]
            for key in (
                "minimum_total_clips",
                "minimum_total_hours",
                "minimum_total_speaker_groups",
            )
        },
        "splits": split_evidence,
        "failures": failures,
    }
    if failures and fail_on_miss:
        raise ValueError(
            "representativeness requirements failed: " + "; ".join(failures)
        )
    return evidence


def load_rows(
    manifests: list[Path],
    repo_root: Path,
    *,
    allow_empty: bool = False,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen_audio: dict[str, str] = {}
    seen_clip_paths: set[str] = set()
    for manifest in manifests:
        with manifest.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.strip():
                    continue
                row = json.loads(line)
                label = f"{manifest}:{line_number}"
                if not isinstance(row, dict):
                    raise ValueError(f"expected JSON object at {label}")
                for permission in (
                    "local_training_allowed",
                    "local_evaluation_allowed",
                ):
                    if row.get(permission) is not True:
                        raise ValueError(f"{permission} is not true at {label}")
                if row.get("redistribution_allowed") is not False:
                    raise ValueError(
                        f"redistribution_allowed must be false at {label}"
                    )
                if row.get("license") != "private-consent-local-only":
                    raise ValueError(f"unexpected license at {label}")
                if row.get("source") != "consented ZenVoice dictation":
                    raise ValueError(f"unexpected source at {label}")

                audio_value = row.get("audio")
                if not isinstance(audio_value, str):
                    raise ValueError(f"missing audio path at {label}")
                audio = (repo_root / audio_value).resolve()
                try:
                    audio.relative_to(repo_root)
                except ValueError as error:
                    raise ValueError(f"audio escapes repository at {label}") \
                        from error
                if not audio.is_file():
                    raise ValueError(f"missing audio at {label}: {audio}")
                actual_audio_hash = sha256(audio)
                if row.get("audio_sha256") != actual_audio_hash:
                    raise ValueError(f"audio hash changed at {label}")
                if actual_audio_hash in seen_audio:
                    raise ValueError(
                        f"duplicate audio at {label} and "
                        f"{seen_audio[actual_audio_hash]}"
                    )
                seen_audio[actual_audio_hash] = label
                if audio_value in seen_clip_paths:
                    raise ValueError(f"duplicate audio path at {label}")
                seen_clip_paths.add(audio_value)

                transcript = audio.with_suffix(".txt")
                if not transcript.is_file():
                    raise ValueError(f"missing transcript at {label}")
                if row.get("transcript_sha256") != sha256(transcript):
                    raise ValueError(f"transcript hash changed at {label}")
                consent = audio.parent.parent / "consent.json"
                if not consent.is_file():
                    raise ValueError(f"missing consent file at {label}")
                if row.get("consent_sha256") != sha256(consent):
                    raise ValueError(f"consent hash changed at {label}")
                validate_source_consent(read_json(consent), row, label)
                session_path = audio.parent.parent / "session.json"
                if not session_path.is_file():
                    raise ValueError(f"missing session metadata at {label}")
                if row.get("session_sha256") != sha256(session_path):
                    raise ValueError(f"session metadata changed at {label}")
                validate_source_session(read_json(session_path), row, label)
                prompt_pack = audio.parent.parent / "prompts.jsonl"
                if not prompt_pack.is_file():
                    raise ValueError(f"missing prompt pack at {label}")
                if (
                    row.get("prompt_pack_version") != PROMPT_PACK_VERSION
                    or row.get("prompt_pack_sha256") != PROMPT_PACK_SHA256
                    or sha256(prompt_pack) != PROMPT_PACK_SHA256
                ):
                    raise ValueError(f"unexpected prompt pack at {label}")
                if not isinstance(row.get("speaker_group_id"), str):
                    raise ValueError(f"missing speaker_group_id at {label}")
                if row.get("prompt_id") != audio.stem:
                    raise ValueError(f"prompt ID differs from filename at {label}")
                claimed_duration = row.get("duration_seconds")
                if (
                    isinstance(claimed_duration, bool)
                    or not isinstance(claimed_duration, (int, float))
                ):
                    raise ValueError(f"missing duration_seconds at {label}")
                actual_duration = inspect_wav_duration(audio)
                if (
                    not math.isfinite(float(claimed_duration))
                    or abs(float(claimed_duration) - actual_duration) > 0.0015
                ):
                    raise ValueError(f"audio duration changed at {label}")
                category = row.get("category")
                if category not in REQUIRED_PROMPT_CATEGORIES:
                    raise ValueError(f"unexpected category at {label}")
                rows.append(row)
    if not rows and not allow_empty:
        raise ValueError("no consented clips found")
    return rows


def report_collection_status(
    manifest_paths: list[Path],
    policy_path: Path,
    repo_root: Path,
) -> None:
    assignments, policy = load_policy(policy_path, allow_incomplete=True)
    rows = load_rows(manifest_paths, repo_root, allow_empty=True)
    split_rows: dict[str, list[dict[str, Any]]] = {
        split: [] for split in SPLITS
    }
    observed_groups = {str(row["speaker_group_id"]) for row in rows}
    unassigned_groups = sorted(observed_groups - set(assignments))
    unused_assignments = sorted(set(assignments) - observed_groups)
    for row in rows:
        split = assignments.get(str(row["speaker_group_id"]))
        if split is not None:
            split_rows[split].append({**row, "split": split})

    assignment_failures: list[str] = []
    if policy.get("dataset_version") == "replace-with-version":
        assignment_failures.append("dataset_version is still a placeholder")
    raw_splits = policy["splits"]
    for split in SPLITS:
        if not raw_splits[split]["speaker_group_ids"]:
            assignment_failures.append(
                f"{split} has no assigned speaker groups"
            )
    if unassigned_groups:
        assignment_failures.append(
            "observed speaker groups are unassigned: "
            + ", ".join(unassigned_groups)
        )
    if unused_assignments:
        assignment_failures.append(
            "policy speaker groups have no validated clips: "
            + ", ".join(unused_assignments)
        )

    representativeness = evaluate_representativeness(
        split_rows,
        policy["representativeness"],
        fail_on_miss=False,
    )
    report = {
        "schema_version": 1,
        "ready_to_freeze": (
            not assignment_failures and representativeness["passed"]
        ),
        "dataset_version": policy["dataset_version"],
        "validated_session_manifests": len(manifest_paths),
        "validated_clips": len(rows),
        "assignment_failures": assignment_failures,
        "representativeness": representativeness,
    }
    print(json.dumps(report, indent=2, sort_keys=True))


def build_splits(
    manifest_paths: list[Path],
    policy_path: Path,
    output: Path,
    repo_root: Path,
) -> None:
    output = require_inside_datasets(output, repo_root, "--output-dir")
    if output.exists():
        raise ValueError(
            f"refusing to modify existing frozen dataset directory: {output}"
        )
    assignments, policy = load_policy(policy_path)
    rows = load_rows(manifest_paths, repo_root)
    observed_groups = {str(row["speaker_group_id"]) for row in rows}
    missing = observed_groups - set(assignments)
    unused = set(assignments) - observed_groups
    if missing:
        raise ValueError(
            "speaker groups missing from policy: " + ", ".join(sorted(missing))
        )
    if unused:
        raise ValueError(
            "policy groups have no clips: " + ", ".join(sorted(unused))
        )

    split_rows = {split: [] for split in SPLITS}
    for row in rows:
        split = assignments[str(row["speaker_group_id"])]
        split_rows[split].append({**row, "split": split})

    representativeness = evaluate_representativeness(
        split_rows,
        policy["representativeness"],
    )

    output.mkdir(parents=True)
    artifact_paths: list[Path] = []
    split_summary: dict[str, Any] = {}
    for split in SPLITS:
        destination = output / f"{split}.jsonl"
        with destination.open("x", encoding="utf-8", newline="\n") as handle:
            for row in sorted(
                split_rows[split],
                key=lambda item: str(item["audio"]),
            ):
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
        artifact_paths.append(destination)
        split_summary[split] = {
            "clips": len(split_rows[split]),
            "hours": round(
                sum(float(row["duration_seconds"]) for row in split_rows[split])
                / 3600,
                4,
            ),
            "speaker_group_ids": sorted(
                {
                    str(row["speaker_group_id"])
                    for row in split_rows[split]
                }
            ),
            "manifest_sha256": sha256(destination),
        }

    summary = {
        "schema_version": 1,
        "dataset_version": policy["dataset_version"],
        "frozen": True,
        "assignment_unit": "speaker_group_id",
        "policy_sha256": sha256(policy_path),
        "source_manifest_sha256": {
            str(path.relative_to(repo_root)): sha256(path)
            for path in manifest_paths
        },
        "representativeness": representativeness,
        "splits": split_summary,
    }
    summary_path = output / "summary.json"
    summary_path.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    artifact_paths.append(summary_path)
    lock = {
        "schema_version": 1,
        "dataset_version": policy["dataset_version"],
        "created_at": datetime.now(timezone.utc).isoformat(),
        "immutable_artifacts": {
            path.name: sha256(path) for path in artifact_paths
        },
        "frozen_test_sha256": sha256(output / "test.jsonl"),
    }
    lock_path = output / "FROZEN_TEST_LOCK.json"
    lock_path.write_text(
        json.dumps(lock, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        f"Built locked dataset {policy['dataset_version']} at {output}; "
        f"test SHA-256 {lock['frozen_test_sha256']}"
    )


def verify_lock(directory: Path, repo_root: Path) -> None:
    directory = require_inside_datasets(directory, repo_root, "--dataset-dir")
    lock_path = directory / "FROZEN_TEST_LOCK.json"
    lock = read_json(lock_path)
    if lock.get("schema_version") != 1:
        raise ValueError("lock schema_version must be 1")
    artifacts = lock.get("immutable_artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        raise ValueError("lock has no immutable_artifacts")
    for name, expected in artifacts.items():
        if not isinstance(name, str) or Path(name).name != name:
            raise ValueError(f"invalid locked artifact name: {name!r}")
        path = directory / name
        if not path.is_file():
            raise ValueError(f"locked artifact is missing: {path}")
        actual = sha256(path)
        if actual != expected:
            raise ValueError(f"locked artifact changed: {path}")
    test_hash = sha256(directory / "test.jsonl")
    if test_hash != lock.get("frozen_test_sha256"):
        raise ValueError("frozen test manifest hash changed")
    print(
        f"Verified locked dataset {lock.get('dataset_version')}; "
        f"test SHA-256 {test_hash}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    initialize = commands.add_parser("init-policy")
    initialize.add_argument("--output", type=Path, required=True)
    build = commands.add_parser("build")
    build.add_argument(
        "--session-manifest",
        type=Path,
        action="append",
        required=True,
    )
    build.add_argument("--policy", type=Path, required=True)
    build.add_argument("--output-dir", type=Path, required=True)
    status = commands.add_parser(
        "status",
        help="report collection deficits without writing a frozen dataset",
    )
    status.add_argument(
        "--session-manifest",
        type=Path,
        action="append",
        default=[],
    )
    status.add_argument("--policy", type=Path, required=True)
    verify = commands.add_parser("verify")
    verify.add_argument("--dataset-dir", type=Path, required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    if args.command == "init-policy":
        initialize_policy(args.output, repo_root)
    elif args.command in {"build", "status"}:
        manifests = [
            require_inside_datasets(path, repo_root, "--session-manifest")
            for path in args.session_manifest
        ]
        policy = require_inside_datasets(args.policy, repo_root, "--policy")
        if args.command == "build":
            build_splits(manifests, policy, args.output_dir, repo_root)
        else:
            report_collection_status(manifests, policy, repo_root)
    else:
        verify_lock(args.dataset_dir, repo_root)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, wave.Error, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
