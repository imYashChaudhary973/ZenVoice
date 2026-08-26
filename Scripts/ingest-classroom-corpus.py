#!/usr/bin/env python3
"""Validate a consented classroom lecture folder. Fail closed."""

import argparse
import json
import math
import sys
from pathlib import Path

REQUIRED_DURATIONS = (30, 60, 90)


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def read_rttm(path):
    turns = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) < 8 or fields[0] != "SPEAKER":
            raise ValueError(f"invalid RTTM: {raw}")
        start = float(fields[3])
        duration = float(fields[4])
        if not math.isfinite(start) or not math.isfinite(duration) or start < 0 or duration <= 0:
            raise ValueError(f"invalid RTTM times: {raw}")
        turns.append((start, start + duration, fields[7]))
    return turns


def regular_file(path):
    return path.is_file() and not path.is_symlink() and path.stat().st_size > 0


def bucket(minutes):
    if 30 <= minutes < 60:
        return 30
    if 60 <= minutes < 90:
        return 60
    if minutes == 90:
        return 90
    return None


def ingest(root, gate):
    missing = []
    records = []
    classroom = gate["classroom"]
    for lecture_dir in sorted(path for path in root.iterdir() if path.is_dir()):
        audio = lecture_dir / "audio.wav"
        consent_path = lecture_dir / "consent.json"
        rttm_path = lecture_dir / "reference.rttm"
        questions_path = lecture_dir / "questions.json"
        for path in (audio, consent_path, rttm_path, questions_path):
            if not regular_file(path):
                missing.append(f"missing classroom artifact: {path}")
        if missing:
            continue
        consent = load_json(consent_path)
        questions = load_json(questions_path)
        turns = read_rttm(rttm_path)
        duration = float(consent["durationSeconds"])
        if duration < 1800 or duration > 5400:
            missing.append(f"{lecture_dir.name}: duration not 30-90 minutes")
        if consent.get("teacherConsent") is not True or consent.get("participantConsent") is not True:
            missing.append(f"{lecture_dir.name}: consent is not validated")
        if consent.get("consentScope") != "local-research-only":
            missing.append(f"{lecture_dir.name}: consent scope is not local-research-only")
        if not turns or not any(speaker == consent["teacherID"] for _, _, speaker in turns):
            missing.append(f"{lecture_dir.name}: RTTM omits teacher")
        student_questions = [
            row for row in questions if row.get("referenceRole") == "others"
        ]
        records.append({
            "lectureID": consent["lectureID"],
            "teacherID": consent["teacherID"],
            "roomID": consent["roomID"],
            "durationSeconds": duration,
            "studentQuestionCount": len(student_questions),
            "split": None,
        })

    teachers = sorted({row["teacherID"] for row in records})
    rooms = sorted({row["roomID"] for row in records})
    if len(teachers) < 2 or len(rooms) < 2:
        missing.append("need at least two teachers and two rooms for disjoint splits")
        calibration_teachers, evaluation_teachers = set(), set(teachers)
        calibration_rooms, evaluation_rooms = set(), set(rooms)
    else:
        calibration_teachers = {teachers[0]}
        evaluation_teachers = set(teachers[1:])
        calibration_rooms = {rooms[0]}
        evaluation_rooms = set(rooms[1:])

    calibration = []
    evaluation = []
    for row in records:
        if row["teacherID"] in calibration_teachers and row["roomID"] in calibration_rooms:
            row["split"] = "calibration"
            calibration.append(row)
        elif row["teacherID"] in evaluation_teachers and row["roomID"] in evaluation_rooms:
            row["split"] = "evaluation"
            evaluation.append(row)
        else:
            missing.append(f"{row['lectureID']}: crosses teacher/room split")

    hours = sum(row["durationSeconds"] for row in evaluation) / 3600
    questions = sum(row["studentQuestionCount"] for row in evaluation)
    buckets = {bucket(row["durationSeconds"] / 60) for row in evaluation}
    if len(evaluation) < classroom["minimumEvaluationLectures"]:
        missing.append("too few evaluation lectures")
    if len({row["teacherID"] for row in evaluation}) < classroom["minimumEvaluationTeachers"]:
        missing.append("too few evaluation teachers")
    if len({row["roomID"] for row in evaluation}) < classroom["minimumEvaluationRooms"]:
        missing.append("too few evaluation rooms")
    if hours < classroom["minimumEvaluationHours"]:
        missing.append("too few evaluation hours")
    if questions < classroom["minimumEvaluationStudentQuestions"]:
        missing.append("too few student questions")
    if any(required not in buckets for required in REQUIRED_DURATIONS):
        missing.append("missing 30/60/90-minute evaluation buckets")
    if not calibration:
        missing.append("no teacher/room-disjoint calibration lectures")

    ready = not missing and bool(evaluation) and bool(calibration)
    return records, missing, {
        "ready": ready,
        "manifest": "manifest.jsonl" if ready else None,
        "evaluationLectures": len(evaluation),
        "evaluationTeachers": len({row["teacherID"] for row in evaluation}),
        "evaluationRooms": len({row["roomID"] for row in evaluation}),
        "evaluationHours": hours,
        "evaluationStudentQuestions": questions,
        "teacherDisjoint": not (calibration_teachers & evaluation_teachers),
        "roomDisjoint": not (calibration_rooms & evaluation_rooms),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--gate", type=Path, required=True)
    parser.add_argument("--status", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    gate = load_json(args.gate)
    if not args.root.exists():
        records, missing, classroom = [], ["classroom lecture root is missing"], {
            "ready": False,
            "manifest": None,
            "evaluationLectures": 0,
            "evaluationTeachers": 0,
            "evaluationRooms": 0,
            "evaluationHours": 0,
            "evaluationStudentQuestions": 0,
            "teacherDisjoint": False,
            "roomDisjoint": False,
        }
    else:
        records, missing, classroom = ingest(args.root, gate)
    status = load_json(args.status) if args.status.exists() else {}
    status["assessedAt"] = "2026-08-23"
    status["classroom"] = classroom
    status["phase1C1Decision"] = (
        "CLASSROOM_CORPUS_READY" if classroom["ready"] else "FAIL_CLOSED_CLASSROOM_CORPUS_MISSING"
    )
    if missing:
        status["classroom"]["missingPrerequisite"] = "; ".join(missing)
    args.status.write_text(json.dumps(status, indent=2) + "\n", encoding="utf-8")
    if classroom["ready"]:
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(
            "\n".join(json.dumps(row, sort_keys=True) for row in records) + "\n",
            encoding="utf-8",
        )
        print("classroom ingest: READY")
        return 0
    print("classroom ingest: FAIL")
    for item in missing:
        print(f"- {item}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
