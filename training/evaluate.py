#!/usr/bin/env python3
"""Score formatting hypotheses against the frozen eval set.

Word-only alignment drives wer/new_content_rate; a token-level alignment
serves the punctuation and case metrics:
  - wer                  word error rate vs reference (the no-regression gate)
  - exact_match          casefolded whole-string equality rate
  - punct_precision/recall/f1   punctuation mark recovery
  - capitalization_accuracy     matched words with identical case
  - sentence_start_accuracy     capitalization of the first word
  - new_content_rate     inserted words per reference word (hallucination proxy)

Usage:
    python3 evaluate.py --self
    python3 evaluate.py --eval data/eval.jsonl --floor          # unformatted input baseline
    python3 evaluate.py --eval data/eval.jsonl --pred hyps.txt  # one hypothesis per line
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from common import APPS

TOKEN = re.compile(r"[\w']+|[^\w\s]")
WORD = re.compile(r"^[\w']+$")

# ops: (op, ref_token_or_None, hyp_token_or_None)
def align(ref: list[str], hyp: list[str]) -> list[tuple[str, str | None, str | None]]:
    n, m = len(ref), len(hyp)
    table = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        table[i][0] = i
    for j in range(m + 1):
        table[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            cost = 0 if ref[i - 1].casefold() == hyp[j - 1].casefold() else 1
            table[i][j] = min(
                table[i - 1][j] + 1,
                table[i][j - 1] + 1,
                table[i - 1][j - 1] + cost,
            )

    ops: list[tuple[str, str | None, str | None]] = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and table[i][j] == table[i - 1][j - 1] + (
            0 if ref[i - 1].casefold() == hyp[j - 1].casefold() else 1
        ):
            ops.append(("match" if ref[i - 1].casefold() == hyp[j - 1].casefold() else "sub",
                        ref[i - 1], hyp[j - 1]))
            i, j = i - 1, j - 1
        elif i > 0 and table[i][j] == table[i - 1][j] + 1:
            ops.append(("del", ref[i - 1], None))
            i -= 1
        else:
            ops.append(("ins", None, hyp[j - 1]))
            j -= 1
    ops.reverse()
    return ops


def score(reference: str, hypothesis: str) -> dict:
    ref_tokens, hyp_tokens = TOKEN.findall(reference), TOKEN.findall(hypothesis)
    ops = align(ref_tokens, hyp_tokens)

    # Word-only alignment drives WER and inserted-word metrics; the token
    # alignment above stays for punctuation and case metrics.
    ref_words = [t for t in ref_tokens if WORD.match(t)]
    hyp_words = [t for t in hyp_tokens if WORD.match(t)]
    subs = dels = inss = 0
    for op, _, _ in align(ref_words, hyp_words):
        if op == "sub":
            subs += 1
        elif op == "del":
            dels += 1
        elif op == "ins":
            inss += 1
    ref_word_count = max(len(ref_words), 1)

    matched = [(r, h) for op, r, h in ops if op == "match"]
    matched_words = [(r, h) for r, h in matched if WORD.match(r)]
    same_case = sum(1 for r, h in matched_words if r == h)

    punct_matched = sum(1 for r, h in matched if not WORD.match(r))
    punct_subs = sum(1 for op, r, h in ops
                     if op == "sub" and not WORD.match(r) and not WORD.match(h))
    punct_missed = (sum(1 for op, r, _ in ops if op == "del" and not WORD.match(r))
                    + punct_subs)
    punct_false = (sum(1 for op, _, h in ops if op == "ins" and not WORD.match(h))
                   + punct_subs)
    punct_recall = punct_matched / max(punct_matched + punct_missed, 1)
    punct_precision = punct_matched / max(punct_matched + punct_false, 1)
    punct_f1 = (2 * punct_precision * punct_recall
                / max(punct_precision + punct_recall, 1e-9))

    starts = starts_ok = 0
    at_sentence_start = True
    for op, r, h in ops:
        if r is not None and not WORD.match(r):
            # A terminal punctuation mark ends the current sentence; the
            # next reference word starts a new one. Abbreviations like
            # "U.S." add spurious boundaries — accepted noise for a cheap
            # per-sentence metric.
            if r in {".", "!", "?"}:
                at_sentence_start = True
            continue
        if op in ("match", "sub", "del") and r is not None and WORD.match(r):
            if at_sentence_start:
                starts += 1
                starts_ok += 1 if (op == "match" and r == h) else 0
                at_sentence_start = False

    return {
        "wer": (subs + dels + inss) / ref_word_count,
        "exact_match": 1.0 if reference.casefold() == hypothesis.casefold() else 0.0,
        "punct_precision": punct_precision,
        "punct_recall": punct_recall,
        "punct_f1": punct_f1,
        "capitalization_accuracy": same_case / max(len(matched_words), 1),
        "sentence_start_accuracy": starts_ok / max(starts, 1),
        "new_content_rate": inss / ref_word_count,
        # not a metric: per-row reference word count, used by --weighted
        "ref_words": float(len(ref_words)),
    }


def aggregate(rows: list[dict]) -> dict:
    totals: dict[str, float] = {}
    counts: dict[str, float] = {}
    for row in rows:
        for key, value in row.items():
            totals[key] = totals.get(key, 0.0) + value
            counts[key] = counts.get(key, 0) + 1
    return {key: totals[key] / counts[key] for key in totals}


def noisy_from_row(row: dict) -> str:
    user = next(m["content"] for m in row["messages"] if m["role"] == "user")
    # chat_row prefixes "app: <name>\n" only when an app context was set.
    # A genuine dictation can also start with "app: ", so only strip when
    # the prefix names one of the known context apps (APPS is the sole
    # source chat_row ever used).
    first, _, rest = user.partition("\n")
    if first.startswith("app: ") and first[5:] in APPS:
        return rest
    return user


def reference_from_row(row: dict) -> str:
    return row["messages"][-1]["content"]


def _self_check() -> None:
    s = score("Hello, world.", "hello world")
    assert s["wer"] == 0.0, s
    assert s["punct_f1"] == 0.0 and s["capitalization_accuracy"] == 0.5, s

    s = score("Say hello", "Say hello everyone")
    assert s["new_content_rate"] == 1 / 2, s
    assert s["wer"] == 0.5, s

    s = score("The build passed.", "the build failed today")
    assert s["wer"] == 2 / 3, s  # failed sub + today ins over 3 words
    assert s["new_content_rate"] == 1 / 3, s

    s = score("Nineteen ninety four was warm", "1994 was warm")
    assert s["wer"] > 0, s  # ITN mismatch counts as errors, as it should

    agg = aggregate([score("Hello, world.", "Hello, world."),
                     score("a b c", "a b")])
    assert 0 < agg["wer"] < 1, agg

    # --weighted: word-weighted WER must sit below the macro average when a
    # short bad row would otherwise dominate
    long_row = score("one two three four five six",
                     "one two three four five six seven")  # wer 1/6
    short_row = score("a b", "x y")  # wer 1.0
    weighted = ((long_row["wer"] * long_row["ref_words"]
                 + short_row["wer"] * short_row["ref_words"])
                / (long_row["ref_words"] + short_row["ref_words"]))
    assert weighted < aggregate([long_row, short_row])["wer"]
    print("evaluate self-check OK")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--eval", type=Path, default=None)
    parser.add_argument("--pred", type=Path, default=None)
    parser.add_argument("--weighted", action="store_true",
                        help="word-weight WER (long rows count proportionally) "
                             "instead of the default macro-average")
    parser.add_argument("--floor", action="store_true",
                        help="score the raw noisy input itself (no-model baseline)")
    parser.add_argument("--json-out", type=Path, default=None)
    parser.add_argument("--max-wer", type=float, default=None,
                        help="exit 1 if aggregate WER exceeds this gate")
    parser.add_argument("--limit", type=int, default=0,
                        help="score only the first N eval rows (must match pred)")
    parser.add_argument("--self", action="store_true")
    args = parser.parse_args()

    if args.self:
        _self_check()
        sys.exit(0)

    if not args.eval or (not args.pred and not args.floor):
        parser.error("need --eval with either --pred or --floor")

    rows = [json.loads(line) for line in
            args.eval.read_text(encoding="utf-8").splitlines() if line.strip()]
    if args.limit:
        rows = rows[:args.limit]

    hypotheses: list[str]
    if args.floor:
        hypotheses = [noisy_from_row(row) for row in rows]
    else:
        hypotheses = args.pred.read_text(encoding="utf-8").splitlines()
        if len(hypotheses) != len(rows):
            sys.exit(f"pred has {len(hypotheses)} lines, eval has {len(rows)}")

    per_row = [score(reference_from_row(row), hyp)
               for row, hyp in zip(rows, hypotheses)]
    summary = aggregate(per_row)
    if args.weighted:
        # word-weighted: each row contributes proportionally to its length,
        # so a 3-word row can't dominate a 60-word one
        total_words = sum(r["ref_words"] for r in per_row)
        summary["wer"] = (sum(r["wer"] * r["ref_words"] for r in per_row)
                          / total_words)
    summary.pop("ref_words")  # row-size bookkeeping, not a metric

    print(f"{'metric':28s} value")
    for key, value in summary.items():
        print(f"{key:28s} {value:.4f}")

    if args.json_out:
        args.json_out.write_text(json.dumps(summary, indent=2) + "\n",
                                 encoding="utf-8")
    if args.max_wer is not None and summary["wer"] > args.max_wer:
        sys.exit(f"WER gate failed: {summary['wer']:.4f} > {args.max_wer}")


if __name__ == "__main__":
    main()
