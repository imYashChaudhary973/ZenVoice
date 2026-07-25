#!/usr/bin/env python3
"""Builds real-speech corpora for ZenVoiceAccuracyChecks from LibriSpeech.

The harness shipped with synthesized fixtures, which are reproducible and
free but are not people: `say` does not hesitate, breathe, or sit in a room.
This turns a published corpus of real recordings into the wav+txt pairs
ZENVOICE_ACCURACY_CORPUS expects.

    python3 Scripts/build-librispeech-corpus.py --output ~/zenvoice-corpora

Downloads mini LibriSpeech dev-clean-2 (126 MB, CC BY 4.0) unless it is
already present. Audio is deliberately never committed: it is someone else's
recordings, and the harness only needs it locally.

Two sets are produced:

  single/      one utterance per speaker — baseline accuracy on real voices
  dictation/   four consecutive utterances joined by silence — the
               multi-sentence shape a real dictation has, and the only one
               that makes live segmentation fire
"""

import argparse
import collections
import glob
import os
import struct
import subprocess
import sys
import urllib.request
import tarfile
import wave

ARCHIVE_URL = "https://www.openslr.org/resources/31/dev-clean-2.tar.gz"
SAMPLE_RATE = 16_000
PAUSE_SECONDS = 1.2
UTTERANCES_PER_DICTATION = 4


def to_wav(source: str, destination: str) -> None:
    """FLAC to 16 kHz mono WAV, using the converter macOS already ships."""
    subprocess.run(
        [
            "afconvert", "-f", "WAVE", "-d", f"LEI16@{SAMPLE_RATE}",
            "-c", "1", source, destination,
        ],
        check=True,
        capture_output=True,
    )


def pcm(path: str) -> bytes:
    """Reads the data chunk directly.

    afconvert writes WAVE_FORMAT_EXTENSIBLE, which Python's wave module
    refuses even though the samples inside are ordinary 16-bit mono.
    """
    raw = open(path, "rb").read()
    if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise ValueError(f"{path} is not a RIFF/WAVE file")
    offset = 12
    while offset < len(raw) - 8:
        chunk = raw[offset:offset + 4]
        size = struct.unpack("<I", raw[offset + 4:offset + 8])[0]
        if chunk == b"data":
            return raw[offset + 8:offset + 8 + size]
        offset += 8 + size + (size & 1)
    raise ValueError(f"{path} has no data chunk")


def write_wav(path: str, frames: bytes) -> None:
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(frames)


def fetch(destination: str) -> str:
    root = os.path.join(destination, "LibriSpeech", "dev-clean-2")
    if os.path.isdir(root):
        return root
    archive = os.path.join(destination, "dev-clean-2.tar.gz")
    if not os.path.exists(archive):
        print(f"downloading {ARCHIVE_URL} …")
        urllib.request.urlretrieve(ARCHIVE_URL, archive)
    print("extracting …")
    with tarfile.open(archive) as handle:
        handle.extractall(destination)
    return root


def utterances(root: str) -> dict:
    found = collections.defaultdict(list)
    for transcript in glob.glob(f"{root}/*/*/*.trans.txt"):
        directory = os.path.dirname(transcript)
        for line in open(transcript):
            identifier, text = line.strip().split(" ", 1)
            audio = os.path.join(directory, identifier + ".flac")
            if os.path.exists(audio):
                found[identifier.split("-")[0]].append((audio, text.strip()))
    return {speaker: sorted(items) for speaker, items in found.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--dictations", type=int, default=8)
    arguments = parser.parse_args()

    os.makedirs(arguments.output, exist_ok=True)
    root = fetch(arguments.output)
    speakers = utterances(root)
    print(f"{len(speakers)} speakers")

    single = os.path.join(arguments.output, "single")
    dictation = os.path.join(arguments.output, "dictation")
    os.makedirs(single, exist_ok=True)
    os.makedirs(dictation, exist_ok=True)

    for index, speaker in enumerate(sorted(speakers)):
        audio, text = speakers[speaker][0]
        target = os.path.join(single, f"{speaker}-{index:02d}.wav")
        to_wav(audio, target)
        open(target[:-4] + ".txt", "w").write(text + "\n")
    print(f"single: {len(glob.glob(single + '/*.wav'))}")

    silence = b"\x00\x00" * int(SAMPLE_RATE * PAUSE_SECONDS)
    made = 0
    for speaker in sorted(speakers):
        items = speakers[speaker]
        if len(items) < UTTERANCES_PER_DICTATION:
            continue
        frames, texts = [], []
        for position, (audio, text) in enumerate(
            items[:UTTERANCES_PER_DICTATION]
        ):
            scratch = os.path.join(arguments.output, f"_join{position}.wav")
            to_wav(audio, scratch)
            frames.append(pcm(scratch))
            texts.append(text)
            os.remove(scratch)
        target = os.path.join(dictation, f"{speaker}.wav")
        write_wav(target, silence.join(frames))
        open(target[:-4] + ".txt", "w").write(" ".join(texts) + "\n")
        made += 1
        if made >= arguments.dictations:
            break
    print(f"dictation: {made}")
    print()
    print(f"ZENVOICE_ACCURACY_CORPUS={single} swift run ZenVoiceAccuracyChecks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
