#!/usr/bin/env python3
"""Builds real-speech corpora for ZenVoiceAccuracyChecks from LibriSpeech.

The harness shipped with synthesized fixtures, which are reproducible and
free but are not people: `say` does not hesitate, breathe, or sit in a room.
This turns a published corpus of real recordings into the audio+txt pairs
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
import hashlib
import os
import shutil
import sys
import urllib.request
import tarfile

ARCHIVE_URL = "https://www.openslr.org/resources/31/dev-clean-2.tar.gz"
ARCHIVE_SHA256 = (
    "176ec501490eced2d6c1f89f4f0ddc7dfe799e649e5322f8ba49fe3ff50c8012"
)
PAUSE_SECONDS = 1.2
UTTERANCES_PER_DICTATION = 4


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extract_safely(archive_path: str, destination: str) -> None:
    root = os.path.realpath(destination) + os.sep
    with tarfile.open(archive_path) as handle:
        members = handle.getmembers()
        for member in members:
            target = os.path.realpath(os.path.join(destination, member.name))
            if not target.startswith(root):
                raise ValueError(
                    f"archive member escapes destination: {member.name}"
                )
            if member.issym() or member.islnk():
                raise ValueError(
                    f"archive contains an unsupported link: {member.name}"
                )
        handle.extractall(destination, members=members)


def fetch(destination: str) -> str:
    root = os.path.join(destination, "LibriSpeech", "dev-clean-2")
    archive = os.path.join(destination, "dev-clean-2.tar.gz")
    if not os.path.exists(archive):
        print(f"downloading {ARCHIVE_URL} …")
        partial = archive + ".download"
        try:
            urllib.request.urlretrieve(ARCHIVE_URL, partial)
            if sha256(partial) != ARCHIVE_SHA256:
                raise ValueError("downloaded LibriSpeech archive failed SHA-256")
            os.replace(partial, archive)
        finally:
            if os.path.exists(partial):
                os.remove(partial)
    elif sha256(archive) != ARCHIVE_SHA256:
        raise ValueError("cached LibriSpeech archive failed SHA-256")
    # The archive is the pinned source of truth. Cached extracted files are
    # disposable and are rebuilt so a poisoned cache cannot bypass the hash.
    if os.path.isdir(root):
        shutil.rmtree(root)
    print("extracting …")
    extract_safely(archive, destination)
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
        target = os.path.join(single, f"{speaker}-{index:02d}.flac")
        shutil.copyfile(audio, target)
        open(os.path.splitext(target)[0] + ".txt", "w").write(text + "\n")
    print(f"single: {len(glob.glob(single + '/*.flac'))}")

    made = 0
    dictation_speakers = (
        sorted(speakers) if arguments.dictations > 0 else []
    )
    for speaker in dictation_speakers:
        items = speakers[speaker]
        if len(items) < UTTERANCES_PER_DICTATION:
            continue
        sources, texts = [], []
        for audio, text in items[:UTTERANCES_PER_DICTATION]:
            sources.append(audio)
            texts.append(text)
        target = os.path.join(dictation, f"{speaker}.list")
        with open(target, "w") as manifest:
            manifest.write(f"pause_seconds={PAUSE_SECONDS}\n")
            for source in sources:
                manifest.write(os.path.relpath(source, dictation) + "\n")
        open(os.path.splitext(target)[0] + ".txt", "w").write(
            " ".join(texts) + "\n"
        )
        made += 1
        if made >= arguments.dictations:
            break
    print(f"dictation: {made}")
    print()
    print(f"ZENVOICE_ACCURACY_CORPUS={single} swift run ZenVoiceAccuracyChecks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
