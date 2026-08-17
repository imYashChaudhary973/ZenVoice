#!/usr/bin/env python3
"""Prepare Mozilla Common Voice Spontaneous English for ZenVoice experiments.

The archive must be downloaded by a person who accepted Mozilla Data
Collective's terms. This tool never downloads data or accepts terms. It binds a
human license review to the archive SHA-256, extracts the untrusted tarball
safely, retains only validated train/dev/test rows without QA flags, converts
MP3 audio to 16 kHz mono PCM WAV, verifies speaker-disjoint splits, and writes
checksum-locked manifests under ZenVoice's gitignored Datasets directory.

Common Voice spontaneous speech is a useful public training supplement. It is
not labelled as representative ZenVoice dictation and does not replace the
frozen product-safety set for numbers, negations, punctuation, and coding terms.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
import shutil
import sys
import tarfile
import wave
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


DATASET_ID = "common-voice-spontaneous-speech-4.0-english"
DATASET_REVISION = "4.0-2026-06-12"
DATASET_PAGE = (
    "https://mozilladatacollective.com/datasets/"
    "cmqialpeo0077nr077xqdqo0j"
)
PUBLISHER = "Mozilla Foundation"
LICENSE = "CC0-1.0"
LICENSE_URL = "https://creativecommons.org/publicdomain/zero/1.0/"
LOCALE = "en"
SPLIT_MAP = {"train": "train", "dev": "validation", "test": "test"}
REQUIRED_COLUMNS = {
    "client_id",
    "audio_id",
    "audio_file",
    "duration_ms",
    "prompt_id",
    "prompt",
    "transcription",
    "votes",
    "language",
    "split",
    "quality_tags",
}
MIN_TOTAL_CLIPS = 500
MIN_TOTAL_HOURS = 3.0
MIN_SPLIT_CLIPS = {"train": 300, "validation": 100, "test": 100}
MIN_SPLIT_SPEAKERS = {"train": 5, "validation": 2, "test": 2}
MIN_DURATION_SECONDS = 0.5
MAX_DURATION_SECONDS = 30.0
MAX_ARCHIVE_MEMBERS = 50_000
MAX_ARCHIVE_UNCOMPRESSED_BYTES = 10 * 1024 * 1024 * 1024
ANNOTATION_PATTERN = re.compile(r"\[(?:[a-z][a-z -]{0,30})\]")


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


def write_json(path: Path, value: object) -> None:
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def require_inside_datasets(path: Path, repo_root: Path, label: str) -> Path:
    resolved = path.resolve()
    datasets = (repo_root / "Datasets").resolve()
    try:
        resolved.relative_to(datasets)
    except ValueError as error:
        raise ValueError(f"{label} must be inside {datasets}") from error
    return resolved


def require_iso_timestamp(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} is missing")
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError(f"{label} is not ISO-8601") from error
    return value


def initialize_review(archive: Path, output: Path, repo_root: Path) -> None:
    archive = require_inside_datasets(archive, repo_root, "--archive")
    output = require_inside_datasets(output, repo_root, "--output")
    if not archive.is_file():
        raise ValueError(f"archive not found: {archive}")
    if output.exists():
        raise ValueError(f"refusing to overwrite review: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    review = {
        "schema_version": 1,
        "dataset_id": DATASET_ID,
        "dataset_revision": DATASET_REVISION,
        "dataset_page": DATASET_PAGE,
        "publisher": PUBLISHER,
        "license": LICENSE,
        "license_url": LICENSE_URL,
        "archive": str(archive.relative_to(repo_root)),
        "archive_bytes": archive.stat().st_size,
        "archive_sha256": sha256(archive),
        "dataset_access_terms_accepted": False,
        "license_approved_for_local_training": False,
        "redistribution_review": "pending",
        "reviewed_by": "replace-with-reviewer",
        "reviewed_at": "replace-with-ISO-8601-timestamp",
        "notes": (
            "A person must review Mozilla Data Collective terms and the CC0 "
            "license. Do not set approval fields automatically."
        ),
    }
    write_json(output, review)
    print(f"Created review template at {output}")
    print("Review the terms, then truthfully update the approval fields.")


def validate_review(review_path: Path, archive: Path) -> dict[str, Any]:
    review = read_json(review_path)
    expected = {
        "schema_version": 1,
        "dataset_id": DATASET_ID,
        "dataset_revision": DATASET_REVISION,
        "dataset_page": DATASET_PAGE,
        "publisher": PUBLISHER,
        "license": LICENSE,
        "license_url": LICENSE_URL,
        "archive_sha256": sha256(archive),
        "archive_bytes": archive.stat().st_size,
    }
    for key, value in expected.items():
        if review.get(key) != value:
            raise ValueError(f"license review has unexpected {key}")
    if review.get("dataset_access_terms_accepted") is not True:
        raise ValueError("dataset access terms have not been accepted by a person")
    if review.get("license_approved_for_local_training") is not True:
        raise ValueError("license has not been approved for local training")
    if review.get("redistribution_review") not in {
        "pending",
        "approved",
        "prohibited",
    }:
        raise ValueError("license review has invalid redistribution_review")
    reviewer = review.get("reviewed_by")
    if (
        not isinstance(reviewer, str)
        or not reviewer.strip()
        or reviewer.startswith("replace-with-")
    ):
        raise ValueError("license review lacks a real reviewer")
    require_iso_timestamp(review.get("reviewed_at"), "reviewed_at")
    return review


def extract_safely(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    destination_root = destination.resolve()
    with tarfile.open(archive, mode="r:gz") as bundle:
        members = bundle.getmembers()
        if not members:
            raise ValueError("archive is empty")
        if len(members) > MAX_ARCHIVE_MEMBERS:
            raise ValueError("archive contains too many members")
        total_bytes = sum(member.size for member in members if member.isfile())
        if total_bytes > MAX_ARCHIVE_UNCOMPRESSED_BYTES:
            raise ValueError("archive expands beyond the safety limit")
        for member in members:
            member_path = Path(member.name)
            if (
                member_path.is_absolute()
                or ".." in member_path.parts
                or member.issym()
                or member.islnk()
                or member.isdev()
            ):
                raise ValueError(f"unsafe archive member: {member.name}")
            target = (destination / member_path).resolve()
            try:
                target.relative_to(destination_root)
            except ValueError as error:
                raise ValueError(
                    f"archive member escapes output: {member.name}"
                ) from error
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if not member.isfile():
                raise ValueError(f"unsupported archive member: {member.name}")
            target.parent.mkdir(parents=True, exist_ok=True)
            source = bundle.extractfile(member)
            if source is None:
                raise ValueError(f"cannot read archive member: {member.name}")
            with source, target.open("wb") as output:
                shutil.copyfileobj(source, output)


def find_dataset_root(extracted: Path) -> tuple[Path, Path]:
    candidates = sorted(extracted.rglob(f"ss-corpus-{LOCALE}.tsv"))
    if len(candidates) != 1:
        raise ValueError(
            f"expected one ss-corpus-{LOCALE}.tsv, found {len(candidates)}"
        )
    tsv = candidates[0]
    root = tsv.parent
    if not (root / "audios").is_dir():
        raise ValueError("dataset archive lacks the audios directory")
    if not (root / "README.md").is_file():
        raise ValueError("dataset archive lacks its locale datasheet")
    return root, tsv


def normalize_transcription(value: str) -> tuple[str, int]:
    annotation_count = len(ANNOTATION_PATTERN.findall(value))
    normalized = ANNOTATION_PATTERN.sub(" ", value)
    return " ".join(normalized.split()), annotation_count


def convert_mp3_to_wav(source: Path, destination: Path) -> None:
    try:
        import numpy as np
        import soundfile as sf
        from scipy.signal import resample_poly
    except ImportError as error:
        raise ValueError(
            "audio conversion requires ZenVoice's training virtual environment"
        ) from error
    samples, sample_rate = sf.read(
        source,
        dtype="float32",
        always_2d=True,
    )
    if sample_rate <= 0 or samples.shape[0] == 0:
        raise ValueError(f"decoded audio is empty: {source}")
    mono = np.mean(samples, axis=1, dtype=np.float32)
    if sample_rate != 16_000:
        divisor = math.gcd(sample_rate, 16_000)
        mono = resample_poly(
            mono,
            16_000 // divisor,
            sample_rate // divisor,
        ).astype(np.float32, copy=False)
    mono = np.clip(mono, -1.0, 1.0)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sf.write(
        destination,
        mono,
        16_000,
        format="WAV",
        subtype="PCM_16",
    )


def inspect_wav(path: Path) -> float:
    with wave.open(str(path), "rb") as reader:
        if (
            reader.getnchannels() != 1
            or reader.getsampwidth() != 2
            or reader.getframerate() != 16_000
        ):
            raise ValueError(f"unexpected converted WAV format: {path}")
        duration = reader.getnframes() / reader.getframerate()
    if not MIN_DURATION_SECONDS <= duration <= MAX_DURATION_SECONDS:
        raise ValueError(f"unsupported converted duration {duration:.3f}s: {path}")
    return duration


def parse_positive_int(value: str, label: str, line_number: int) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise ValueError(f"invalid {label} at TSV line {line_number}") from error
    if parsed < 0:
        raise ValueError(f"negative {label} at TSV line {line_number}")
    return parsed


def build_manifests(
    dataset_root: Path,
    tsv: Path,
    temporary: Path,
    final_output: Path,
    repo_root: Path,
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, Any]]:
    rows_by_split: dict[str, list[dict[str, Any]]] = {
        split: [] for split in SPLIT_MAP.values()
    }
    seen_audio_ids: set[str] = set()
    seen_audio_hashes: set[str] = set()
    excluded = Counter()
    annotations_removed = 0
    with tsv.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        fields = set(reader.fieldnames or [])
        missing = sorted(REQUIRED_COLUMNS - fields)
        if missing:
            raise ValueError(f"dataset TSV lacks columns: {', '.join(missing)}")
        for line_number, source_row in enumerate(reader, start=2):
            source_split = (source_row.get("split") or "").strip()
            if source_split not in SPLIT_MAP:
                excluded["unassigned"] += 1
                continue
            quality_tags = tuple(
                tag.strip()
                for tag in (source_row.get("quality_tags") or "").split("|")
                if tag.strip()
            )
            if quality_tags:
                excluded["quality-tagged"] += 1
                continue
            duration_ms = parse_positive_int(
                source_row.get("duration_ms") or "", "duration_ms", line_number
            )
            declared_duration = duration_ms / 1000.0
            if not MIN_DURATION_SECONDS <= declared_duration <= MAX_DURATION_SECONDS:
                excluded["duration-out-of-range"] += 1
                continue
            audio_id = (source_row.get("audio_id") or "").strip()
            if not audio_id.isdigit() or audio_id in seen_audio_ids:
                raise ValueError(f"invalid or duplicate audio_id at TSV line {line_number}")
            audio_file = (source_row.get("audio_file") or "").strip()
            if Path(audio_file).name != audio_file or not audio_file.endswith(".mp3"):
                raise ValueError(f"unsafe audio_file at TSV line {line_number}")
            source_audio = dataset_root / "audios" / audio_file
            if not source_audio.is_file():
                raise ValueError(f"missing audio at TSV line {line_number}: {audio_file}")
            speaker_id = (source_row.get("client_id") or "").strip()
            if not speaker_id or len(speaker_id) > 256:
                raise ValueError(f"invalid client_id at TSV line {line_number}")
            language = (source_row.get("language") or "").strip().lower()
            if language not in {"en", "english"}:
                raise ValueError(f"unexpected language at TSV line {line_number}")
            transcription, removed = normalize_transcription(
                source_row.get("transcription") or ""
            )
            if not transcription or len(transcription) > 2_000:
                excluded["invalid-transcription"] += 1
                continue
            prompt = " ".join((source_row.get("prompt") or "").split())
            if not prompt or len(prompt) > 2_000:
                raise ValueError(f"invalid prompt at TSV line {line_number}")
            destination_split = SPLIT_MAP[source_split]
            wav_name = f"cv-sps-en-{audio_id}.wav"
            temporary_audio = temporary / "audio" / destination_split / wav_name
            convert_mp3_to_wav(source_audio, temporary_audio)
            actual_duration = inspect_wav(temporary_audio)
            tolerance = max(0.5, declared_duration * 0.05)
            if abs(actual_duration - declared_duration) > tolerance:
                raise ValueError(
                    f"converted duration differs at TSV line {line_number}: "
                    f"declared {declared_duration:.3f}s, actual {actual_duration:.3f}s"
                )
            audio_hash = sha256(temporary_audio)
            if audio_hash in seen_audio_hashes:
                raise ValueError(f"duplicate decoded audio at TSV line {line_number}")
            seen_audio_ids.add(audio_id)
            seen_audio_hashes.add(audio_hash)
            annotations_removed += removed
            final_audio = final_output / "audio" / destination_split / wav_name
            rows_by_split[destination_split].append(
                {
                    "audio": str(final_audio.relative_to(repo_root)),
                    "text": transcription,
                    "duration_seconds": round(actual_duration, 6),
                    "source": "Mozilla Common Voice Spontaneous Speech 4.0 English",
                    "publisher": PUBLISHER,
                    "source_url": DATASET_PAGE,
                    "source_subset": source_split,
                    "license": LICENSE,
                    "license_url": LICENSE_URL,
                    "speaker_id": speaker_id,
                    "audio_id": audio_id,
                    "prompt_id": (source_row.get("prompt_id") or "").strip(),
                    "prompt": prompt,
                    "votes": parse_positive_int(
                        source_row.get("votes") or "0", "votes", line_number
                    ),
                    "transcription_annotations_removed": removed,
                    "source_audio_sha256": sha256(source_audio),
                    "audio_sha256": audio_hash,
                }
            )
    details = {
        "excluded": dict(sorted(excluded.items())),
        "transcription_annotations_removed": annotations_removed,
    }
    return rows_by_split, details


def validate_coverage(rows_by_split: dict[str, list[dict[str, Any]]]) -> dict[str, Any]:
    speakers_by_split = {
        split: {str(row["speaker_id"]) for row in rows}
        for split, rows in rows_by_split.items()
    }
    for left in speakers_by_split:
        for right in speakers_by_split:
            if left >= right:
                continue
            overlap = speakers_by_split[left] & speakers_by_split[right]
            if overlap:
                raise ValueError(
                    f"speaker overlap between {left} and {right}: {next(iter(overlap))}"
                )
    failures: list[str] = []
    total_clips = sum(len(rows) for rows in rows_by_split.values())
    total_seconds = sum(
        float(row["duration_seconds"])
        for rows in rows_by_split.values()
        for row in rows
    )
    if total_clips < MIN_TOTAL_CLIPS:
        failures.append(f"total clips {total_clips} < {MIN_TOTAL_CLIPS}")
    if total_seconds / 3600.0 < MIN_TOTAL_HOURS:
        failures.append(
            f"total hours {total_seconds / 3600.0:.4f} < {MIN_TOTAL_HOURS}"
        )
    splits: dict[str, Any] = {}
    for split, rows in rows_by_split.items():
        seconds = sum(float(row["duration_seconds"]) for row in rows)
        speakers = speakers_by_split[split]
        if len(rows) < MIN_SPLIT_CLIPS[split]:
            failures.append(
                f"{split} clips {len(rows)} < {MIN_SPLIT_CLIPS[split]}"
            )
        if len(speakers) < MIN_SPLIT_SPEAKERS[split]:
            failures.append(
                f"{split} speakers {len(speakers)} < {MIN_SPLIT_SPEAKERS[split]}"
            )
        splits[split] = {
            "clips": len(rows),
            "hours": round(seconds / 3600.0, 6),
            "speakers": len(speakers),
        }
    return {
        "passed": not failures,
        "failures": failures,
        "requirements": {
            "minimum_total_clips": MIN_TOTAL_CLIPS,
            "minimum_total_hours": MIN_TOTAL_HOURS,
            "minimum_split_clips": MIN_SPLIT_CLIPS,
            "minimum_split_speakers": MIN_SPLIT_SPEAKERS,
        },
        "actual": {
            "total_clips": total_clips,
            "total_hours": round(total_seconds / 3600.0, 6),
            "total_speakers": len(set().union(*speakers_by_split.values())),
            "splits": splits,
        },
    }


def write_manifest(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in sorted(rows, key=lambda item: int(str(item["audio_id"]))):
            handle.write(json.dumps(row, sort_keys=True) + "\n")


def prepare(args: argparse.Namespace, repo_root: Path) -> None:
    archive = require_inside_datasets(args.archive, repo_root, "--archive")
    review_path = require_inside_datasets(
        args.license_review, repo_root, "--license-review"
    )
    output = require_inside_datasets(args.output_dir, repo_root, "--output-dir")
    if not archive.is_file():
        raise ValueError(f"archive not found: {archive}")
    if not review_path.is_file():
        raise ValueError(f"license review not found: {review_path}")
    if output.exists():
        raise ValueError(f"refusing to overwrite output: {output}")
    review = validate_review(review_path, archive)
    temporary = output.with_name(output.name + ".preparing")
    if temporary.exists():
        raise ValueError(f"stale preparation directory exists: {temporary}")
    temporary.mkdir(parents=True)
    try:
        extracted = temporary / "extracted"
        extract_safely(archive, extracted)
        dataset_root, tsv = find_dataset_root(extracted)
        rows_by_split, preparation = build_manifests(
            dataset_root, tsv, temporary, output, repo_root
        )
        coverage = validate_coverage(rows_by_split)
        if not coverage["passed"]:
            raise ValueError(
                "public corpus does not meet coverage contract: "
                + "; ".join(coverage["failures"])
            )
        shutil.rmtree(extracted)
        manifest_paths: dict[str, Path] = {}
        for split, rows in rows_by_split.items():
            manifest_path = temporary / f"{split}.jsonl"
            write_manifest(manifest_path, rows)
            manifest_paths[split] = manifest_path
        summary = {
            "schema_version": 1,
            "dataset_id": DATASET_ID,
            "dataset_revision": DATASET_REVISION,
            "dataset_kind": "public-spontaneous-speech-supplement",
            "representative_zenvoice_dictation": False,
            "speaker_disjoint": True,
            "coverage": coverage,
            "preparation": preparation,
        }
        summary_path = temporary / "summary.json"
        write_json(summary_path, summary)
        provenance = {
            "schema_version": 1,
            "purpose": "public spontaneous English training supplement",
            "representative_dictation": False,
            "source": "Mozilla Common Voice Spontaneous Speech 4.0 English",
            "publisher": PUBLISHER,
            "source_url": DATASET_PAGE,
            "source_landing_page": DATASET_PAGE,
            "source_subset": "validated train split",
            "license": LICENSE,
            "license_url": LICENSE_URL,
            "required_attribution": (
                "CC0 does not require attribution; retain Mozilla Common Voice "
                "source and corpus citation in model provenance."
            ),
            "archive": str(archive.relative_to(repo_root)),
            "archive_bytes": archive.stat().st_size,
            "archive_sha256": sha256(archive),
            "license_review": str(review_path.relative_to(repo_root)),
            "license_review_sha256": sha256(review_path),
            "manifest": "train.jsonl",
            "manifest_sha256": sha256(manifest_paths["train"]),
            "redistribution_review": review["redistribution_review"],
            "local_training_status": "approved by recorded human review",
        }
        provenance_path = temporary / "provenance.json"
        write_json(provenance_path, provenance)
        locked_paths = [*manifest_paths.values(), summary_path, provenance_path]
        lock = {
            "schema_version": 1,
            "dataset_id": DATASET_ID,
            "dataset_revision": DATASET_REVISION,
            "archive_sha256": sha256(archive),
            "immutable_artifacts": {
                path.name: sha256(path) for path in locked_paths
            },
            "held_out_validation_sha256": sha256(manifest_paths["validation"]),
            "held_out_test_sha256": sha256(manifest_paths["test"]),
        }
        write_json(temporary / "PUBLIC_CORPUS_LOCK.json", lock)
        temporary.replace(output)
        print(json.dumps({**summary, "provenance": provenance}, indent=2, sort_keys=True))
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def verify(args: argparse.Namespace, repo_root: Path) -> None:
    dataset = require_inside_datasets(args.dataset_dir, repo_root, "--dataset-dir")
    lock = read_json(dataset / "PUBLIC_CORPUS_LOCK.json")
    if lock.get("schema_version") != 1 or lock.get("dataset_id") != DATASET_ID:
        raise ValueError("invalid public corpus lock")
    artifacts = lock.get("immutable_artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        raise ValueError("public corpus lock has no immutable artifacts")
    for name, expected_hash in artifacts.items():
        if not isinstance(name, str) or Path(name).name != name:
            raise ValueError(f"invalid locked artifact name: {name!r}")
        path = dataset / name
        if not path.is_file() or sha256(path) != expected_hash:
            raise ValueError(f"locked public corpus artifact changed: {path}")
    provenance = read_json(dataset / "provenance.json")
    archive_value = provenance.get("archive")
    review_value = provenance.get("license_review")
    if not isinstance(archive_value, str) or not isinstance(review_value, str):
        raise ValueError("public corpus provenance lacks archive or review")
    archive = require_inside_datasets(repo_root / archive_value, repo_root, "archive")
    review_path = require_inside_datasets(
        repo_root / review_value, repo_root, "license review"
    )
    if sha256(archive) != provenance.get("archive_sha256"):
        raise ValueError("public corpus archive changed")
    if sha256(review_path) != provenance.get("license_review_sha256"):
        raise ValueError("public corpus license review changed")
    validate_review(review_path, archive)
    rows_by_split: dict[str, list[dict[str, Any]]] = {}
    audio_hashes: set[str] = set()
    for split in ("train", "validation", "test"):
        rows: list[dict[str, Any]] = []
        with (dataset / f"{split}.jsonl").open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.strip():
                    continue
                row = json.loads(line)
                audio_value = row.get("audio")
                if not isinstance(audio_value, str) or Path(audio_value).is_absolute():
                    raise ValueError(f"invalid audio path in {split}:{line_number}")
                audio = require_inside_datasets(
                    repo_root / audio_value, repo_root, "manifest audio"
                )
                actual_hash = sha256(audio)
                if actual_hash != row.get("audio_sha256"):
                    raise ValueError(f"audio changed in {split}:{line_number}")
                if actual_hash in audio_hashes:
                    raise ValueError(f"duplicate audio in {split}:{line_number}")
                actual_duration = inspect_wav(audio)
                if abs(actual_duration - float(row["duration_seconds"])) > 1e-6:
                    raise ValueError(f"duration changed in {split}:{line_number}")
                if row.get("source") != provenance.get("source"):
                    raise ValueError(f"source mismatch in {split}:{line_number}")
                if row.get("license") != LICENSE:
                    raise ValueError(f"license mismatch in {split}:{line_number}")
                audio_hashes.add(actual_hash)
                rows.append(row)
        rows_by_split[split] = rows
    coverage = validate_coverage(rows_by_split)
    if not coverage["passed"]:
        raise ValueError("verified public corpus no longer meets coverage contract")
    summary = read_json(dataset / "summary.json")
    if summary.get("coverage") != coverage:
        raise ValueError("public corpus coverage differs from locked summary")
    print(
        f"Verified Common Voice spontaneous corpus: "
        f"{coverage['actual']['total_clips']} clips, "
        f"{coverage['actual']['total_hours']:.3f} hours, "
        f"{coverage['actual']['total_speakers']} speakers"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    review_parser = subparsers.add_parser("init-review")
    review_parser.add_argument("--archive", type=Path, required=True)
    review_parser.add_argument("--output", type=Path, required=True)
    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--archive", type=Path, required=True)
    prepare_parser.add_argument("--license-review", type=Path, required=True)
    prepare_parser.add_argument("--output-dir", type=Path, required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--dataset-dir", type=Path, required=True)
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    if args.command == "init-review":
        initialize_review(args.archive, args.output, repo_root)
    elif args.command == "prepare":
        prepare(args, repo_root)
    else:
        verify(args, repo_root)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        OSError,
        ValueError,
        tarfile.TarError,
        json.JSONDecodeError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
