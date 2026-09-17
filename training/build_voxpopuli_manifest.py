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
    args.workdir.mkdir(parents=True, exist_ok=True)

    table = pq.read_table(
        args.parquet, columns=["audio", "raw_text", "is_gold_transcript"])
    audio_col, text_col = table.column("audio"), table.column("raw_text")

    kept, attempted = 0, 0
    start = 0
    if args.out.exists():
        start = sum(1 for line in args.out.read_text(
            encoding="utf-8").splitlines() if line.strip())
        print(f"resuming after {start} completed rows", file=sys.stderr)
    with args.out.open("a", encoding="utf-8", buffering=1) as out:
        for i in range(start, min(args.limit, table.num_rows)):
            audio = audio_col[i].as_py()
            reference = text_col[i].as_py().strip()
            attempted += 1

            raw_path = audio.get("path") or "clip.ogg"
            ext = Path(raw_path).suffix.lstrip(".") or "ogg"
            src = args.workdir / f"clip_{i}.{ext}"
            src.write_bytes(audio["bytes"])
            wav = to_wav(src, src, args.workdir)
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
