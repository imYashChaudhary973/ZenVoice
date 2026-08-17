#!/usr/bin/env python3
"""Build leakage-safe JSONL manifests for ZenVoice Whisper fine-tuning.

The input directories must contain flat ``name.wav`` + ``name.txt`` pairs.
AMI filenames are expected to begin with a meeting identifier such as
``ES2004a.A``. Meeting *series* (``ES2004``) may appear in exactly one split;
this keeps the same scenario group and speakers from leaking across train,
validation, and test data.

Generated manifests contain repo-relative paths and provenance metadata only.
Audio and transcripts remain under the gitignored ``Datasets`` directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import wave
from dataclasses import dataclass
from pathlib import Path


AMI_NAME = re.compile(
    r"^(?P<series>[A-Z]{2}\d{4})[a-z]\.(?P<speaker>[A-E])\."
)
MIN_SECONDS = 0.5
MAX_SECONDS = 30.0


@dataclass(frozen=True)
class Clip:
    audio: Path
    transcript: Path
    text: str
    duration_seconds: float
    series: str
    speaker: str
    audio_sha256: str


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_clip(audio: Path) -> Clip:
    transcript = audio.with_suffix(".txt")
    if not transcript.is_file():
        raise ValueError(f"missing transcript for {audio}")
    text = " ".join(transcript.read_text(encoding="utf-8").split())
    if not text:
        raise ValueError(f"empty transcript: {transcript}")

    match = AMI_NAME.match(audio.name)
    if match is None:
        raise ValueError(f"unsupported AMI filename: {audio.name}")

    with wave.open(str(audio), "rb") as reader:
        if reader.getnchannels() != 1:
            raise ValueError(f"expected mono WAV: {audio}")
        if reader.getsampwidth() != 2:
            raise ValueError(f"expected 16-bit PCM WAV: {audio}")
        if reader.getframerate() != 16_000:
            raise ValueError(f"expected 16 kHz WAV: {audio}")
        frames = reader.getnframes()
        duration = frames / reader.getframerate()

    if not MIN_SECONDS <= duration <= MAX_SECONDS:
        raise ValueError(
            f"clip duration {duration:.2f}s outside "
            f"{MIN_SECONDS:.1f}-{MAX_SECONDS:.1f}s: {audio}"
        )

    return Clip(
        audio=audio,
        transcript=transcript,
        text=text,
        duration_seconds=duration,
        series=match.group("series"),
        speaker=match.group("speaker"),
        audio_sha256=sha256(audio),
    )


def load_split(directory: Path) -> list[Clip]:
    if not directory.is_dir():
        raise ValueError(f"corpus directory not found: {directory}")
    audio_files = sorted(directory.glob("*.wav"))
    if not audio_files:
        raise ValueError(f"no WAV files found in {directory}")
    clips = [inspect_clip(audio) for audio in audio_files]

    paired_transcripts = {clip.transcript.resolve() for clip in clips}
    orphaned = [
        path for path in sorted(directory.glob("*.txt"))
        if path.resolve() not in paired_transcripts
    ]
    if orphaned:
        raise ValueError(f"orphaned transcript: {orphaned[0]}")
    return clips


def validate_splits(splits: dict[str, list[Clip]]) -> None:
    series_by_split = {
        name: {clip.series for clip in clips}
        for name, clips in splits.items()
    }
    names = list(splits)
    for index, left in enumerate(names):
        for right in names[index + 1 :]:
            overlap = series_by_split[left] & series_by_split[right]
            if overlap:
                raise ValueError(
                    f"meeting-series leakage between {left} and {right}: "
                    + ", ".join(sorted(overlap))
                )

    seen_audio: dict[str, str] = {}
    for split_name, clips in splits.items():
        for clip in clips:
            previous = seen_audio.get(clip.audio_sha256)
            if previous is not None:
                raise ValueError(
                    f"duplicate audio in {previous} and {split_name}: "
                    f"{clip.audio.name}"
                )
            seen_audio[clip.audio_sha256] = split_name


def relative_to_repo(path: Path, repo_root: Path) -> str:
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(repo_root))
    except ValueError as error:
        raise ValueError(f"corpus path escapes repository: {path}") from error


def write_manifest(
    destination: Path,
    clips: list[Clip],
    repo_root: Path,
) -> None:
    with destination.open("w", encoding="utf-8", newline="\n") as handle:
        for clip in clips:
            row = {
                "audio": relative_to_repo(clip.audio, repo_root),
                "text": clip.text,
                "duration_seconds": round(clip.duration_seconds, 3),
                "source": "AMI Meeting Corpus",
                "license": "CC-BY-4.0",
                "meeting_series": clip.series,
                "speaker_channel": clip.speaker,
                "audio_sha256": clip.audio_sha256,
            }
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train-dir", type=Path, required=True)
    parser.add_argument("--validation-dir", type=Path, required=True)
    parser.add_argument("--test-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    output = args.output_dir.resolve()
    datasets_root = (repo_root / "Datasets").resolve()
    try:
        output.relative_to(datasets_root)
    except ValueError:
        parser.error("--output-dir must be inside the gitignored Datasets directory")

    splits = {
        "train": load_split(args.train_dir),
        "validation": load_split(args.validation_dir),
        "test": load_split(args.test_dir),
    }
    validate_splits(splits)
    output.mkdir(parents=True, exist_ok=True)

    split_summary: dict[str, dict[str, object]] = {}
    summary: dict[str, object] = {
        "schema_version": 1,
        "source": "AMI Meeting Corpus",
        "license": "CC-BY-4.0",
        "license_url": "https://groups.inf.ed.ac.uk/ami/corpus/",
        "split_policy": "meeting-series and speaker-group disjoint",
        "splits": split_summary,
    }
    for name, clips in splits.items():
        write_manifest(output / f"{name}.jsonl", clips, repo_root)
        split_summary[name] = {
            "clips": len(clips),
            "hours": round(sum(c.duration_seconds for c in clips) / 3600, 3),
            "meeting_series": sorted({c.series for c in clips}),
        }

    (output / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, wave.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
