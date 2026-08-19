#!/usr/bin/env python3
"""Exercise Common Voice spontaneous-speech intake with local fixtures."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import shutil
import tarfile
import tempfile
import wave
from pathlib import Path
from types import ModuleType


def load_tool(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location("common_voice_intake", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_wav(path: Path, sample: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16_000)
        output.writeframes(int(sample).to_bytes(2, "little", signed=True) * 16_000)


def build_archive(fixture: Path) -> Path:
    source = fixture / "archive-source" / "sps-corpus-4.0-2026-06-12-en"
    audios = source / "audios"
    audios.mkdir(parents=True)
    (source / "README.md").write_text("Fixture datasheet\n", encoding="utf-8")
    fields = [
        "client_id",
        "audio_id",
        "audio_file",
        "duration_ms",
        "prompt_id",
        "prompt",
        "transcription",
        "votes",
        "age",
        "gender",
        "accents",
        "variant",
        "language",
        "prompt_upvotes",
        "prompt_reports",
        "is_edited",
        "split",
        "char_per_sec",
        "quality_tags",
    ]
    assignments = [
        *(('train', f'train-speaker-{index}') for index in range(1, 6)),
        *(('dev', f'validation-speaker-{index}') for index in range(1, 3)),
        *(('test', f'test-speaker-{index}') for index in range(1, 3)),
    ]
    tsv = source / "ss-corpus-en.tsv"
    with tsv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for index, (split, speaker) in enumerate(assignments, start=1):
            audio_file = f"spontaneous-speech-en-{index}.mp3"
            write_wav(audios / audio_file, index)
            writer.writerow(
                {
                    "client_id": speaker,
                    "audio_id": str(index),
                    "audio_file": audio_file,
                    "duration_ms": "1000",
                    "prompt_id": str(100 + index),
                    "prompt": "Describe a normal work day.",
                    "transcription": f"[disfluency] fixture response {index}",
                    "votes": "2",
                    "language": "English",
                    "split": split,
                    "char_per_sec": "10.0",
                    "quality_tags": "",
                }
            )
    archive = fixture / "common-voice-spontaneous-fixture.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        bundle.add(source, arcname=source.name)
    return archive


def expect_failure(callback: object, contains: str) -> None:
    try:
        callback()  # type: ignore[operator]
    except ValueError as error:
        if contains not in str(error):
            raise RuntimeError(
                f"expected failure containing {contains!r}, got {error!r}"
            ) from error
    else:
        raise RuntimeError(f"expected failure containing {contains!r}")


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    datasets = repo_root / "Datasets"
    fixture = Path(
        tempfile.mkdtemp(prefix=".common-voice-intake-fixture-", dir=datasets)
    )
    try:
        tool = load_tool(repo_root / "Scripts" / "prepare-common-voice-spontaneous.py")
        tool.MIN_TOTAL_CLIPS = 9
        tool.MIN_TOTAL_HOURS = 9 / 3600.0
        tool.MIN_SPLIT_CLIPS = {"train": 5, "validation": 2, "test": 2}
        tool.MIN_SPLIT_SPEAKERS = {"train": 5, "validation": 2, "test": 2}
        tool.convert_mp3_to_wav = lambda source, destination: (
            destination.parent.mkdir(parents=True, exist_ok=True),
            shutil.copy2(source, destination),
        )

        archive = build_archive(fixture)
        review = fixture / "license-review.json"
        tool.initialize_review(archive, review, repo_root)
        review_value = json.loads(review.read_text(encoding="utf-8"))
        review_value.update(
            {
                "dataset_access_terms_accepted": True,
                "license_approved_for_local_training": True,
                "redistribution_review": "prohibited",
                "reviewed_by": "fixture-reviewer",
                "reviewed_at": "2026-08-14T12:00:00Z",
            }
        )
        review.write_text(
            json.dumps(review_value, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        output = fixture / "prepared"
        tool.prepare(
            argparse.Namespace(
                archive=archive,
                license_review=review,
                output_dir=output,
            ),
            repo_root,
        )
        tool.verify(argparse.Namespace(dataset_dir=output), repo_root)

        summary = json.loads((output / "summary.json").read_text(encoding="utf-8"))
        if (
            summary["coverage"]["actual"]["total_clips"] != 9
            or summary["coverage"]["actual"]["total_speakers"] != 9
            or summary["preparation"]["transcription_annotations_removed"] != 9
            or summary["representative_zenvoice_dictation"] is not False
        ):
            raise RuntimeError("prepared corpus summary is incorrect")

        original_manifest = (output / "test.jsonl").read_text(encoding="utf-8")
        (output / "test.jsonl").write_text(original_manifest + "{}\n", encoding="utf-8")
        expect_failure(
            lambda: tool.verify(argparse.Namespace(dataset_dir=output), repo_root),
            "locked public corpus artifact changed",
        )
        (output / "test.jsonl").write_text(original_manifest, encoding="utf-8")

        overlapping = {
            "train": [{"speaker_id": "same", "duration_seconds": 1.0}],
            "validation": [{"speaker_id": "same", "duration_seconds": 1.0}],
            "test": [{"speaker_id": "other", "duration_seconds": 1.0}],
        }
        expect_failure(
            lambda: tool.validate_coverage(overlapping),
            "speaker overlap",
        )

        unsafe = fixture / "unsafe.tar.gz"
        payload = fixture / "payload.txt"
        payload.write_text("unsafe", encoding="utf-8")
        with tarfile.open(unsafe, "w:gz") as bundle:
            bundle.add(payload, arcname="../escaped.txt")
        expect_failure(
            lambda: tool.extract_safely(unsafe, fixture / "unsafe-output"),
            "unsafe archive member",
        )
        if (fixture / "escaped.txt").exists():
            raise RuntimeError("unsafe archive escaped its destination")

        print(
            "Common Voice spontaneous intake checks passed: human review, "
            "safe extraction, speaker-disjoint splits, coverage, annotation "
            "normalization, immutable manifests, and tamper rejection"
        )
        return 0
    finally:
        if fixture.parent.resolve() != datasets.resolve():
            raise RuntimeError("refusing to remove fixture outside Datasets")
        shutil.rmtree(fixture)


if __name__ == "__main__":
    raise SystemExit(main())
