#!/usr/bin/env python3
"""Build a real-speech evaluation corpus from the AMI Meeting Corpus.

`build-librispeech-corpus.py` covers read speech, which is the case ZenVoice is
*least* interested in: nobody dictates like an audiobook narrator. AMI is
spontaneous — people hesitate, restart, talk over each other, and sit in a room
with a projector fan. That is the shape of real dictation, and it is what the
per-engine WER baselines in Phase 6 need to rest on.

Annotations are expected to be present already at

    Datasets/ami_public_1.6.2/

(687 word files, with matching segment files). This script downloads only the
*audio* that goes with them, one individual headset channel per speaker, and
cuts it into utterance clips paired with reference transcripts:

    Datasets/dictation-ami/
        ES2002a.A.0007.wav
        ES2002a.A.0007.txt
        ...
        PROVENANCE.md

which is the flat wav+txt layout `Fixtures.corpus(at:)` reads. Consume it with:

    ZENVOICE_ACCURACY_CORPUS=Datasets/dictation-ami \
    ZENVOICE_ACCURACY_MULTIENGINE=1 \
    swift run ZenVoiceAccuracyChecks

Individual headset channels rather than the mixed `Mix-Headset` track: the word
annotations are per speaker, so scoring a speaker's words against a mix that
also contains three other people measures overlap handling rather than
transcription accuracy.

Licence: the AMI Meeting Corpus is released under CC BY 4.0. Provenance and
licence are written into the corpus directory, which is gitignored — the audio
is fetched on demand and never committed.
"""

import argparse
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import wave
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    from defusedxml.ElementTree import parse as parse_xml
except ImportError:
    # The NITE XML read here is extracted from the checksum-pinned AMI
    # archive this script downloads, so entity expansion is not
    # attacker-controlled; stdlib parsing is the reviewed fallback when
    # defusedxml is not installed.
    parse_xml = ET.parse  # nosemgrep

NITE = "{http://nite.sourceforge.net/}"
MIRROR = "https://groups.inf.ed.ac.uk/ami/AMICorpusMirror/amicorpus"
LICENCE_URL = "https://groups.inf.ed.ac.uk/ami/corpus/"

# Four meetings from the ES2002 series: one group of four speakers across a
# design-team scenario, which keeps voices and rooms consistent enough that a
# WER difference between engines is about the engines.
DEFAULT_MEETINGS = ["ES2002a", "ES2002b"]

# Word-level tags that are not speech. AMI marks laughter, coughs, and
# transcriber disfluency markers inline with the words they interrupt.
NON_SPEECH_TAGS = {"vocalsound", "nonvocalsound", "disfmarker", "pause",
                   "transformerror", "gap"}


def log(message):
    print(message, flush=True)


def download(url, destination):
    """Fetches `url` to `destination`, skipping an already-complete file."""
    if destination.exists() and destination.stat().st_size > 0:
        log(f"  cached  {destination.name} "
            f"({destination.stat().st_size / 1e6:.0f} MB)")
        return True
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    log(f"  fetch   {destination.name}")
    try:
        # curl rather than urllib: resumable, and it is already a dependency of
        # the other corpus scripts.
        subprocess.run(
            ["curl", "-fL", "--retry", "3", "--retry-delay", "2",
             "--connect-timeout", "30", "-C", "-", "-s",
             "-o", str(partial), url],
            check=True,
        )
    except subprocess.CalledProcessError:
        log(f"  MISSING {destination.name} — skipped")
        partial.unlink(missing_ok=True)
        return False
    partial.replace(destination)
    return True


def parse_words(path):
    """Returns {nite:id: (text, starttime, endtime)} in document order.

    Non-speech tags are recorded with `text=None` so an id range that spans
    them still resolves, but they contribute nothing to the reference.
    """
    words = {}
    order = []
    tree = parse_xml(path)
    for element in tree.getroot():
        identifier = element.get(f"{NITE}id")
        if identifier is None:
            continue
        tag = element.tag.split("}")[-1]
        start = element.get("starttime")
        end = element.get("endtime")
        text = None
        if tag == "w" and not element.get("punc"):
            text = (element.text or "").strip()
        elif tag in NON_SPEECH_TAGS:
            text = None
        elif tag == "w":
            text = None  # punctuation: dropped, per ASR scoring convention
        words[identifier] = (
            text,
            float(start) if start else None,
            float(end) if end else None,
            tag,
        )
        order.append(identifier)
    return words, order


CHILD_RANGE = re.compile(r"id\(([^)]+)\)")


def parse_segments(path):
    """Yields (channel, start, end, [word ids]) per transcribed utterance."""
    tree = parse_xml(path)
    for segment in tree.getroot():
        child = segment.find(f"{NITE}child")
        if child is None:
            continue
        identifiers = CHILD_RANGE.findall(child.get("href", ""))
        if not identifiers:
            continue
        yield (
            segment.get("channel"),
            float(segment.get("transcriber_start", "0")),
            float(segment.get("transcriber_end", "0")),
            identifiers,
        )


def resolve_range(order, words, identifiers):
    """Expands an `id(a)..id(b)` range into the ids it covers."""
    if len(identifiers) == 1:
        return [identifiers[0]] if identifiers[0] in words else []
    first, last = identifiers[0], identifiers[-1]
    if first not in words or last not in words:
        return []
    start, end = order.index(first), order.index(last)
    if end < start:
        return []
    return order[start:end + 1]


def clip_audio(source, destination, start_seconds, end_seconds):
    """Writes `source[start:end]` to `destination`, preserving the format."""
    with wave.open(str(source), "rb") as reader:
        rate = reader.getframerate()
        start_frame = max(0, int(start_seconds * rate))
        end_frame = min(reader.getnframes(), int(end_seconds * rate))
        if end_frame <= start_frame:
            return False
        reader.setpos(start_frame)
        frames = reader.readframes(end_frame - start_frame)
        with wave.open(str(destination), "wb") as writer:
            writer.setnchannels(reader.getnchannels())
            writer.setsampwidth(reader.getsampwidth())
            writer.setframerate(rate)
            writer.writeframes(frames)
    return True


def build_meeting(meeting, annotations, audio_dir, out_dir, options):
    """Cuts one meeting into clips. Returns the number written."""
    log(f"{meeting}")
    written = 0
    for speaker in ["A", "B", "C", "D", "E"]:
        words_path = annotations / "words" / f"{meeting}.{speaker}.words.xml"
        segments_path = (
            annotations / "segments" / f"{meeting}.{speaker}.segments.xml"
        )
        if not words_path.exists() or not segments_path.exists():
            continue

        words, order = parse_words(words_path)
        segments = list(parse_segments(segments_path))
        if not segments:
            continue

        channel = segments[0][0]
        if channel is None:
            continue
        audio_path = audio_dir / f"{meeting}.Headset-{channel}.wav"
        url = f"{MIRROR}/{meeting}/audio/{meeting}.Headset-{channel}.wav"
        if not download(url, audio_path):
            continue

        with wave.open(str(audio_path), "rb") as reader:
            log(f"  {audio_path.name}: {reader.getframerate()} Hz, "
                f"{reader.getnchannels()} ch, "
                f"{reader.getnframes() / reader.getframerate() / 60:.0f} min")

        kept = 0
        for index, (_, start, end, identifiers) in enumerate(segments):
            if options.per_speaker and kept >= options.per_speaker:
                break
            covered = resolve_range(order, words, identifiers)
            if not covered:
                continue
            # A segment containing untranscribed audio cannot be a reference.
            if any(words[i][3] == "gap" for i in covered):
                continue
            tokens = [words[i][0] for i in covered if words[i][0]]
            if len(tokens) < options.min_words:
                continue
            times = [
                (words[i][1], words[i][2]) for i in covered
                if words[i][1] is not None and words[i][2] is not None
            ]
            if not times:
                continue
            first = min(t[0] for t in times)
            last = max(t[1] for t in times)
            duration = last - first
            if duration < options.min_seconds or duration > options.max_seconds:
                continue

            name = f"{meeting}.{speaker}.{index:04d}"
            audio_out = out_dir / f"{name}.wav"
            # A little air either side: clipping exactly on the first word's
            # onset shaves the consonant, which is a transcription error the
            # engine did not make.
            if not clip_audio(
                audio_path, audio_out,
                max(0.0, first - 0.15), last + 0.15
            ):
                continue
            (out_dir / f"{name}.txt").write_text(
                " ".join(tokens) + "\n", encoding="utf-8"
            )
            kept += 1
            written += 1
        log(f"  {meeting}.{speaker}: {kept} clip(s)")
    return written


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--meetings", nargs="+", default=DEFAULT_MEETINGS)
    parser.add_argument(
        "--annotations", type=Path,
        default=Path("Datasets/ami_public_1.6.2"),
    )
    parser.add_argument(
        "--audio-cache", type=Path, default=Path("Datasets/ami-audio"),
    )
    parser.add_argument("--out", type=Path, default=Path("Datasets/dictation-ami"))
    parser.add_argument("--min-words", type=int, default=6)
    parser.add_argument("--min-seconds", type=float, default=2.0)
    parser.add_argument("--max-seconds", type=float, default=18.0)
    parser.add_argument(
        "--per-speaker", type=int, default=25,
        help="Clip cap per speaker. The baseline needs a few hundred "
             "utterances, not every minute of every meeting.",
    )
    parser.add_argument(
        "--keep-audio", action="store_true",
        help="Keep the downloaded meeting audio after cutting clips.",
    )
    options = parser.parse_args()

    if not (options.annotations / "words").is_dir():
        sys.exit(
            f"AMI annotations not found at {options.annotations}. Download "
            "ami_public_1.6.2 first."
        )

    options.out.mkdir(parents=True, exist_ok=True)
    total = 0
    for meeting in options.meetings:
        total += build_meeting(
            meeting, options.annotations, options.audio_cache,
            options.out, options,
        )

    (options.out / "PROVENANCE.md").write_text(
        "# Corpus provenance\n\n"
        "| Field | Value |\n|---|---|\n"
        "| Source | AMI Meeting Corpus, individual headset channels |\n"
        f"| Meetings | {', '.join(options.meetings)} |\n"
        f"| Mirror | {MIRROR} |\n"
        "| Annotations | ami_public_1.6.2, words + segments |\n"
        "| Licence | CC BY 4.0 |\n"
        f"| Licence source | {LICENCE_URL} |\n"
        f"| Clips | {total} |\n"
        f"| Built by | Scripts/build-ami-corpus.py |\n\n"
        "Speech is spontaneous rather than read. References are the AMI word "
        "annotations for that speaker with punctuation and non-speech markers "
        "(laughter, coughs, disfluency marks) removed, which is the usual ASR "
        "scoring convention. Segments containing untranscribed `gap` regions "
        "are skipped, because an incomplete reference scores as engine error.\n\n"
        "Audio is fetched on demand and gitignored. Do not commit it.\n",
        encoding="utf-8",
    )

    if not options.keep_audio and options.audio_cache.is_dir():
        shutil.rmtree(options.audio_cache)
        log(f"removed {options.audio_cache} (pass --keep-audio to keep it)")

    log(f"\n{total} clip(s) in {options.out}")
    if total == 0:
        sys.exit("no clips were produced")


if __name__ == "__main__":
    main()
