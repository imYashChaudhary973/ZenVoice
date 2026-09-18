"""Shared constants for ZenVoice enhancement-model training.

SYSTEM_PROMPT is the single source of truth. Training pairs are built with
it, so `ZenFineTunedLanguageModel` (Sources/ZenVoiceCore, phase 4) must send
this exact string at inference.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

SYSTEM_PROMPT = (
    "You clean up raw speech-to-text dictation. Fix punctuation and "
    "capitalization, remove filler words and false restarts, and restore the "
    "written forms of numbers, dates, times, money, URLs, and email "
    "addresses. Keep the speaker's meaning and wording. If an 'app:' line is "
    "given, match capitalization and tone to that context. Output only the "
    "cleaned text, with no commentary."
)

# Context targets used for context-aware capitalization training. Roughly
# mirrors the apps a dictation user actually types into.
APPS = [
    "Slack", "Notes", "Messages", "Mail", "Xcode", "Terminal", "Chrome",
    "Notion", "Bear", "Word", "Reminders", "Things",
]


def load_jsonl(path: Path) -> list[dict]:
    """Read a JSONL file, skipping malformed lines with a loud note.

    One bad line should never kill a long decode/training-data run; the
    file:line + excerpt pinpoints it without stopping the rest.
    """
    rows: list[dict] = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except ValueError as exc:
            print(f"{path}:{n}: bad JSON skipped ({exc}): {line[:80]!r}",
                  file=sys.stderr)
    return rows


def chat_row(noisy: str, clean: str, app: str | None) -> dict:
    """Build one mlx-lm chat-format training row."""
    text = f"app: {app}\n{noisy}" if app else noisy
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text},
            {"role": "assistant", "content": clean},
        ]
    }
