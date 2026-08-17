#!/usr/bin/env python3
"""Create and validate local, consented ZenVoice dictation sessions.

The workflow is deliberately local-only. ``init`` creates an empty recording
session with a consent form and representative prompt pack. ``validate``
accepts only explicit adult consent, verbatim transcripts, and 16 kHz mono PCM
audio, then writes a provenance-rich JSONL manifest below ``Datasets``.

Nothing is recorded, uploaded, licensed, or consented by this script.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import wave
from datetime import datetime
from pathlib import Path
from typing import Any


SAMPLE_RATE = 16_000
MIN_SECONDS = 0.5
MAX_SECONDS = 30.0
CONSENT_VERSION = "zenvoice-dictation-v1"
PROMPT_PACK_VERSION = "zenvoice-dictation-prompts-v2"
PROMPTS_PER_CATEGORY = 6
IDENTIFIER = re.compile(r"^[a-z0-9][a-z0-9_-]{2,63}$")

PROMPTS = [
    {
        "id": "email-update",
        "category": "email",
        "kind": "spontaneous",
        "instruction": "Dictate a short project-status email with a greeting, two updates, and a polite closing.",
    },
    {
        "id": "email-request",
        "category": "email",
        "kind": "spontaneous",
        "instruction": "Dictate an email requesting a deadline change and give one reason without sharing private information.",
    },
    {
        "id": "email-followup",
        "category": "email",
        "kind": "spontaneous",
        "instruction": "Dictate a meeting follow-up email confirming a fictional owner, due date, and one item that is not approved.",
    },
    {
        "id": "email-apology",
        "category": "email",
        "kind": "spontaneous",
        "instruction": "Dictate a brief professional apology for a delayed reply and propose a new fictional time.",
    },
    {
        "id": "email-invitation",
        "category": "email",
        "kind": "spontaneous",
        "instruction": "Dictate an invitation to a fictional study session with its topic, place, and two possible times.",
    },
    {
        "id": "email-feedback",
        "category": "email",
        "kind": "spontaneous",
        "instruction": "Dictate constructive feedback on a fictional presentation with one strength and two specific improvements.",
    },
    {
        "id": "code-review",
        "category": "technical",
        "kind": "spontaneous",
        "instruction": "Dictate a code-review comment about authentication, validation, and a failing test.",
    },
    {
        "id": "debug-note",
        "category": "technical",
        "kind": "spontaneous",
        "instruction": "Explain a software bug, its likely cause, and the next debugging step.",
    },
    {
        "id": "api-terms",
        "category": "technical",
        "kind": "scripted",
        "instruction": "The API returns HTTP four hundred and one when the bearer token is missing, but it must never log the access token.",
    },
    {
        "id": "deployment-terms",
        "category": "technical",
        "kind": "scripted",
        "instruction": "Do not deploy version two point three until all twelve integration tests pass in the staging environment.",
    },
    {
        "id": "terminal-workflow",
        "category": "technical",
        "kind": "spontaneous",
        "instruction": "Explain a terminal workflow using git status, a feature branch, a test command, and a pull request.",
    },
    {
        "id": "database-migration",
        "category": "technical",
        "kind": "spontaneous",
        "instruction": "Dictate a database-migration note mentioning an index, rollback, schema validation, and a backup.",
    },
    {
        "id": "date-time",
        "category": "numbers-dates",
        "kind": "scripted",
        "instruction": "Schedule the review for Friday the twenty first at three thirty PM, not Thursday at two PM.",
    },
    {
        "id": "money-percent",
        "category": "numbers-dates",
        "kind": "scripted",
        "instruction": "The budget is twenty five thousand rupees, and the final invoice must not exceed fifty percent of that amount.",
    },
    {
        "id": "address-phone",
        "category": "numbers-dates",
        "kind": "spontaneous",
        "instruction": "Dictate a fictional address and phone number. Do not use real personal information.",
    },
    {
        "id": "screen-measurements",
        "category": "numbers-dates",
        "kind": "scripted",
        "instruction": "Set the canvas to one thousand two hundred eighty by seven hundred twenty pixels with a sixteen by nine aspect ratio.",
    },
    {
        "id": "decimal-comparison",
        "category": "numbers-dates",
        "kind": "scripted",
        "instruction": "Version two point zero five used one point seven gigabytes, while version two point one used nine hundred fifty megabytes.",
    },
    {
        "id": "fictional-order",
        "category": "numbers-dates",
        "kind": "spontaneous",
        "instruction": "Dictate a fictional order update containing an order number, quantity, price, delivery date, and time.",
    },
    {
        "id": "negation-list",
        "category": "semantic-safety",
        "kind": "scripted",
        "instruction": "Do not delete the backup, never expose the password, and do not merge without approval.",
    },
    {
        "id": "quantity-repeat",
        "category": "semantic-safety",
        "kind": "scripted",
        "instruction": "We need one one-way switch and one separate two-way switch, not three switches.",
    },
    {
        "id": "permission-negations",
        "category": "semantic-safety",
        "kind": "scripted",
        "instruction": "The guest can view the report but cannot edit it, cannot export it, and must not invite another user.",
    },
    {
        "id": "account-negations",
        "category": "semantic-safety",
        "kind": "scripted",
        "instruction": "The account is not disabled, the payment was not declined, and no refund has been requested.",
    },
    {
        "id": "repeated-quantities",
        "category": "semantic-safety",
        "kind": "scripted",
        "instruction": "Pack two two-litre bottles, four four-inch labels, and one one-page instruction sheet.",
    },
    {
        "id": "quantity-contrast",
        "category": "semantic-safety",
        "kind": "scripted",
        "instruction": "Reserve fourteen seats, not forty seats, and send two reminders, not three.",
    },
    {
        "id": "correction-restart",
        "category": "self-correction",
        "kind": "scripted",
        "instruction": "Create a login page, no wait, a sign-up page using SwiftUI and the new validation rules.",
    },
    {
        "id": "natural-restart",
        "category": "self-correction",
        "kind": "spontaneous",
        "instruction": "Dictate a task, then naturally correct its date, person, or destination mid-sentence.",
    },
    {
        "id": "filler-speech",
        "category": "self-correction",
        "kind": "spontaneous",
        "instruction": "Give a casual status update with your natural pauses, fillers, and one self-correction.",
    },
    {
        "id": "name-correction",
        "category": "self-correction",
        "kind": "scripted",
        "instruction": "Send the draft to Rahul, sorry, send it to Rohan, and ask Meera to review it tomorrow.",
    },
    {
        "id": "number-correction",
        "category": "self-correction",
        "kind": "scripted",
        "instruction": "Order sixteen adapters, actually make that sixty adapters, and deliver them on the ninth.",
    },
    {
        "id": "sentence-restart",
        "category": "self-correction",
        "kind": "spontaneous",
        "instruction": "Begin explaining a fictional plan, stop naturally, restart the sentence, and finish with the corrected plan.",
    },
    {
        "id": "punctuation-email",
        "category": "punctuation",
        "kind": "spontaneous",
        "instruction": "Dictate a three-sentence email and speak any punctuation commands you normally use in ZenVoice.",
    },
    {
        "id": "bullet-list",
        "category": "punctuation",
        "kind": "spontaneous",
        "instruction": "Dictate a heading followed by a three-item task list using your normal layout commands.",
    },
    {
        "id": "quoted-message",
        "category": "punctuation",
        "kind": "spontaneous",
        "instruction": "Dictate a sentence containing a short quotation and parentheses, speaking punctuation commands as you normally would.",
    },
    {
        "id": "url-and-path",
        "category": "punctuation",
        "kind": "spontaneous",
        "instruction": "Dictate a fictional web address and file path, including the punctuation or symbols you normally say aloud.",
    },
    {
        "id": "two-paragraph-note",
        "category": "punctuation",
        "kind": "spontaneous",
        "instruction": "Dictate two short paragraphs and use your normal command for starting the second paragraph.",
    },
    {
        "id": "numbered-steps",
        "category": "punctuation",
        "kind": "spontaneous",
        "instruction": "Dictate a title and four numbered setup steps using the punctuation and layout commands you normally use.",
    },
    {
        "id": "meeting-summary",
        "category": "long-form",
        "kind": "spontaneous",
        "instruction": "Summarize a fictional meeting decision, owner, deadline, and unresolved question in twenty to thirty seconds.",
    },
    {
        "id": "study-note",
        "category": "long-form",
        "kind": "spontaneous",
        "instruction": "Explain a concept you studied today in twenty to thirty seconds without reading prepared prose.",
    },
    {
        "id": "incident-summary",
        "category": "long-form",
        "kind": "spontaneous",
        "instruction": "Describe a fictional software incident, impact, suspected cause, recovery, and follow-up in twenty to thirty seconds.",
    },
    {
        "id": "project-plan",
        "category": "long-form",
        "kind": "spontaneous",
        "instruction": "Explain a fictional one-week project plan with milestones, dependencies, risks, and success criteria in twenty to thirty seconds.",
    },
    {
        "id": "lecture-recap",
        "category": "long-form",
        "kind": "spontaneous",
        "instruction": "Recap a lecture or tutorial topic in twenty to thirty seconds using your own words and one concrete example.",
    },
    {
        "id": "decision-explanation",
        "category": "long-form",
        "kind": "spontaneous",
        "instruction": "Explain a fictional decision, the alternatives considered, the trade-off, and why one option was chosen in twenty to thirty seconds.",
    },
    {
        "id": "fast-message",
        "category": "speaking-rate",
        "kind": "spontaneous",
        "instruction": "Dictate a short message at the fastest pace that still feels natural and understandable.",
    },
    {
        "id": "slow-message",
        "category": "speaking-rate",
        "kind": "spontaneous",
        "instruction": "Dictate a short message slowly with deliberate pauses between clauses.",
    },
    {
        "id": "conversational-message",
        "category": "speaking-rate",
        "kind": "spontaneous",
        "instruction": "Dictate a casual message at your ordinary conversational pace with natural rhythm and pauses.",
    },
    {
        "id": "short-command-burst",
        "category": "speaking-rate",
        "kind": "spontaneous",
        "instruction": "Dictate six short fictional commands in quick succession while keeping every word clear.",
    },
    {
        "id": "mixed-pace-explanation",
        "category": "speaking-rate",
        "kind": "spontaneous",
        "instruction": "Explain a simple task, naturally speeding up for familiar details and slowing down for the important instruction.",
    },
    {
        "id": "hesitant-response",
        "category": "speaking-rate",
        "kind": "spontaneous",
        "instruction": "Answer a fictional planning question with natural thinking pauses, then finish with one clear decision.",
    },
    {
        "id": "indian-names",
        "category": "names-loanwords",
        "kind": "scripted",
        "instruction": "Priya asked Arjun and Aditi to review the Bengaluru launch plan before Diwali.",
    },
    {
        "id": "product-names",
        "category": "names-loanwords",
        "kind": "spontaneous",
        "instruction": "Dictate a technical note containing three product, framework, or library names you genuinely use.",
    },
    {
        "id": "indian-cities",
        "category": "names-loanwords",
        "kind": "scripted",
        "instruction": "The team travelled from Thiruvananthapuram to Kochi, Hyderabad, Pune, and Ahmedabad for the workshop.",
    },
    {
        "id": "acronyms-and-tools",
        "category": "names-loanwords",
        "kind": "spontaneous",
        "instruction": "Dictate a technical update containing three acronyms and three tool names, expanding each acronym once.",
    },
    {
        "id": "hindi-loanwords",
        "category": "names-loanwords",
        "kind": "spontaneous",
        "instruction": "Dictate an English message that naturally includes familiar Hindi words you would genuinely use, without forcing an accent.",
    },
    {
        "id": "course-and-company-names",
        "category": "names-loanwords",
        "kind": "spontaneous",
        "instruction": "Dictate a fictional schedule mentioning two course names, two company or product names, and one person's pseudonymous name.",
    },
    {
        "id": "quiet-room",
        "category": "environment",
        "kind": "spontaneous",
        "instruction": "In a quiet room, dictate a normal message you might send during study or work.",
    },
    {
        "id": "normal-background",
        "category": "environment",
        "kind": "spontaneous",
        "instruction": "With ordinary safe background noise, dictate a normal message without adding artificial noise in software.",
    },
    {
        "id": "laptop-fan",
        "category": "environment",
        "kind": "spontaneous",
        "instruction": "If your laptop fan is naturally audible, dictate a normal study update; otherwise record in your usual room without creating noise.",
    },
    {
        "id": "distant-traffic",
        "category": "environment",
        "kind": "spontaneous",
        "instruction": "If distant traffic is naturally audible from a safe private room, dictate a fictional reminder; otherwise use ordinary room ambience.",
    },
    {
        "id": "alternate-microphone",
        "category": "environment",
        "kind": "spontaneous",
        "instruction": "Using a different microphone available to you, dictate a fictional task update and record the microphone in session metadata.",
    },
    {
        "id": "farther-from-microphone",
        "category": "environment",
        "kind": "spontaneous",
        "instruction": "From a comfortable slightly greater microphone distance, dictate a normal message without raising your voice unnaturally.",
    },
]


def canonical_prompt_pack() -> str:
    return "".join(
        json.dumps(prompt, ensure_ascii=False) + "\n" for prompt in PROMPTS
    )


def prompt_pack_sha256() -> str:
    return hashlib.sha256(canonical_prompt_pack().encode("utf-8")).hexdigest()


def validate_prompt_pack_definition() -> None:
    identifiers = [str(prompt.get("id", "")) for prompt in PROMPTS]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("canonical prompt pack contains duplicate IDs")
    category_counts: dict[str, int] = {}
    for prompt in PROMPTS:
        category = str(prompt.get("category", ""))
        category_counts[category] = category_counts.get(category, 0) + 1
    unexpected = {
        category: count
        for category, count in category_counts.items()
        if count != PROMPTS_PER_CATEGORY
    }
    if len(PROMPTS) != 60 or unexpected:
        raise ValueError(
            "canonical prompt pack must contain exactly 60 prompts and six "
            f"per category; observed {category_counts}"
        )

README = """# Consented ZenVoice Dictation Session

This directory is a local recording session for model research. It is not a
public dataset and must stay below the gitignored `Datasets/` directory.

## Before recording

1. The participant personally reads and edits `consent.json`.
2. Use a pseudonymous participant ID; do not put a name, email, or phone number
   in filenames or metadata.
3. Set every required consent field truthfully. The validator rejects the
   default `false` values.
4. Fill in `session.json`, including microphone and recording environment.

## Recording

- ZenVoice users can enable Audio History, make intentional test dictations,
  then export selected recordings with transcripts included.
- The canonical pack contains 60 prompts, six per required category. Complete
  every prompt you are comfortable contributing; participation remains
  voluntary, and a participant may stop or omit a prompt.
- Extract the export locally and copy only the intentionally contributed WAV
  files into `recordings/`.
- Name each pair after a prompt ID, for example `email-update.wav` and
  `email-update.txt`.
- The `.txt` file must be a verbatim transcript of words actually spoken,
  including fillers, repetitions, and self-corrections. It is not the intended
  prompt and must not be copied from the model output without human review.
- WAV files must be 16 kHz, mono, 16-bit PCM and 0.5–30 seconds long.
- Never record private conversations, bystanders, passwords, access tokens,
  real addresses, health information, or other unnecessary personal data.

## Validation

Run from the ZenVoice repository:

    python3 Scripts/prepare-dictation-corpus.py validate \
      --session-dir Datasets/consented-dictation/<participant>/<session> \
      --output-manifest Datasets/consented-dictation/manifests/<session>.jsonl

Validation is local. It records hashes and permissions but uploads nothing.
Deleting the source session before model merge withdraws it from the next run.
Once weights are released, removing one participant's learned influence may
require retraining; do not promise deletion from already distributed weights.
"""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_inside_datasets(path: Path, repo_root: Path, label: str) -> Path:
    resolved = path.resolve()
    datasets = (repo_root / "Datasets").resolve()
    try:
        resolved.relative_to(datasets)
    except ValueError as error:
        raise ValueError(f"{label} must be inside {datasets}") from error
    return resolved


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def require_identifier(value: Any, label: str) -> str:
    if not isinstance(value, str) or IDENTIFIER.fullmatch(value) is None:
        raise ValueError(
            f"{label} must be 3–64 lowercase letters, numbers, '_' or '-'"
        )
    return value


def require_nonempty(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a non-empty string")
    return " ".join(value.split())


def validate_timestamp(value: Any, label: str) -> str:
    text = require_nonempty(value, label)
    try:
        datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError(f"{label} must be an ISO-8601 timestamp") from error
    return text


def initialize_session(
    directory: Path,
    repo_root: Path,
    participant_id: str | None = None,
    speaker_group_id: str | None = None,
    session_id: str | None = None,
) -> None:
    validate_prompt_pack_definition()
    if participant_id is not None:
        participant_id = require_identifier(participant_id, "participant_id")
    if speaker_group_id is not None:
        speaker_group_id = require_identifier(
            speaker_group_id, "speaker_group_id"
        )
    if session_id is not None:
        session_id = require_identifier(session_id, "session_id")
    participant_value = participant_id or "replace-with-pseudonym"
    speaker_group_value = speaker_group_id or "replace-with-pseudonym"
    session_value = session_id or "replace-with-session-id"
    directory = require_inside_datasets(directory, repo_root, "--output")
    if directory.exists() and any(directory.iterdir()):
        raise ValueError(f"session directory is not empty: {directory}")
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "recordings").mkdir(exist_ok=True)

    consent = {
        "schema_version": 1,
        "consent_text_version": CONSENT_VERSION,
        "participant_id": participant_value,
        "consented_at": "replace-with-ISO-8601-timestamp",
        "participant_is_adult": False,
        "consent_statement_accepted": False,
        "local_training_allowed": False,
        "local_evaluation_allowed": False,
        "redistribution_allowed": False,
    }
    session = {
        "schema_version": 1,
        "participant_id": participant_value,
        "speaker_group_id": speaker_group_value,
        "session_id": session_value,
        "recorded_at": "replace-with-ISO-8601-timestamp",
        "language": "en-IN",
        "accent_self_description": "",
        "microphone": "replace-with-microphone",
        "environment": "replace-with-environment",
        "prompt_pack_sha256": prompt_pack_sha256(),
        "prompt_pack_version": PROMPT_PACK_VERSION,
        "notes": "",
    }
    (directory / "consent.json").write_text(
        json.dumps(consent, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (directory / "session.json").write_text(
        json.dumps(session, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (directory / "prompts.jsonl").write_text(
        canonical_prompt_pack(),
        encoding="utf-8",
        newline="\n",
    )
    (directory / "README.md").write_text(README, encoding="utf-8")
    print(f"Created consented dictation session at {directory}")
    print("Complete consent.json and session.json before recording.")


def refresh_prompt_pack(directory: Path, repo_root: Path) -> None:
    validate_prompt_pack_definition()
    directory = require_inside_datasets(
        directory, repo_root, "--session-dir"
    )
    consent_path = directory / "consent.json"
    session_path = directory / "session.json"
    recordings = directory / "recordings"
    consent = read_json(consent_path)
    if consent.get("consent_statement_accepted") is not False:
        raise ValueError(
            "prompt refresh is allowed only before consent is accepted"
        )
    if recordings.is_dir() and any(recordings.iterdir()):
        raise ValueError("prompt refresh is allowed only before recording")
    session = read_json(session_path)
    session["prompt_pack_version"] = PROMPT_PACK_VERSION
    session["prompt_pack_sha256"] = prompt_pack_sha256()
    session_path.write_text(
        json.dumps(session, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (directory / "prompts.jsonl").write_text(
        canonical_prompt_pack(),
        encoding="utf-8",
        newline="\n",
    )
    (directory / "README.md").write_text(README, encoding="utf-8")
    print(
        f"Refreshed {PROMPT_PACK_VERSION} in {directory}; "
        f"SHA-256 {prompt_pack_sha256()}"
    )


def validate_consent(path: Path) -> tuple[dict[str, Any], str]:
    consent = read_json(path)
    if consent.get("schema_version") != 1:
        raise ValueError("consent.json schema_version must be 1")
    if consent.get("consent_text_version") != CONSENT_VERSION:
        raise ValueError(
            f"consent_text_version must be {CONSENT_VERSION!r}"
        )
    participant = require_identifier(
        consent.get("participant_id"), "consent participant_id"
    )
    validate_timestamp(consent.get("consented_at"), "consented_at")
    for field in (
        "participant_is_adult",
        "consent_statement_accepted",
        "local_training_allowed",
        "local_evaluation_allowed",
    ):
        if consent.get(field) is not True:
            raise ValueError(f"consent field {field} must be explicitly true")
    if consent.get("redistribution_allowed") is not False:
        raise ValueError(
            "this local workflow requires redistribution_allowed=false"
        )
    return consent, participant


def load_prompts(path: Path) -> dict[str, str]:
    validate_prompt_pack_definition()
    prompt_text = path.read_text(encoding="utf-8")
    if prompt_text != canonical_prompt_pack():
        raise ValueError(
            f"prompts.jsonl does not match {PROMPT_PACK_VERSION}"
        )
    prompts: dict[str, str] = {}
    for line_number, line in enumerate(prompt_text.splitlines(), start=1):
        item = json.loads(line)
        prompt_id = require_identifier(
            item.get("id"), f"prompt id at line {line_number}"
        )
        category = require_identifier(
            item.get("category"),
            f"prompt category at line {line_number}",
        )
        if prompt_id in prompts:
            raise ValueError(f"duplicate prompt id: {prompt_id}")
        prompts[prompt_id] = category
    if not prompts:
        raise ValueError("prompts.jsonl is empty")
    return prompts


def inspect_wav(path: Path) -> float:
    with wave.open(str(path), "rb") as reader:
        if (
            reader.getnchannels() != 1
            or reader.getsampwidth() != 2
            or reader.getframerate() != SAMPLE_RATE
        ):
            raise ValueError(f"expected 16 kHz mono 16-bit PCM WAV: {path}")
        duration = reader.getnframes() / reader.getframerate()
    if not MIN_SECONDS <= duration <= MAX_SECONDS:
        raise ValueError(
            f"duration {duration:.2f}s outside {MIN_SECONDS}–{MAX_SECONDS}s: "
            f"{path}"
        )
    return duration


def validate_session(
    directory: Path,
    output_manifest: Path,
    repo_root: Path,
) -> None:
    directory = require_inside_datasets(
        directory, repo_root, "--session-dir"
    )
    output_manifest = require_inside_datasets(
        output_manifest, repo_root, "--output-manifest"
    )
    if output_manifest.exists():
        raise ValueError(f"refusing to overwrite manifest: {output_manifest}")

    consent_path = directory / "consent.json"
    session_path = directory / "session.json"
    prompts_path = directory / "prompts.jsonl"
    for path in (consent_path, session_path, prompts_path):
        if not path.is_file():
            raise ValueError(f"missing session file: {path}")

    _, participant = validate_consent(consent_path)
    session = read_json(session_path)
    if session.get("schema_version") != 1:
        raise ValueError("session.json schema_version must be 1")
    if session.get("participant_id") != participant:
        raise ValueError("session and consent participant_id values differ")
    speaker_group = require_identifier(
        session.get("speaker_group_id"), "speaker_group_id"
    )
    session_id = require_identifier(session.get("session_id"), "session_id")
    recorded_at = validate_timestamp(session.get("recorded_at"), "recorded_at")
    language = require_nonempty(session.get("language"), "language")
    microphone = require_nonempty(session.get("microphone"), "microphone")
    environment = require_nonempty(session.get("environment"), "environment")
    accent = str(session.get("accent_self_description", "")).strip()
    if session.get("prompt_pack_version") != PROMPT_PACK_VERSION:
        raise ValueError(
            f"prompt_pack_version must be {PROMPT_PACK_VERSION!r}"
        )
    if session.get("prompt_pack_sha256") != prompt_pack_sha256():
        raise ValueError("session prompt_pack_sha256 does not match prompt pack")
    prompts = load_prompts(prompts_path)

    recordings = directory / "recordings"
    audio_files = sorted(recordings.glob("*.wav"))
    if not audio_files:
        raise ValueError(f"no WAV recordings found in {recordings}")
    transcript_files = {path.stem: path for path in recordings.glob("*.txt")}
    audio_stems = {path.stem for path in audio_files}
    orphaned = sorted(set(transcript_files) - audio_stems)
    if orphaned:
        raise ValueError(f"orphaned transcript: {orphaned[0]}.txt")

    consent_hash = sha256(consent_path)
    rows: list[dict[str, Any]] = []
    seen_hashes: set[str] = set()
    for audio in audio_files:
        if audio.stem not in prompts:
            raise ValueError(f"recording has unknown prompt id: {audio.stem}")
        transcript_path = transcript_files.get(audio.stem)
        if transcript_path is None:
            raise ValueError(f"missing verbatim transcript for {audio.name}")
        transcript = " ".join(
            transcript_path.read_text(encoding="utf-8").split()
        )
        if not transcript:
            raise ValueError(f"empty transcript: {transcript_path}")
        audio_hash = sha256(audio)
        if audio_hash in seen_hashes:
            raise ValueError(f"duplicate audio in session: {audio.name}")
        seen_hashes.add(audio_hash)
        rows.append(
            {
                "audio": str(audio.resolve().relative_to(repo_root)),
                "text": transcript,
                "duration_seconds": round(inspect_wav(audio), 3),
                "source": "consented ZenVoice dictation",
                "license": "private-consent-local-only",
                "participant_id": participant,
                "speaker_group_id": speaker_group,
                "session_id": session_id,
                "recorded_at": recorded_at,
                "language": language,
                "accent_self_description": accent,
                "microphone": microphone,
                "environment": environment,
                "prompt_pack_version": PROMPT_PACK_VERSION,
                "prompt_pack_sha256": prompt_pack_sha256(),
                "session_sha256": sha256(session_path),
                "category": prompts[audio.stem],
                "prompt_id": audio.stem,
                "consent_sha256": consent_hash,
                "audio_sha256": audio_hash,
                "transcript_sha256": sha256(transcript_path),
                "local_training_allowed": True,
                "local_evaluation_allowed": True,
                "redistribution_allowed": False,
            }
        )

    output_manifest.parent.mkdir(parents=True, exist_ok=True)
    with output_manifest.open("x", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    hours = sum(row["duration_seconds"] for row in rows) / 3600
    print(
        f"Validated {len(rows)} clips ({hours:.3f} h) from {session_id}; "
        f"manifest: {output_manifest}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    initialize = commands.add_parser("init", help="create an empty session")
    initialize.add_argument("--output", type=Path, required=True)
    initialize.add_argument("--participant-id")
    initialize.add_argument("--speaker-group-id")
    initialize.add_argument("--session-id")
    refresh = commands.add_parser(
        "refresh-prompts",
        help="refresh an empty unconsented session to the canonical prompt pack",
    )
    refresh.add_argument("--session-dir", type=Path, required=True)
    validate = commands.add_parser("validate", help="validate a session")
    validate.add_argument("--session-dir", type=Path, required=True)
    validate.add_argument("--output-manifest", type=Path, required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    if args.command == "init":
        identity_values = (
            args.participant_id,
            args.speaker_group_id,
            args.session_id,
        )
        if any(value is not None for value in identity_values) and not all(
            value is not None for value in identity_values
        ):
            parser.error(
                "--participant-id, --speaker-group-id, and --session-id "
                "must be supplied together"
            )
        initialize_session(
            args.output,
            repo_root,
            args.participant_id,
            args.speaker_group_id,
            args.session_id,
        )
    elif args.command == "refresh-prompts":
        refresh_prompt_pack(args.session_dir, repo_root)
    else:
        validate_session(args.session_dir, args.output_manifest, repo_root)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, wave.Error, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
