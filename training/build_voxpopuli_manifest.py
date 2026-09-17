#!/usr/bin/env python3
"""Decode audio from a VoxPopuli parquet shard with the local whisper.cpp CLI
and emit a real-ASR-pairs manifest for build_real_pairs.py.

VoxPopuli is CC0 and its transcripts keep punctuation and casing, so pairing
whisper's raw output against them trains on true ASR error distribution.
Everything runs on this Mac; audio and transcripts never leave it.

Requires: pyarrow, ffmpeg (PATH), whisper-cli (PATH), a ggml whisper model.

Usage:
    python3 build_voxpopuli_manifest.py \
      --parquet /Datasets/voxpopuli_en_test.parquet \
      --model /Datasets/whisper/ggml-large-v3-turbo.bin \
      --limit 400 --out /Datasets/voxpopuli_manifest.jsonl
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from decode import to_wav, transcribe


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parquet", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=400)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, default=Path("/tmp/zv_voxpopuli"))
    args = parser.parse_args()

    import pyarrow.parquet as pq

    if not args.model.exists():
        sys.exit(f"whisper model missing: {args.model}")
    if args.workdir.is_symlink():
        sys.exit(f"workdir is a symlink: {args.workdir}")
    # Restrictive mode: a predictable /tmp dir must not be writable by other
    # local users, or they can pre-plant symlinked clip paths.
    args.workdir.mkdir(parents=True, exist_ok=True, mode=0o700)

    parquet = pq.ParquetFile(args.parquet)
    total = parquet.metadata.num_rows

    kept, attempted = 0, 0
    # Resume from the last ATTEMPTED source index, not the output line count:
    # failed rows write nothing, so a line-count resume duplicates pairs.
    checkpoint_path = args.out.with_suffix(args.out.suffix + ".checkpoint")
    start = 0
    if checkpoint_path.exists():
        # One {"next_index": N} line per attempted row. Tolerate a torn
        # final line from a kill mid-write: walk back to the last parseable
        # entry instead of resetting the whole run.
        for line in reversed(checkpoint_path.read_text(
                encoding="utf-8").splitlines()):
            if not line.strip():
                continue
            try:
                start = json.loads(line)["next_index"]
                break
            except (ValueError, KeyError):
                continue
        print(f"resuming at source index {start}", file=sys.stderr)
    elif args.out.exists():
        lines = args.out.read_text(encoding="utf-8").splitlines()
        good = 0
        while good < len(lines):
            try:
                json.loads(lines[good])
            except ValueError:
                break
            good += 1
        if good < len(lines):
            # torn trailing row (killed mid-write): drop the tail so the
            # appended rows don't glue onto the half-written line
            print(f"dropping {len(lines) - good} torn trailing row(s)",
                  file=sys.stderr)
            args.out.write_text("".join(line + "\n" for line in lines[:good]))
        start = good
        print(f"resuming after {start} completed rows (line-count fallback)",
              file=sys.stderr)

    limit = min(args.limit, total)
    # Stream in batches: a whole shard can be far larger than RAM.
    with args.out.open("a", encoding="utf-8", buffering=1) as out, \
            checkpoint_path.open("w", encoding="utf-8") as checkpoint:
        i = 0
        for batch in parquet.iter_batches(batch_size=256,
                                          columns=["audio", "raw_text"]):
            if i >= limit:
                break
            for j in range(batch.num_rows):
                if i >= limit:
                    break
                i += 1
                if i <= start:
                    continue
                audio = batch.column("audio")[j].as_py()
                reference = batch.column("raw_text")[j].as_py()
                # Null audio/text rows are skippable data, not a crash.
                if not audio or not audio.get("bytes") or not reference:
                    continue
                checkpoint.write(json.dumps({"next_index": i}) + "\n")
                checkpoint.flush()
                reference = reference.strip()
                attempted += 1

                raw_path = audio.get("path") or "clip.ogg"
                ext = Path(raw_path).suffix.lstrip(".") or "ogg"
                src = args.workdir / f"clip_{i}.{ext}"
                # O_EXCL: never follow a pre-planted symlink at this path.
                try:
                    fd = os.open(src, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                except FileExistsError:
                    src.unlink()
                    fd = os.open(src, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "wb") as handle:
                    handle.write(audio["bytes"])
                wav = to_wav(src, args.workdir)
                src.unlink(missing_ok=True)
                if wav is None:
                    continue

                raw = transcribe(str(args.model), wav)
                wav.unlink(missing_ok=True)
                if not raw:
                    continue

                out.write(json.dumps(
                    {"raw": raw, "reference": reference, "app": None},
                    ensure_ascii=False,
                ) + "\n")
                kept += 1
                if kept % 25 == 0:
                    print(f"{kept} pairs decoded", file=sys.stderr)

    print(f"attempted {attempted}, kept {kept} -> {args.out}")


if __name__ == "__main__":
    main()
