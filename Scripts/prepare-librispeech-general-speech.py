#!/usr/bin/env python3
"""Prepare and verify the pinned Mini LibriSpeech general-speech corpus.

The archive must be downloaded from OpenSLR SLR31 and match both the
publisher's MD5 and ZenVoice's SHA-256 pin. Preparation extracts only regular
files, records per-audio hashes and attribution, and emits a deterministic
training manifest. This read audiobook speech is a clean-speech regularizer;
it is never labelled representative ZenVoice dictation or used as the frozen
dictation test set.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tarfile
from pathlib import Path
from typing import Any


SOURCE_NAME = "Mini LibriSpeech train-clean-5"
PUBLISHER = "Open Speech and Language Resources (OpenSLR)"
SOURCE_URL = "https://www.openslr.org/resources/31/train-clean-5.tar.gz"
LANDING_PAGE = "https://www.openslr.org/31/"
LICENSE = "CC-BY-4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"
OFFICIAL_MD5 = "5df7d4e78065366204ca6845bb08f490"
PINNED_SHA256 = "47805806c8b15f7549f3c51bd6b7da72ec0128a34d32830c8014a88658c0292d"
EXPECTED_ROOT = Path("LibriSpeech/train-clean-5")


def digest(path: Path, algorithm: str) -> str:
    value = hashlib.new(algorithm)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def sha256(path: Path) -> str:
    return digest(path, "sha256")


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def repo_paths(path: Path, repo_root: Path, label: str) -> Path:
    resolved = path.resolve()
    datasets = (repo_root / "Datasets").resolve()
    try:
        resolved.relative_to(datasets)
    except ValueError as error:
        raise ValueError(f"{label} must be inside {datasets}") from error
    return resolved


def validate_archive(archive: Path) -> None:
    if not archive.is_file():
        raise ValueError(f"archive not found: {archive}")
    if digest(archive, "md5") != OFFICIAL_MD5:
        raise ValueError("archive does not match OpenSLR's official MD5")
    if sha256(archive) != PINNED_SHA256:
        raise ValueError("archive does not match ZenVoice's SHA-256 pin")


def extract_safely(archive: Path, destination: Path) -> None:
    destination_root = destination.resolve()
    with tarfile.open(archive, mode="r:gz") as bundle:
        members = bundle.getmembers()
        if not members:
            raise ValueError("archive is empty")
        for member in members:
            if member.issym() or member.islnk() or member.isdev():
                raise ValueError(f"unsupported archive member: {member.name}")
            member_path = Path(member.name)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise ValueError(f"archive member escapes output: {member.name}")
            target = (destination / member_path).resolve()
            try:
                target.relative_to(destination_root)
            except ValueError as error:
                raise ValueError(
                    f"archive member escapes output: {member.name}"
                ) from error
        bundle.extractall(destination, members=members)


def transcripts(source_root: Path) -> dict[str, str]:
    rows: dict[str, str] = {}
    for path in sorted(source_root.rglob("*.trans.txt")):
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(),
            start=1,
        ):
            parts = line.strip().split(maxsplit=1)
            if len(parts) != 2 or not parts[1].strip():
                raise ValueError(f"invalid transcript at {path}:{line_number}")
            identifier, text = parts
            if identifier in rows:
                raise ValueError(f"duplicate utterance ID: {identifier}")
            rows[identifier] = " ".join(text.split())
    if not rows:
        raise ValueError("no LibriSpeech transcripts found")
    return rows


def audio_info(path: Path) -> tuple[int, int, float]:
    try:
        import soundfile as sf
    except ImportError as error:
        raise ValueError("preparation requires the soundfile package") from error
    info = sf.info(path)
    return info.samplerate, info.channels, info.duration


def build_manifest(
    source_root: Path,
    final_source_root: Path,
    manifest: Path,
    repo_root: Path,
) -> tuple[int, float, int]:
    text_by_id = transcripts(source_root)
    rows: list[dict[str, Any]] = []
    speakers: set[str] = set()
    total_seconds = 0.0
    for audio in sorted(source_root.rglob("*.flac")):
        identifier = audio.stem
        text = text_by_id.pop(identifier, None)
        if text is None:
            raise ValueError(f"audio has no transcript: {audio}")
        sample_rate, channels, duration = audio_info(audio)
        if sample_rate != 16_000 or channels != 1:
            raise ValueError(f"expected 16 kHz mono FLAC: {audio}")
        if not 0.5 <= duration <= 30.0:
            raise ValueError(f"unsupported duration {duration:.3f}s: {audio}")
        speaker = identifier.split("-", maxsplit=1)[0]
        speakers.add(speaker)
        total_seconds += duration
        final_audio = final_source_root / audio.relative_to(source_root)
        rows.append(
            {
                "audio": str(final_audio.relative_to(repo_root)),
                "text": text,
                "duration_seconds": round(duration, 6),
                "source": SOURCE_NAME,
                "publisher": PUBLISHER,
                "source_url": SOURCE_URL,
                "source_landing_page": LANDING_PAGE,
                "source_subset": "train-clean-5",
                "license": LICENSE,
                "license_url": LICENSE_URL,
                "speaker_id": speaker,
                "utterance_id": identifier,
                "audio_sha256": sha256(audio),
            }
        )
    if text_by_id:
        raise ValueError(
            f"{len(text_by_id)} transcript(s) have no matching audio"
        )
    if not rows:
        raise ValueError("no LibriSpeech audio found")
    with manifest.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")
    return len(rows), total_seconds, len(speakers)


def prepare(args: argparse.Namespace, repo_root: Path) -> None:
    archive = repo_paths(args.archive, repo_root, "--archive")
    output = repo_paths(args.output_dir, repo_root, "--output-dir")
    if output.exists():
        raise ValueError(f"refusing to overwrite output: {output}")
    validate_archive(archive)
    temporary = output.with_name(output.name + ".preparing")
    if temporary.exists():
        raise ValueError(f"stale preparation directory exists: {temporary}")
    temporary.mkdir(parents=True)
    try:
        extract_safely(archive, temporary / "source")
        source_root = temporary / "source" / EXPECTED_ROOT
        if not source_root.is_dir():
            raise ValueError(f"archive lacks expected root: {EXPECTED_ROOT}")
        manifest = temporary / "train.jsonl"
        clips, seconds, speakers = build_manifest(
            source_root,
            output / "source" / EXPECTED_ROOT,
            manifest,
            repo_root,
        )
        provenance = {
            "schema_version": 1,
            "purpose": "general English clean-speech training regularizer",
            "representative_dictation": False,
            "source": SOURCE_NAME,
            "publisher": PUBLISHER,
            "source_url": SOURCE_URL,
            "source_landing_page": LANDING_PAGE,
            "source_subset": "train-clean-5",
            "license": LICENSE,
            "license_url": LICENSE_URL,
            "required_attribution": (
                "Mini LibriSpeech/LibriSpeech, OpenSLR SLR31; "
                "licensed under CC BY 4.0"
            ),
            "archive": str(archive.relative_to(repo_root)),
            "archive_bytes": archive.stat().st_size,
            "archive_official_md5": OFFICIAL_MD5,
            "archive_sha256": PINNED_SHA256,
            "manifest": "train.jsonl",
            "manifest_sha256": sha256(manifest),
            "clips": clips,
            "speakers": speakers,
            "hours": round(seconds / 3600.0, 6),
            "local_training_status": "recorded; not a release approval",
            "redistribution_review": "pending",
        }
        (temporary / "provenance.json").write_text(
            json.dumps(provenance, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        temporary.replace(output)
        print(json.dumps(provenance, indent=2, sort_keys=True))
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def verify(args: argparse.Namespace, repo_root: Path) -> None:
    dataset = repo_paths(args.dataset_dir, repo_root, "--dataset-dir")
    provenance_path = dataset / "provenance.json"
    manifest = dataset / "train.jsonl"
    provenance = read_json(provenance_path)
    if provenance.get("schema_version") != 1:
        raise ValueError("provenance schema_version must be 1")
    expected_values = {
        "source": SOURCE_NAME,
        "publisher": PUBLISHER,
        "source_url": SOURCE_URL,
        "source_subset": "train-clean-5",
        "license": LICENSE,
        "archive_official_md5": OFFICIAL_MD5,
        "archive_sha256": PINNED_SHA256,
        "manifest": "train.jsonl",
        "representative_dictation": False,
    }
    for key, expected in expected_values.items():
        if provenance.get(key) != expected:
            raise ValueError(f"unexpected provenance {key}")
    if provenance.get("redistribution_review") not in {"pending", "approved"}:
        raise ValueError("invalid redistribution review state")
    archive_value = provenance.get("archive")
    if not isinstance(archive_value, str):
        raise ValueError("provenance archive path is missing")
    archive = repo_paths(repo_root / archive_value, repo_root, "archive")
    validate_archive(archive)
    if sha256(manifest) != provenance.get("manifest_sha256"):
        raise ValueError("general training manifest changed")

    hashes: set[str] = set()
    clips = 0
    seconds = 0.0
    speakers: set[str] = set()
    with manifest.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            if not isinstance(row, dict):
                raise ValueError(f"invalid manifest row {line_number}")
            if row.get("source") != SOURCE_NAME or row.get("license") != LICENSE:
                raise ValueError(f"provenance mismatch at row {line_number}")
            audio_value = row.get("audio")
            if not isinstance(audio_value, str) or Path(audio_value).is_absolute():
                raise ValueError(f"invalid audio path at row {line_number}")
            audio = repo_paths(repo_root / audio_value, repo_root, "audio")
            actual_hash = sha256(audio)
            if actual_hash != row.get("audio_sha256"):
                raise ValueError(f"audio changed at row {line_number}: {audio}")
            if actual_hash in hashes:
                raise ValueError(f"duplicate audio at row {line_number}")
            hashes.add(actual_hash)
            clips += 1
            seconds += float(row["duration_seconds"])
            speakers.add(str(row["speaker_id"]))
    if clips != provenance.get("clips") or len(speakers) != provenance.get("speakers"):
        raise ValueError("manifest counts do not match provenance")
    if abs(round(seconds / 3600.0, 6) - float(provenance.get("hours"))) > 1e-6:
        raise ValueError("manifest duration does not match provenance")
    print(
        f"Verified {clips} Mini LibriSpeech clips, "
        f"{seconds / 3600.0:.3f} hours, {len(speakers)} speakers"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--archive", type=Path, required=True)
    prepare_parser.add_argument("--output-dir", type=Path, required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--dataset-dir", type=Path, required=True)
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    if args.command == "prepare":
        prepare(args, repo_root)
    else:
        verify(args, repo_root)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, tarfile.TarError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
