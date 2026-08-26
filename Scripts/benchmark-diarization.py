#!/usr/bin/env python3
"""Prepare and score local speaker-diarization candidates.

Developer-only harness. It uses Python's standard library; Python is not a
ZenVoice runtime dependency. AMI annotations remain the source of truth.

Examples:
  Scripts/benchmark-diarization.py reference --meeting ES2004a \
    --annotations Datasets/ami_public_1.6.2 --output /tmp/ES2004a.rttm
  Scripts/benchmark-diarization.py score --reference /tmp/ES2004a.rttm \
    --hypothesis /tmp/fluid.json --format fluid --audio /tmp/ES2004a.wav
"""

import argparse
import array
import json
import math
import os
import re
import tempfile
import wave
from pathlib import Path

try:
    from defusedxml.ElementTree import parse as parse_xml
except ImportError:
    import xml.etree.ElementTree as ET

    def parse_xml(path):
        data = Path(path).read_bytes()
        if b"<!DOCTYPE" in data or b"<!ENTITY" in data:
            raise ValueError("DTD/entity declarations are not allowed")
        return ET.parse(path)


NITE = "{http://nite.sourceforge.net/}"
QUESTION_DA_IDS = {"ami_da_5", "ami_da_8", "ami_da_11", "ami_da_13"}
CHILD_RANGE = re.compile(r"id\(([^)]+)\)")
SHERPA_SEGMENT = re.compile(
    r"^\s*(\d+(?:\.\d+)?)\s+--\s+(\d+(?:\.\d+)?)\s+(speaker_\d+)\s*$"
)
MAX_DURATION_SECONDS = 6 * 60 * 60


def safe_text_write(path, text):
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(str(path), flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(text)


def safe_binary_output(path):
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0)
    return os.fdopen(os.open(str(path), flags, 0o600), "wb")


def validated_segment(start, end, speaker):
    if (
        not math.isfinite(start)
        or not math.isfinite(end)
        or start < 0
        or end <= start
        or end > MAX_DURATION_SECONDS
        or not speaker
    ):
        raise ValueError(f"invalid segment: {start} -- {end} {speaker!r}")
    return start, end, speaker


def bit_count(value):
    return bin(value).count("1")


def wav_duration(path):
    with wave.open(str(path), "rb") as reader:
        duration = reader.getnframes() / reader.getframerate()
    if not 0 < duration <= MAX_DURATION_SECONDS:
        raise ValueError(f"invalid WAV duration: {duration}")
    return duration


def read_rttm(path):
    segments = []
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) < 8 or fields[0] != "SPEAKER":
            raise ValueError(f"invalid RTTM line: {raw}")
        start = float(fields[3])
        end = start + float(fields[4])
        segments.append(validated_segment(start, end, fields[7]))
    return segments


def write_rttm(path, recording_id, segments):
    lines = [
        f"SPEAKER {recording_id} 1 {start:.3f} {end - start:.3f} "
        f"<NA> <NA> {speaker} <NA> <NA>"
        for start, end, speaker in sorted(segments)
        if end > start
    ]
    safe_text_write(path, "\n".join(lines) + "\n")


def ami_segments(annotations, meeting, speakers):
    segments = []
    for speaker in speakers:
        path = annotations / "segments" / f"{meeting}.{speaker}.segments.xml"
        if not path.exists():
            continue
        for element in parse_xml(path).getroot():
            start = float(element.get("transcriber_start", "0"))
            end = float(element.get("transcriber_end", "0"))
            if end - start >= 0.5:
                segments.append(validated_segment(start, end, speaker))
    return sorted(segments)


def ami_question_count(annotations, meeting, speakers):
    count = 0
    for speaker in speakers:
        path = annotations / "dialogueActs" / f"{meeting}.{speaker}.dialog-act.xml"
        if not path.exists():
            continue
        for act in parse_xml(path).getroot():
            pointer = act.find(f"{NITE}pointer")
            href = pointer.get("href", "") if pointer is not None else ""
            if any(f"id({identifier})" in href for identifier in QUESTION_DA_IDS):
                count += 1
    return count

def ami_words(path):
    words = {}
    order = []
    for element in parse_xml(path).getroot():
        identifier = element.get(f"{NITE}id")
        if not identifier:
            continue
        start = element.get("starttime")
        end = element.get("endtime")
        tag = element.tag.split("}")[-1]
        text = (element.text or "").strip() if tag == "w" and not element.get("punc") else ""
        words[identifier] = {
            "start": float(start) if start else None,
            "end": float(end) if end else None,
            "text": text,
        }
        order.append(identifier)
    return words, order


def resolve_word_range(words, order, identifiers):
    if not identifiers or identifiers[0] not in words:
        return []
    if len(identifiers) == 1:
        return [identifiers[0]]
    if identifiers[-1] not in words:
        return []
    first = order.index(identifiers[0])
    last = order.index(identifiers[-1])
    return order[first:last + 1] if last >= first else []


def ami_questions(annotations, meeting, speakers, reference, teacher):
    questions = []
    for speaker in speakers:
        words_path = annotations / "words" / f"{meeting}.{speaker}.words.xml"
        acts_path = annotations / "dialogueActs" / f"{meeting}.{speaker}.dialog-act.xml"
        if not words_path.exists() or not acts_path.exists():
            continue
        words, order = ami_words(words_path)
        for act in parse_xml(acts_path).getroot():
            pointer = act.find(f"{NITE}pointer")
            href = pointer.get("href", "") if pointer is not None else ""
            if not any(f"id({identifier})" in href for identifier in QUESTION_DA_IDS):
                continue
            child = act.find(f"{NITE}child")
            identifiers = CHILD_RANGE.findall(child.get("href", "")) if child is not None else []
            covered = resolve_word_range(words, order, identifiers)
            timed = [
                words[item] for item in covered
                if words[item]["start"] is not None and words[item]["end"] is not None
            ]
            if not timed:
                continue
            start = min(item["start"] for item in timed)
            end = max(item["end"] for item in timed)
            overlap = any(
                other != speaker and other_start < end and other_end > start
                for other_start, other_end, other in reference
            )
            questions.append({
                "start": start,
                "end": end,
                "speaker": speaker,
                "referenceRole": "overlap" if overlap else (
                    "teacher" if speaker == teacher else "others"
                ),
                "text": " ".join(item["text"] for item in timed if item["text"]),
            })
    return sorted(questions, key=lambda item: item["start"])


def masks_for_segments(segments, labels, frame_count, frame_seconds):
    masks = [0] * frame_count
    for start, end, speaker in segments:
        bit = 1 << labels[speaker]
        first = max(0, int(math.floor(start / frame_seconds)))
        last = min(frame_count, int(math.ceil(end / frame_seconds)))
        for index in range(first, last):
            masks[index] |= bit
    return masks


def collar_mask(reference, frame_count, frame_seconds, collar):
    ignored = bytearray(frame_count)
    radius = int(math.ceil(collar / frame_seconds))
    for start, end, _ in reference:
        for boundary in (start, end):
            center = int(round(boundary / frame_seconds))
            lo = max(0, center - radius)
            hi = min(frame_count, center + radius + 1)
            ignored[lo:hi] = b"\x01" * (hi - lo)
    return ignored


def hungarian_max(weights):
    """Maximum one-to-one row/column assignment; returns row -> column."""
    rows = len(weights)
    cols = max((len(row) for row in weights), default=0)
    size = max(rows, cols)
    if size == 0:
        return {}
    maximum = max((max(row, default=0) for row in weights), default=0)
    cost = [[maximum] * size for _ in range(size)]
    for i, row in enumerate(weights):
        for j, value in enumerate(row):
            cost[i][j] = maximum - value

    u = [0.0] * (size + 1)
    v = [0.0] * (size + 1)
    p = [0] * (size + 1)
    way = [0] * (size + 1)
    for i in range(1, size + 1):
        p[0] = i
        j0 = 0
        minimum = [float("inf")] * (size + 1)
        used = [False] * (size + 1)
        while True:
            used[j0] = True
            i0 = p[j0]
            delta = float("inf")
            j1 = 0
            for j in range(1, size + 1):
                if used[j]:
                    continue
                current = cost[i0 - 1][j - 1] - u[i0] - v[j]
                if current < minimum[j]:
                    minimum[j] = current
                    way[j] = j0
                if minimum[j] < delta:
                    delta = minimum[j]
                    j1 = j
            for j in range(size + 1):
                if used[j]:
                    u[p[j]] += delta
                    v[j] -= delta
                else:
                    minimum[j] -= delta
            j0 = j1
            if p[j0] == 0:
                break
        while True:
            j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
            if j0 == 0:
                break

    assignment = {}
    for column in range(1, size + 1):
        row = p[column] - 1
        if row < rows and column - 1 < cols:
            assignment[row] = column - 1
    return assignment


def score_segments(reference, hypothesis, duration, frame_seconds=0.01, collar=0.25):
    if (
        not math.isfinite(duration)
        or duration <= 0
        or duration > MAX_DURATION_SECONDS
    ):
        raise ValueError(f"invalid benchmark duration: {duration}")
    ref_names = sorted({speaker for _, _, speaker in reference})
    hyp_names = sorted({speaker for _, _, speaker in hypothesis})
    ref_index = {name: index for index, name in enumerate(ref_names)}
    hyp_index = {name: index for index, name in enumerate(hyp_names)}
    frame_count = max(1, int(math.ceil(duration / frame_seconds)))
    ref_masks = masks_for_segments(reference, ref_index, frame_count, frame_seconds)
    hyp_masks = masks_for_segments(hypothesis, hyp_index, frame_count, frame_seconds)
    ignored = collar_mask(reference, frame_count, frame_seconds, collar)

    overlap_weights = [[0] * len(ref_names) for _ in hyp_names]
    for frame, ref_mask in enumerate(ref_masks):
        if ignored[frame] or bit_count(ref_mask) != 1:
            continue
        ref_bit = ref_mask.bit_length() - 1
        hyp_mask = hyp_masks[frame]
        while hyp_mask:
            low = hyp_mask & -hyp_mask
            hyp_bit = low.bit_length() - 1
            overlap_weights[hyp_bit][ref_bit] += 1
            hyp_mask ^= low
    assignment = hungarian_max(overlap_weights)

    miss = false_alarm = confusion = reference_time = 0
    overlap_frames = overlap_detected = silence_frames = silence_false_alarm = 0
    longest_silence = current_silence = 0
    ref_totals = [0] * len(ref_names)
    hyp_totals = [0] * len(hyp_names)

    for frame, ref_mask in enumerate(ref_masks):
        hyp_mask = hyp_masks[frame]
        for bit in range(len(ref_names)):
            if ref_mask & (1 << bit):
                ref_totals[bit] += 1
        for bit in range(len(hyp_names)):
            if hyp_mask & (1 << bit):
                hyp_totals[bit] += 1

        if ref_mask == 0:
            current_silence += 1
            longest_silence = max(longest_silence, current_silence)
            silence_frames += 1
            if hyp_mask:
                silence_false_alarm += 1
        else:
            current_silence = 0
        if bit_count(ref_mask) > 1:
            overlap_frames += 1
            if bit_count(hyp_mask) > 1:
                overlap_detected += 1

        if ignored[frame] or bit_count(ref_mask) > 1:
            continue
        ref_count = bit_count(ref_mask)
        hyp_count = bit_count(hyp_mask)
        mapped_mask = 0
        active = hyp_mask
        while active:
            low = active & -active
            hyp_bit = low.bit_length() - 1
            ref_bit = assignment.get(hyp_bit)
            if ref_bit is not None:
                mapped_mask |= 1 << ref_bit
            active ^= low
        correct = bit_count(mapped_mask & ref_mask)
        miss += max(0, ref_count - hyp_count)
        false_alarm += max(0, hyp_count - ref_count)
        confusion += min(ref_count, hyp_count) - correct
        reference_time += ref_count

    denominator = max(1, reference_time)
    dominant_ref = max(range(len(ref_totals)), key=ref_totals.__getitem__) if ref_totals else None
    dominant_hyp = max(range(len(hyp_totals)), key=hyp_totals.__getitem__) if hyp_totals else None
    mapped_dominant = assignment.get(dominant_hyp) if dominant_hyp is not None else None
    dominant_share = (
        ref_totals[dominant_ref] / max(1, sum(ref_totals)) if dominant_ref is not None else 0
    )
    step = frame_seconds
    return {
        "durationSeconds": duration,
        "referenceSpeakers": len(ref_names),
        "detectedSpeakers": len(hyp_names),
        "speakerCountError": len(hyp_names) - len(ref_names),
        "derPercent": 100 * (miss + false_alarm + confusion) / denominator,
        "missPercent": 100 * miss / denominator,
        "falseAlarmPercent": 100 * false_alarm / denominator,
        "speakerErrorPercent": 100 * confusion / denominator,
        "dominantReferenceSpeaker": ref_names[dominant_ref] if dominant_ref is not None else None,
        "dominantPredictedSpeaker": hyp_names[dominant_hyp] if dominant_hyp is not None else None,
        "dominantMappedSpeaker": ref_names[mapped_dominant] if mapped_dominant is not None else None,
        "dominantSpeakerCorrect": mapped_dominant == dominant_ref and dominant_ref is not None,
        "dominantReferenceSharePercent": 100 * dominant_share,
        "overlapSeconds": overlap_frames * step,
        "overlapDetectionRecallPercent": 100 * overlap_detected / max(1, overlap_frames),
        "silenceSeconds": silence_frames * step,
        "longestSilenceSeconds": longest_silence * step,
        "silenceFalseAlarmPercent": 100 * silence_false_alarm / max(1, silence_frames),
        "collarSeconds": collar,
        "ignoreOverlap": True,
    }


def load_hypothesis(path, format_name):
    if format_name == "fluid":
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
        segments = [
            validated_segment(
                float(item["startTimeSeconds"]),
                float(item["endTimeSeconds"]),
                str(item["speakerId"]),
            )
            for item in payload["segments"]
        ]
        return segments, float(payload.get("durationSeconds", 0))
    if format_name == "sherpa":
        segments = []
        duration = 0.0
        started = completed = False
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if line.strip() == "Started":
                started = True
            if line.strip() == "SHERPA_EXIT_OK":
                completed = True
                continue
            match = SHERPA_SEGMENT.match(line)
            if match:
                if completed:
                    raise ValueError("sherpa segment appeared after completion marker")
                start, end, speaker = match.groups()
                segment = validated_segment(float(start), float(end), speaker)
                segments.append(segment)
                duration = max(duration, segment[1])
            elif "--" in line and "speaker_" in line:
                raise ValueError(f"malformed sherpa segment: {line}")
        if not started or not completed or not segments:
            raise ValueError(
                "incomplete sherpa output; capture only after a zero exit and "
                "append SHERPA_EXIT_OK"
            )
        return segments, duration
    if format_name == "rttm":
        segments = read_rttm(path)
        return segments, max((end for _, end, _ in segments), default=0)
    raise ValueError(f"unknown hypothesis format: {format_name}")


def command_reference(args):
    speakers = args.speakers or ["A", "B", "C", "D"]
    segments = ami_segments(args.annotations, args.meeting, speakers)
    if not segments:
        raise SystemExit("no AMI segments found")
    write_rttm(args.output, args.meeting, segments)
    duration = args.duration or max(end for _, end, _ in segments)
    analysis = score_segments(segments, segments, duration)
    analysis["meeting"] = args.meeting
    analysis["questionActs"] = ami_question_count(
        args.annotations, args.meeting, speakers
    )
    print(json.dumps(analysis, indent=2, sort_keys=True))

def command_metadata(args):
    speakers = args.speakers or ["A", "B", "C", "D"]
    reference = ami_segments(args.annotations, args.meeting, speakers)
    if not reference:
        raise SystemExit("no AMI segments found")
    durations = {
        speaker: sum(
            end - start for start, end, current in reference
            if current == speaker
        )
        for speaker in speakers
    }
    teacher = max(durations, key=durations.get)
    payload = {
        "meeting": args.meeting,
        "teacherSpeaker": teacher,
        "speakerDurations": durations,
        "questions": ami_questions(
            args.annotations,
            args.meeting,
            speakers,
            reference,
            teacher,
        ),
    }
    encoded = json.dumps(payload, indent=2, sort_keys=True)
    safe_text_write(args.output, encoded + "\n")
    print(encoded)



def command_score(args):
    reference = read_rttm(args.reference)
    hypothesis, inferred_duration = load_hypothesis(args.hypothesis, args.format)
    duration = args.duration
    if args.audio:
        duration = wav_duration(args.audio)
    if not duration:
        duration = max(
            inferred_duration,
            max((end for _, end, _ in reference), default=0),
        )
    result = score_segments(reference, hypothesis, duration, collar=args.collar)
    if args.processing_seconds is not None:
        result["processingSeconds"] = args.processing_seconds
        result["realTimeFactorX"] = duration / max(args.processing_seconds, 1e-9)
    encoded = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        safe_text_write(args.output, encoded + "\n")
    print(encoded)


def command_concat(args):
    if len(args.audio) != len(args.rttm):
        raise SystemExit("--audio and --rttm counts must match")
    if not 0 < args.duration <= MAX_DURATION_SECONDS:
        raise ValueError("invalid concat duration")
    output_segments = []
    cursor_seconds = 0.0
    writer = None
    output_params = None
    try:
        for source_index, (audio_path, rttm_path) in enumerate(
            zip(args.audio, args.rttm)
        ):
            if cursor_seconds >= args.duration:
                break
            with wave.open(str(audio_path), "rb") as reader:
                params = (
                    reader.getnchannels(),
                    reader.getsampwidth(),
                    reader.getframerate(),
                )
                if writer is None:
                    writer = wave.open(safe_binary_output(args.output_audio), "wb")
                    writer.setnchannels(params[0])
                    writer.setsampwidth(params[1])
                    writer.setframerate(params[2])
                    output_params = params
                elif params != output_params:
                    raise ValueError("all WAV inputs must share channel/width/rate")
                available = min(
                    reader.getnframes(),
                    int((args.duration - cursor_seconds) * reader.getframerate()),
                )
                remaining = available
                while remaining > 0:
                    frames = reader.readframes(min(8192, remaining))
                    if not frames:
                        break
                    writer.writeframesraw(frames)
                    remaining -= len(frames) // (
                        reader.getnchannels() * reader.getsampwidth()
                    )
                copied_seconds = (available - remaining) / reader.getframerate()
                for start, end, speaker in read_rttm(rttm_path):
                    if start >= copied_seconds:
                        continue
                    output_segments.append(
                        validated_segment(
                            cursor_seconds + start,
                            cursor_seconds + min(end, copied_seconds),
                            f"m{source_index}_{speaker}",
                        )
                    )
                cursor_seconds += copied_seconds
                silence = min(args.silence, args.duration - cursor_seconds)
                if silence > 0:
                    silence_frames = int(silence * reader.getframerate())
                    zero = b"\0" * (
                        8192 * reader.getnchannels() * reader.getsampwidth()
                    )
                    while silence_frames > 0:
                        count = min(8192, silence_frames)
                        writer.writeframesraw(
                            zero[: count * reader.getnchannels() * reader.getsampwidth()]
                        )
                        silence_frames -= count
                    cursor_seconds += silence
        if writer is None:
            raise ValueError("no audio inputs")
    finally:
        if writer is not None:
            writer.close()
    write_rttm(args.output_rttm, args.output_audio.stem, output_segments)
    print(json.dumps({
        "durationSeconds": cursor_seconds,
        "speakerCount": len({speaker for _, _, speaker in output_segments}),
        "segments": len(output_segments),
    }, indent=2, sort_keys=True))


def command_mix(args):
    readers = [wave.open(str(path), "rb") for path in args.input]
    try:
        params = [
            (r.getnchannels(), r.getsampwidth(), r.getframerate()) for r in readers
        ]
        if len(set(params)) != 1 or params[0][:2] != (1, 2):
            raise ValueError("mix requires matching mono 16-bit PCM WAV inputs")
        with wave.open(safe_binary_output(args.output), "wb") as writer:
            writer.setnchannels(1)
            writer.setsampwidth(2)
            writer.setframerate(params[0][2])
            while True:
                blocks = [r.readframes(8192) for r in readers]
                if not any(blocks):
                    break
                samples = [array.array("h", block) for block in blocks]
                length = max(map(len, samples))
                mixed = array.array("h")
                for index in range(length):
                    total = sum(s[index] if index < len(s) else 0 for s in samples)
                    mixed.append(max(-32768, min(32767, round(total / len(samples)))))
                writer.writeframesraw(mixed.tobytes())
    finally:
        for reader in readers:
            reader.close()


def command_self_check(_args):
    reference = [(0, 2, "A"), (2, 4, "B")]
    swapped = [(0, 2, "x"), (2, 4, "y")]
    result = score_segments(reference, swapped, 4, collar=0)
    assert result["derPercent"] == 0
    assert result["dominantSpeakerCorrect"]
    fragmented = [(0, 1, "x"), (1, 2, "z"), (2, 4, "y")]
    result = score_segments(reference, fragmented, 4, collar=0)
    assert result["speakerCountError"] == 1
    assert result["derPercent"] > 0
    try:
        score_segments(reference, swapped, MAX_DURATION_SECONDS + 1)
        raise AssertionError("oversized duration was accepted")
    except ValueError:
        pass
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        path = root / "test.rttm"
        write_rttm(path, "test", reference)
        assert read_rttm(path) == reference
        target = root / "target"
        target.write_text("keep", encoding="utf-8")
        link = root / "link"
        link.symlink_to(target)
        try:
            safe_text_write(link, "replace")
            if getattr(os, "O_NOFOLLOW", 0):
                raise AssertionError("symlink output was followed")
        except OSError:
            pass
        assert target.read_text(encoding="utf-8") == "keep"
        sherpa = root / "sherpa.txt"
        sherpa.write_text(
            "Started\nDuration : 4.0 s\n0.0 -- 2.0 speaker_00\n",
            encoding="utf-8",
        )
        try:
            load_hypothesis(sherpa, "sherpa")
            raise AssertionError("truncated sherpa output was accepted")
        except ValueError:
            pass
        with sherpa.open("a", encoding="utf-8") as handle:
            handle.write("SHERPA_EXIT_OK\n")
        assert len(load_hypothesis(sherpa, "sherpa")[0]) == 1
    print("benchmark-diarization: self-check passed")


def command_frames(args):
    reference = read_rttm(args.reference)
    payload = json.loads(args.hypothesis.read_text(encoding="utf-8"))
    labels = payload["frames"]
    step = float(payload["frameSeconds"])
    duration = float(payload.get("durationSeconds") or len(labels) * step)
    overlap_ref = silence_ref = overlap_hit = silence_fa = 0
    for index, label in enumerate(labels):
        start = index * step
        end = min(duration, start + step)
        speakers = {
            speaker for ref_start, ref_end, speaker in reference
            if ref_start < end and ref_end > start
        }
        if len(speakers) > 1:
            overlap_ref += 1
            overlap_hit += label == "overlap"
        elif not speakers:
            silence_ref += 1
            silence_fa += label != "silence"
    result = {
        "backend": payload.get("backend"),
        "durationSeconds": duration,
        "overlapRecall": overlap_hit / max(1, overlap_ref),
        "silenceFalseAlarm": silence_fa / max(1, silence_ref),
        "overlapReferenceFrames": overlap_ref,
        "silenceReferenceFrames": silence_ref,
        "predictedOverlapFrames": sum(label == "overlap" for label in labels),
        "predictedSpeechFrames": sum(label == "speech" for label in labels),
        "predictedSilenceFrames": sum(label == "silence" for label in labels),
    }
    encoded = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        safe_text_write(args.output, encoded + "\n")
    print(encoded)


def parser():
    root = argparse.ArgumentParser(description=__doc__)
    sub = root.add_subparsers(dest="command", required=True)

    reference = sub.add_parser("reference")
    reference.add_argument("--meeting", required=True)
    reference.add_argument("--annotations", type=Path, required=True)
    reference.add_argument("--output", type=Path, required=True)
    reference.add_argument("--speakers", nargs="*")
    reference.add_argument("--duration", type=float)
    reference.set_defaults(handler=command_reference)

    metadata = sub.add_parser("metadata")
    metadata.add_argument("--meeting", required=True)
    metadata.add_argument("--annotations", type=Path, required=True)
    metadata.add_argument("--output", type=Path, required=True)
    metadata.add_argument("--speakers", nargs="*")
    metadata.set_defaults(handler=command_metadata)

    score = sub.add_parser("score")
    score.add_argument("--reference", type=Path, required=True)
    score.add_argument("--hypothesis", type=Path, required=True)
    score.add_argument("--format", choices=["fluid", "sherpa", "rttm"], required=True)
    score.add_argument("--audio", type=Path)
    score.add_argument("--duration", type=float)
    score.add_argument("--collar", type=float, default=0.25)
    score.add_argument("--processing-seconds", type=float)
    score.add_argument("--output", type=Path)
    score.set_defaults(handler=command_score)

    concat = sub.add_parser("concat")
    concat.add_argument("--audio", type=Path, action="append", required=True)
    concat.add_argument("--rttm", type=Path, action="append", required=True)
    concat.add_argument("--output-audio", type=Path, required=True)
    concat.add_argument("--output-rttm", type=Path, required=True)
    concat.add_argument("--duration", type=float, default=3600)
    concat.add_argument("--silence", type=float, default=30)
    concat.set_defaults(handler=command_concat)

    mix = sub.add_parser("mix")
    mix.add_argument("--input", type=Path, action="append", required=True)
    mix.add_argument("--output", type=Path, required=True)
    mix.set_defaults(handler=command_mix)

    frames = sub.add_parser("frames")
    frames.add_argument("--reference", type=Path, required=True)
    frames.add_argument("--hypothesis", type=Path, required=True)
    frames.add_argument("--output", type=Path)
    frames.set_defaults(handler=command_frames)

    check = sub.add_parser("self-check")
    check.set_defaults(handler=command_self_check)
    return root


if __name__ == "__main__":
    arguments = parser().parse_args()
    arguments.handler(arguments)
