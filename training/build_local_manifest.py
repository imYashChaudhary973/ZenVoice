#!/usr/bin/env python3
"""Decode locally-held dictation corpora into real-ASR-pairs manifests.

Sources (all already on this Mac, none leave it):
  --consented   consented-dictation manifests (JSONL rows with "audio" and
                "text"; license private-consent-local-only)
  --ami         dictation-ami dirs of .wav + .txt sidecar pairs

Every clip is decoded with the production whisper.cpp path (see decode.py)
and emitted as {"raw", "reference"} rows for build_real_pairs.py.

Usage:
    python3 build_local_manifest.py \
      --model /Datasets/whisper/ggml-large-v3-turbo.bin \
      --consented ../Datasets/consented-dictation/manifests/*.jsonl \
      --ami ../Datasets/dictation-ami-train \
      --out ../Datasets/real_manifest.jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from decode import FFMPEG, to_wav, transcribe


def consented_rows(manifests: list[Path]) -> list[tuple[Path, str]]:
    rows: list[tuple[Path, str]] = []
    for manifest in manifests:
        repo_root = Path.cwd().parent
        for line in manifest.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            item = json.loads(line)
            audio = Path(item["audio"])
            if not audio.is_absolute() and not audio.exists():
                audio = repo_root / audio
            rows.append((audio, item["text"].strip()))
    return rows


def ami_rows(directory: Path) -> list[tuple[Path, str]]:
    rows: list[tuple[Path, str]] = []
    for wav in sorted(directory.glob("*.wav")):
        text = wav.with_suffix(".txt")
        if text.exists():
            rows.append((wav, " ".join(
                text.read_text(encoding="utf-8").split()).strip()))
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--consented", nargs="*", type=Path, default=[])
    parser.add_argument("--ami", nargs="*", type=Path, default=[])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--workdir", type=Path,
                        default=Path("/tmp/zv_local_decode"))
    parser.add_argument("--limit", type=int, default=0,
                        help="stop after N kept rows (0 = all)")
    parser.add_argument("--start", type=int, default=0,
                        help="skip the first N source pairs (for sharding)")
    args = parser.parse_args()

    pairs = consented_rows(args.consented) + sum(
        (ami_rows(directory) for directory in args.ami), [])
    print(f"{len(pairs)} audio/reference pairs to decode", file=sys.stderr)
    if not args.model.exists():
        sys.exit(f"whisper model missing: {args.model}")
    args.workdir.mkdir(parents=True, exist_ok=True)

    pairs = pairs[args.start:]

    # Resume from the last ATTEMPTED source index, not the output line count:
    # failed pairs write no row, so a line-count resume re-runs rows and
    # duplicates examples. Falls back to the legacy line count when no
    # checkpoint exists.
    checkpoint_path = args.out.with_suffix(args.out.suffix + ".checkpoint")
    start = 0
    if checkpoint_path.exists():
        try:
            # One {"next_index": N} line per attempted pair; resume from the
            # last line so a mid-write crash can't corrupt earlier entries.
            lines = [line for line in
                     checkpoint_path.read_text(encoding="utf-8").splitlines()
                     if line.strip()]
            start = json.loads(lines[-1])["next_index"] if lines else 0
            print(f"resuming at source index {start}", file=sys.stderr)
        except (ValueError, KeyError):
            start = 0
    elif args.out.exists():
        start = sum(1 for line in args.out.read_text(
            encoding="utf-8").splitlines() if line.strip())
        print(f"resuming after {start} completed rows (line-count fallback)",
              file=sys.stderr)
    pairs = pairs[start:]

    kept, failed = 0, 0
    with args.out.open("a", encoding="utf-8", buffering=1) as out, \
            checkpoint_path.open("w", encoding="utf-8") as checkpoint:
        for index, (audio, reference) in enumerate(pairs):
            checkpoint.write(json.dumps({"next_index": start + index + 1}) + "\n")
            checkpoint.flush()
            wav = to_wav(audio, audio, args.workdir)
            if wav is None:
                failed += 1
                continue
            raw = transcribe(str(args.model), wav)
            wav.unlink(missing_ok=True)
            if not raw or not reference:
                failed += 1
                continue
            out.write(json.dumps(
                {"raw": raw, "reference": reference, "app": None},
                ensure_ascii=False) + "\n")
            kept += 1
            if kept % 100 == 0:
                print(f"{kept} decoded", file=sys.stderr)
            if args.limit and kept >= args.limit:
                break

    print(f"kept {kept}, failed {failed} -> {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
