#!/usr/bin/env python3
"""Degrade clean text into raw-ASR-style input for enhancement-model training.

The noisifier approximates what Parakeet/Whisper emit: lowercase, no
punctuation, spoken forms of numbers/dates/money/URLs, fillers, false
restarts, and a few homophone confusions.

Usage:
    python3 noisifier.py --seed 7 < clean.txt > noisy.txt
    python3 noisifier.py --self
"""

from __future__ import annotations

import argparse
import random
import re
import sys

try:
    from num2words import num2words
except ImportError:
    sys.exit("noisifier.py needs num2words: python3 -m pip install num2words")

FILLERS = ["um", "uh", "like", "you know", "i mean", "sort of"]

# (correct, ASR-plausible confusion); applied to exact word matches only.
HOMOPHONES = [
    ("their", "there"), ("there", "their"),
    ("your", "you're"), ("you're", "your"),
    ("its", "it's"), ("it's", "its"),
    ("to", "too"), ("then", "than"),
    ("weather", "whether"), ("no", "know"),
]

CURRENCY = re.compile(r"\$\s?(\d{1,3}(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)")
PERCENT = re.compile(r"\b(\d+(?:\.\d+)?)\s?%")
TIME = re.compile(r"\b(\d{1,2}):(\d{2})\s?([ap])\.?\s?m?\.?", re.IGNORECASE)
EMAIL = re.compile(r"\b([\w.+-]+)@([\w-]+)\.([a-z]{2,})\b", re.IGNORECASE)
URL = re.compile(r"\b(?:https?://|www\.)([a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,})(/[^\s,;]*)?", re.IGNORECASE)
YEAR = re.compile(r"\b(1[89]\d{2}|20\d{2})\b(?!\s?%)")
ORDINAL = re.compile(r"\b(\d{1,2})(st|nd|rd|th)\b", re.IGNORECASE)
NUMBER = re.compile(r"\b\d+(?:\.\d+)?\b")

_MONTHS = (
    "january february march april may june july august september october "
    "november december"
).split()


def _spoken_number(value) -> str:
    text = str(value)
    return re.sub("-", " ", num2words(float(text) if "." in text else int(text)))


def _spoken_currency(m: re.Match) -> str:
    value = m.group(1).replace(",", "")
    words = num2words(float(value), to="currency", currency="USD", lang="en")
    return re.sub("-", " ", words.replace(", ", " and "))


def _spoken_year(m: re.Match) -> str:
    year = m.group(1)
    if year.startswith("20") and year.endswith("00"):  # 2000 -> "two thousand"
        return _spoken_number(year)
    first, second = year[:2], year[2:]
    if second == "00":  # 1800 -> "eighteen hundred"
        return f"{_spoken_number(first)} hundred"
    if int(second) < 10:  # 1905 -> "nineteen oh five"
        return f"{_spoken_number(first)} oh {_spoken_number(second)}"
    return f"{_spoken_number(first)} {_spoken_number(second)}"


def _spoken_time(m: re.Match) -> str:
    hour, minute, meridiem = int(m.group(1)), m.group(2), m.group(3)
    if minute == "00":
        minutes = ""
    elif int(minute) < 10:
        minutes = f" oh {_spoken_number(minute)}"
    else:
        minutes = f" {_spoken_number(minute)}"
    suffix = f" {meridiem.lower()}m" if meridiem else ""
    return f"{_spoken_number(hour)}{minutes}{suffix}"


def _spoken_url(m: re.Match) -> str:
    domain, path = m.group(1), m.group(2)
    parts = domain.replace(".", " dot ")
    if path and path != "/":
        segments = " slash ".join(s.strip("/") for s in path.split("/") if s)
        parts = f"{parts} slash {segments}"
    return parts


def spoken_forms(text: str) -> str:
    """Restore written forms to how a speaker would say them aloud."""
    text = CURRENCY.sub(_spoken_currency, text)
    text = PERCENT.sub(lambda m: _spoken_number(m.group(1)) + " percent", text)
    text = EMAIL.sub(lambda m: f"{m.group(1)} at {m.group(2)} dot {m.group(3)}", text)
    text = URL.sub(_spoken_url, text)
    text = TIME.sub(_spoken_time, text)
    text = YEAR.sub(_spoken_year, text)
    text = ORDINAL.sub(lambda m: re.sub("-", " ", num2words(int(m.group(1)), to="ordinal")), text)
    text = NUMBER.sub(lambda m: _spoken_number(m.group(0)), text)
    return text


class Noisifier:
    def __init__(
        self,
        seed: int = 0,
        fillers: bool = True,
        restarts: bool = True,
        homophones: bool = True,
    ):
        self.rng = random.Random(seed)
        self.fillers = fillers
        self.restarts = restarts
        self.homophones = homophones

    def degrade(self, sentence: str) -> str:
        try:
            text = spoken_forms(sentence).lower()
        except (ValueError, OverflowError, NotImplementedError):
            # num2words raises on absurd values (thousand-digit integers,
            # out-of-currency-range floats); skipping the sample beats
            # killing the whole synthetic-build run.
            return ""

        # ASR emits almost no punctuation; contractions keep their apostrophe.
        text = re.sub(r"[^a-z0-9'\s]", " ", text.replace("&", " and "))
        text = re.sub(r"\s+", " ", text).strip()

        words = text.split(" ") if text else []
        if not words:
            return ""

        if self.fillers and self.rng.random() < 0.12:
            words.insert(0, self.rng.choice(FILLERS))
        if self.fillers and len(words) > 4 and self.rng.random() < 0.10:
            words.insert(self.rng.randint(2, 4), self.rng.choice(FILLERS))
        if self.restarts and len(words) > 4 and self.rng.random() < 0.08:
            k = self.rng.randint(1, 3)
            words = words[:k] + words
        if self.homophones:
            lowered = {w.casefold() for w in words}
            swaps = [pair for pair in HOMOPHONES if pair[0] in lowered]
            for correct, confused in swaps:
                if self.rng.random() < 0.15:
                    words = [confused if w.casefold() == correct else w for w in words]

        return " ".join(words)


def _self_check() -> None:
    n = Noisifier(seed=1, fillers=False, restarts=False, homophones=False)
    out = n.degrade("I sent you $45.50 on March 5th, 2026 at 3:30 pm.")
    assert not any(ch.isdigit() for ch in out), out
    assert "$" not in out and "," not in out and "." not in out, out
    assert "dollars and fifty cents" in out, out
    assert "march fifth" in out and "twenty twenty six" in out, out
    assert "three thirty pm" in out, out

    out2 = n.degrade("Check https://github.com/zenvoice/app for the build.")
    assert "dot" in out2 and "slash" in out2 and "http" not in out2, out2

    plain = n.degrade("she walked home quietly")
    assert re.fullmatch(r"[a-z ]+", plain), plain

    assert Noisifier(seed=3).degrade("The invoice totals $1,250 today") == Noisifier(seed=3).degrade(
        "The invoice totals $1,250 today"
    ), "same seed must be deterministic"
    print("noisifier self-check OK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--no-fillers", action="store_true")
    parser.add_argument("--no-restarts", action="store_true")
    parser.add_argument("--no-homophones", action="store_true")
    parser.add_argument("--self", action="store_true", help="run built-in asserts")
    args = parser.parse_args()

    if args.self:
        _self_check()
        sys.exit(0)

    noisifier = Noisifier(
        seed=args.seed,
        fillers=not args.no_fillers,
        restarts=not args.no_restarts,
        homophones=not args.no_homophones,
    )
    for line in sys.stdin:
        line = line.strip()
        if line:
            print(noisifier.degrade(line))
