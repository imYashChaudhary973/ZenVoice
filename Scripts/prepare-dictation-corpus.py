#!/usr/bin/env python3
"""Prepare a real-dictation evaluation corpus for ZenVoiceAccuracyChecks.

Synthetic fixtures are reproducible and free, but they are not people: a
synthesiser does not hesitate, breathe, change its mind, or sit in a room.
This script sets up a licence-clean corpus of *actual* spontaneous speech
that can be fed to the accuracy harness.

The corpus is deliberately self-recorded rather than scraped, so provenance
and licensing are unambiguous. The resulting audio + transcript pairs live
under Datasets/dictation/ (gitignored) and are consumed with:

    ZENVOICE_ACCURACY_CORPUS=Datasets/dictation \
    ZENVOICE_ACCURACY_MULTIENGINE=1 \
    swift run ZenVoiceAccuracyChecks

The harness will report whole / segmented word error rate and, when
ZENVOICE_ACCURACY_MULTIENGINE is set, per-engine WER on the same recordings.
"""

import argparse
import os
import sys
from pathlib import Path

PROMPTS = [
    # Technical vocabulary and proper nouns.
    "Please refactor the authentication middleware so it validates the bearer token before it queries the Postgres replica, and returns unauthorized instead of a server error.",
    # Multi-sentence, natural pauses.
    "The Kubernetes cluster is throttling because the sidecar proxy keeps retrying idempotent requests against a stale endpoint slice in the staging namespace.",
    # Hesitations and self-corrections — real dictation shape.
    "Um, I think we should, um, ship the beta on Thursday only if the crash rate stays low and, uh, the onboarding flow is fully localized.",
    # Spoken restart.
    "Create a login page, no wait, a sign-up page using SwiftUI and the new validation rules.",
    # Numbers and negation.
    "Do not merge the branch until the tests pass. Increase the request timeout to thirty seconds.",
    # Casual message with filler words.
    "Hey, you know, I just wanted to check if the API returns a cached response, like, when the token is valid.",
    # Code review with technical terms.
    "I asked Priya to review the pull request but she said the migration script drops the index before the backfill completes, which would lock the whole table.",
    # Stand-up style short update.
    "Yesterday I fixed the waveform normalisation bug and today I am wiring the cloud provider picker into the formatting screen.",
    # Mixed case and punctuation.
    "Ship the beta on Thursday only if the crash rate stays low and the onboarding flow is fully localized for Hindi, Tamil, and Marathi speakers.",
    # Dictated email opening.
    "Hi team, quick update, we have cut word error rate on disfluent speech from twenty three percent to under eight percent.",
]

README = """# Real-Dictation Evaluation Corpus

This directory contains licence-clean self-recorded audio used to measure
ZenVoice accuracy on spontaneous speech.

## Recording

1. Record yourself reading each prompt naturally — do not rehearse into a
   monotone delivery. Hesitate, breathe, and self-correct exactly as you would
   when dictating to an app.
2. Export each recording as a 16-bit mono WAV or M4A file at any standard
   sample rate (the harness resamples to 16 kHz mono float32).
3. Name the audio file `01.wav`, `02.wav`, … matching the prompt number.
4. Save the exact text you intended as `01.txt`, `02.txt`, … in the same
   folder. Do not edit the prompt to match what you actually said; the whole
   point is to measure the gap between intended and transcribed text.

## Optional: multi-clip dictations

For recordings that mimic a long dictation with natural pauses, create a
`.list` file instead of a single audio file:

    pause_seconds=1.2
    01.wav
    02.wav

and a same-name `.txt` with the combined reference transcript.

## Running the harness

    ZENVOICE_ACCURACY_CORPUS=Datasets/dictation \
    ZENVOICE_ACCURACY_MULTIENGINE=1 \
    swift run ZenVoiceAccuracyChecks

The harness reports whole / segmented WER for the configured Whisper model and
per-engine WER for every installed engine.

## Licence

Recordings you make yourself are your own work. By contributing them to this
local corpus you agree they are used only for measuring ZenVoice accuracy on
this Mac. They are never sent anywhere.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default="Datasets/dictation",
        help="directory to create (default: Datasets/dictation)",
    )
    args = parser.parse_args()

    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)

    prompts_path = output / "prompts.txt"
    prompts_path.write_text("\n\n".join(PROMPTS) + "\n", encoding="utf-8")

    readme_path = output / "README.md"
    readme_path.write_text(README, encoding="utf-8")

    for index, prompt in enumerate(PROMPTS, start=1):
        reference = output / f"{index:02d}.txt"
        if not reference.exists():
            reference.write_text(prompt + "\n", encoding="utf-8")

    print(f"Created real-dictation corpus layout at {output.resolve()}")
    print(f"  prompts:  {prompts_path}")
    print(f"  guide:    {readme_path}")
    print(f"  references: {len(PROMPTS)} placeholder .txt files")
    print()
    print("Next steps:")
    print("1. Record yourself reading each prompt naturally.")
    print("2. Save audio as 01.wav, 02.wav, … alongside the .txt files.")
    print("3. Update each .txt to the exact text you intended.")
    print("4. Run: ZENVOICE_ACCURACY_CORPUS=Datasets/dictation \\")
    print("       ZENVOICE_ACCURACY_MULTIENGINE=1 \\")
    print("       swift run ZenVoiceAccuracyChecks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
