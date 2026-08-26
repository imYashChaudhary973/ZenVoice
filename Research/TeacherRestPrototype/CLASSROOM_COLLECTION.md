# Classroom collection — Phase 1C.1

This is the missing promotion corpus. AMI is engineering data only.
Do not reuse dictation clips. Do not invent lectures.

## What to record

Each lecture must be one real class, 16 kHz mono WAV:

- Several teachers and several rooms
- Separate 30–<60, 60–<90, and 90-minute lectures
- Distant student questions
- Similar teacher/student voices
- Overlap and interruptions
- Quiet speech, noise, and long breaks

Minimum evaluation set from `GATE.json`:

- 10 lectures, 5 teachers, 3 rooms, 8 hours, 100 student questions
- Calibration teachers ≠ evaluation teachers
- Calibration rooms ≠ evaluation rooms

## Consent

One `consent.json` per lecture matching `classroom-consent.schema.json`.

- Teacher and every audible participant must consent
- Scope is local research only
- Delete with the lecture
- No cloud upload, no voiceprints, no cross-lecture comparison

## Annotation

Write RTTM with speaker IDs. Roles are derived later:

```
SPEAKER <lectureID> 1 <start> <dur> <NA> <NA> <speakerID> <NA> <NA>
```

Write `questions.json` matching `classroom-questions.schema.json`:

- `teacher` — teacher asked it
- `others` — student question
- `overlap` — overlapping speech

Do not mark silence as a speaker. Silence is the absence of an RTTM turn.

## Layout

```
Datasets/classroom-lectures/
  <lectureID>/
    audio.wav
    consent.json
    reference.rttm
    questions.json
```

Then:

```
Scripts/ingest-classroom-corpus.py \
  --root Datasets/classroom-lectures \
  --gate Research/TeacherRestPrototype/GATE.json \
  --status Research/TeacherRestPrototype/CORPUS_STATUS.json \
  --manifest Datasets/classroom-lectures/manifest.jsonl
```

Ingest fail-closes unless every GATE classroom minimum is met.

## Fine-tuning

A classroom-fine-tuned segmentation model is allowed only after this
corpus exists. Until then, skip it.
