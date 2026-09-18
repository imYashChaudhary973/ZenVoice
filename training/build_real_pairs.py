#!/usr/bin/env python3
"""Turn decoded-ASR manifests into chat-format training pairs.

Real pairs train on the true error distribution of the production engines.
Workflow: fetch audio + human transcripts (Common Voice CC0, GigaSpeech
Apache-2.0, People's Speech CC-BY), decode the audio with a production
engine (e.g. ZenVoiceRuntimeChecks with ZENVOICE_MODEL_PATH, or any local
whisper.cpp CLI), then write one manifest row per clip:

    {"raw": "<engine output, unpunctuated>", "reference": "<human text>", "app": null}

Rows that are empty, absurdly long, or where raw vs reference WER is so high
the pair is probably misaligned are skipped with a count.

Usage:
    python3 build_real_pairs.py --manifest cv_pairs.jsonl --out data/real_train.jsonl
"""

from __future__ import annotations

import argparse
import json
import random
import re
import sys
from pathlib import Path

from common import APPS, chat_row, load_jsonl
from evaluate import score

MAX_WORDS = 80
MAX_PAIR_WER = 0.9

# The enhancement target must model the style we teach: punctuated, cased,
# fluent text. AMI-style disfluent transcripts point the objective backwards
# (they would teach removing punctuation and keeping fillers), so require at
# least one sentence mark in the reference.
CLEAN_TARGET = re.compile(r"[.,!?]")


def _digit_count(text: str) -> int:
    return len(re.findall(r"\d", text))


def rows_from_manifest(path: Path, rng: random.Random) -> list[dict]:
    kept, skipped = [], 0
    for item in load_jsonl(path):
        raw, reference = (item.get("raw") or "").strip(), (item.get("reference") or "").strip()
        if not raw or not reference or len(reference.split()) > MAX_WORDS:
            skipped += 1
            continue
        if score(reference, raw)["wer"] > MAX_PAIR_WER:
            skipped += 1
            continue
        if not CLEAN_TARGET.search(reference):
            skipped += 1
            continue
        # ASR already wrote digits where the reference kept number words:
        # pairing these would train reverse-ITN (written -> spoken).
        if _digit_count(raw) > _digit_count(reference) + 1:
            skipped += 1
            continue
        app = item.get("app") or (rng.choice(APPS) if rng.random() < 0.6 else None)
        kept.append(chat_row(raw, reference, app))
    print(f"kept {len(kept)}, skipped {skipped}", file=sys.stderr)
    return kept


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--valid-out", type=Path, default=None,
                        help="hold out this fraction as real validation rows")
    parser.add_argument("--valid-frac", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    if not 0.0 <= args.valid_frac < 1.0:
        parser.error(f"--valid-frac must be in [0, 1), got {args.valid_frac}")

    rows = rows_from_manifest(args.manifest, random.Random(args.seed))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    split = int(len(rows) * (1 - args.valid_frac)) if args.valid_out else len(rows)
    subsets = [(args.out, rows[:split])]
    if args.valid_out:
        subsets.append((args.valid_out, rows[split:]))
    for path, subset in subsets:
        with path.open("w", encoding="utf-8") as handle:
            for row in subset:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
