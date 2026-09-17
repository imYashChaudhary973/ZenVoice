#!/usr/bin/env python3
"""Generate formatting hypotheses from any MLX chat model, for evaluate.py.

The baseline run: score the STOCK model with SYSTEM_PROMPT before any
fine-tuning. Same prompt the fine-tune will be trained on.

Usage:
    python3 baseline.py --model mlx-community/Qwen3-1.7B-4bit \
      --eval data/eval.jsonl --out hyps_stock.txt --limit 300
    python3 evaluate.py --eval data/eval.jsonl --pred hyps_stock.txt
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from common import SYSTEM_PROMPT
from evaluate import noisy_from_row


def strip_reasoning(text: str) -> str:
    """Qwen3-style <think> blocks are never part of the dictation output."""
    return re.sub(r"<think>.*?</think>\s*", "", text, flags=re.DOTALL).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True)
    parser.add_argument("--eval", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=300)
    parser.add_argument("--max-tokens", type=int, default=200)
    args = parser.parse_args()

    from mlx_lm import load, generate
    from mlx_lm.sample_utils import make_sampler

    model, tokenizer = load(args.model)
    sampler = make_sampler(temp=0.0)

    rows = [json.loads(line) for line in
            args.eval.read_text(encoding="utf-8").splitlines() if line.strip()]
    rows = rows[:args.limit]

    with args.out.open("w", encoding="utf-8") as out:
        for n, row in enumerate(rows):
            messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": noisy_from_row(row)},
            ]
            try:
                prompt = tokenizer.apply_chat_template(
                    messages, add_generation_prompt=True,
                    enable_thinking=False)
            except TypeError:  # templates without thinking support
                prompt = tokenizer.apply_chat_template(
                    messages, add_generation_prompt=True)
            text = generate(model, tokenizer, prompt=prompt,
                            max_tokens=args.max_tokens, sampler=sampler)
            # one line per row: evaluate.py maps predictions by line number
            out.write(" ".join(strip_reasoning(text).split()) + "\n")
            if (n + 1) % 25 == 0:
                print(f"{n + 1}/{len(rows)} generated", file=sys.stderr)

    print(f"{len(rows)} hypotheses -> {args.out}")


if __name__ == "__main__":
    main()
