#!/usr/bin/env python3
"""Build chat-format training pairs from a clean text corpus.

Input: one or more .txt files of plain prose (a sentence per line works, or
paragraphs -- sentences are split automatically). Output: train.jsonl,
valid.jsonl, and eval.jsonl in --out. The eval split is frozen by --seed;
regenerate the whole directory with the same seed to reproduce it.

Sources for the corpus (license matters for a shipped Apache-2.0 model):
prefer CC0/public-domain text (e.g. Common Voice CC0 transcripts, OANC).
Avoid CC BY-SA sources (Wikipedia) for weights you plan to ship.

Usage:
    python3 build_synthetic.py --seed 7 --corpus data/sample_corpus.txt --out data
"""

from __future__ import annotations

import argparse
import json
import random
import re
from pathlib import Path

from common import APPS, chat_row
from noisifier import Noisifier

SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")
WORD_COUNT = re.compile(r"[\w']+")


def sentences_from_corpus(paths: list[Path]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for path in paths:
        for paragraph in path.read_text(encoding="utf-8").splitlines():
            for raw in SENTENCE_SPLIT.split(paragraph.strip()):
                sentence = re.sub(r"\s+", " ", raw).strip()
                words = WORD_COUNT.findall(sentence)
                if not (2 <= len(words) <= 40):
                    continue
                key = sentence.casefold()
                if key in seen:
                    continue
                seen.add(key)
                result.append(sentence)
    return result


def build_split(rows: list[str], seed: int, rng: random.Random) -> list[dict]:
    out = []
    for index, target in enumerate(rows):
        noisy = Noisifier(seed=seed * 1_000_003 + index).degrade(target)
        if not noisy:
            continue
        app = rng.choice(APPS) if rng.random() < 0.6 else None
        out.append(chat_row(noisy, target, app))
    return out


def write_jsonl(path: Path, rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", nargs="+", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=Path("data"))
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--valid-frac", type=float, default=0.01)
    parser.add_argument("--eval-frac", type=float, default=0.01)
    args = parser.parse_args()

    for name, frac in (("--valid-frac", args.valid_frac),
                       ("--eval-frac", args.eval_frac)):
        if not 0.0 <= frac < 1.0:
            parser.error(f"{name} must be in [0, 1), got {frac}")
    if args.valid_frac + args.eval_frac >= 1.0:
        parser.error("--valid-frac + --eval-frac must be < 1.0, got "
                     f"{args.valid_frac + args.eval_frac}")

    all_sentences = sentences_from_corpus(args.corpus)
    if len(all_sentences) < 500:
        print(f"warning: only {len(all_sentences)} sentences; "
              "a real fine-tune wants 50k+. Sample corpus is for smoke runs.")

    rng = random.Random(args.seed)
    rng.shuffle(all_sentences)

    eval_count = max(1, int(len(all_sentences) * args.eval_frac))
    valid_count = max(1, int(len(all_sentences) * args.valid_frac))
    eval_rows = all_sentences[:eval_count]
    valid_rows = all_sentences[eval_count:eval_count + valid_count]
    train_rows = all_sentences[eval_count + valid_count:]

    args.out.mkdir(parents=True, exist_ok=True)
    for name, sentences in (
        ("synthetic_train", train_rows),
        ("synthetic_valid", valid_rows),
        ("eval", eval_rows),
    ):
        rows = build_split(sentences, args.seed, rng)
        write_jsonl(args.out / f"{name}.jsonl", rows)
        print(f"{name}.jsonl: {len(rows)} pairs")


if __name__ == "__main__":
    main()
