"""Shared local audio decode: ffmpeg -> 16k mono wav -> whisper.cpp CLI.

Used by every real-pair manifest builder so raw-side transcripts all come
from the same decoder (ggml-large-v3-turbo, matching ZenVoice's Whisper
production path). Never touches the network.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

WHISPER_CLI = "whisper-cli"
FFMPEG = "ffmpeg"


def to_wav(src: Path, wav: Path, workdir: Path) -> Path | None:
    """Convert any audio to 16k mono wav. Returns wav path or None on failure.

    src inside workdir means it is already a wav-shaped temp file.
    """
    if src.suffix.lower() == ".wav":
        target = workdir / f"{src.stem}_16k.wav"
    else:
        target = workdir / f"{src.stem}.wav"
        src = src
    # ffmpeg -y would follow a pre-planted symlink at target; refuse instead.
    if target.is_symlink():
        return None
    result = subprocess.run(
        [FFMPEG, "-y", "-loglevel", "error", "-i", str(src),
         "-ar", "16000", "-ac", "1", str(target)],
        capture_output=True,
    )
    return target if result.returncode == 0 else None


def transcribe(model: str, wav: Path, timeout: int = 300) -> str:
    """Raw whisper.cpp transcript: no timestamps, no prints.

    A clip that exceeds the timeout returns "" so callers count it as a
    failed row instead of crashing.
    """
    try:
        result = subprocess.run(
            [WHISPER_CLI, "-m", model, "-f", str(wav), "-nt", "-np"],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return ""
    return " ".join(result.stdout.split()).strip()
