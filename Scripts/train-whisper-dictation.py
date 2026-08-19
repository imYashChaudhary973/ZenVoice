#!/usr/bin/env python3
"""Fine-tune Whisper Small English for ZenVoice with a local LoRA adapter.

This script never downloads a model implicitly and never uploads checkpoints.
Pass a revision-pinned local Hugging Face model directory plus manifests created
by the ZenVoice data tools. A locked-dataset run verifies either consented
dictation or an approved public spontaneous-speech corpus, mixes that target
speech with explicitly supplied licensed general speech, uses conservative
defaults, and preserves candidate adapters for later composite selection. It
does not merge or promote a candidate automatically.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import random
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import torch
from peft import LoraConfig, get_peft_model
from torch.utils.data import Dataset
from transformers import (
    Seq2SeqTrainer,
    Seq2SeqTrainingArguments,
    WhisperForConditionalGeneration,
    WhisperProcessor,
    set_seed,
)


SAMPLE_RATE = 16_000
CONSENTED_LOCK_NAME = "FROZEN_TEST_LOCK.json"
PUBLIC_LOCK_NAME = "PUBLIC_CORPUS_LOCK.json"


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_manifest(
    path: Path,
    repo_root: Path,
    approved_licenses: set[str] | None = None,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            audio = (repo_root / row["audio"]).resolve()
            try:
                audio.relative_to(repo_root)
            except ValueError as error:
                raise ValueError(
                    f"manifest audio escapes repository at line {line_number}"
                ) from error
            if not audio.is_file():
                raise ValueError(f"missing audio at line {line_number}: {audio}")
            text = " ".join(str(row["text"]).split())
            if not text:
                raise ValueError(f"empty text at line {line_number}")
            actual_audio_hash = file_sha256(audio)
            declared_hash = row.get("audio_sha256")
            if declared_hash is not None and declared_hash != actual_audio_hash:
                raise ValueError(
                    f"audio hash changed at line {line_number}: {audio}"
                )
            source = row.get("source")
            license_name = row.get("license")
            if approved_licenses is not None:
                if not isinstance(source, str) or not source.strip():
                    raise ValueError(
                        f"general speech source missing at line {line_number}"
                    )
                if license_name not in approved_licenses:
                    raise ValueError(
                        f"general speech license {license_name!r} is not "
                        f"approved at line {line_number}"
                    )
            rows.append(
                {
                    "audio": audio,
                    "text": text,
                    "audio_sha256": actual_audio_hash,
                    "source": source,
                    "license": license_name,
                }
            )
    if not rows:
        raise ValueError(f"empty manifest: {path}")
    return rows


def verify_locked_dataset(directory: Path) -> dict[str, Any]:
    lock_candidates = [
        name
        for name in (CONSENTED_LOCK_NAME, PUBLIC_LOCK_NAME)
        if (directory / name).is_file()
    ]
    if len(lock_candidates) != 1:
        raise ValueError(
            f"expected exactly one supported dataset lock in {directory}"
        )
    lock_name = lock_candidates[0]
    lock_path = directory / lock_name
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    if not isinstance(lock, dict) or lock.get("schema_version") != 1:
        raise ValueError(f"invalid frozen dataset lock: {lock_path}")
    artifacts = lock.get("immutable_artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        raise ValueError(f"lock contains no immutable artifacts: {lock_path}")
    for name, expected in artifacts.items():
        if not isinstance(name, str) or Path(name).name != name:
            raise ValueError(f"invalid locked artifact name: {name!r}")
        path = directory / name
        if not path.is_file() or file_sha256(path) != expected:
            raise ValueError(f"locked dataset artifact changed: {path}")
    test_manifest = directory / "test.jsonl"
    expected_test_hash = (
        lock.get("frozen_test_sha256")
        if lock_name == CONSENTED_LOCK_NAME
        else lock.get("held_out_test_sha256")
    )
    if file_sha256(test_manifest) != expected_test_hash:
        raise ValueError("frozen test manifest hash changed")
    if lock_name == PUBLIC_LOCK_NAME:
        validation_manifest = directory / "validation.jsonl"
        if (
            file_sha256(validation_manifest)
            != lock.get("held_out_validation_sha256")
        ):
            raise ValueError("held-out validation manifest hash changed")
    summary_path = directory / "summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if lock_name == CONSENTED_LOCK_NAME:
        representativeness = (
            summary.get("representativeness")
            if isinstance(summary, dict)
            else None
        )
        if (
            not isinstance(representativeness, dict)
            or representativeness.get("passed") is not True
            or representativeness.get("failures") != []
        ):
            raise ValueError(
                "locked dataset lacks passing representativeness evidence"
            )
        dataset_kind = "consented-zenvoice-dictation"
        representative_dictation = True
    else:
        coverage = summary.get("coverage") if isinstance(summary, dict) else None
        if (
            not isinstance(coverage, dict)
            or coverage.get("passed") is not True
            or coverage.get("failures") != []
            or summary.get("dataset_kind")
            != "public-spontaneous-speech-supplement"
            or summary.get("representative_zenvoice_dictation") is not False
        ):
            raise ValueError("locked public corpus lacks passing coverage evidence")
        provenance_path = directory / "provenance.json"
        provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
        if (
            not isinstance(provenance, dict)
            or provenance.get("schema_version") != 1
            or provenance.get("representative_dictation") is not False
            or provenance.get("redistribution_review")
            not in {"pending", "approved", "prohibited"}
        ):
            raise ValueError("locked public corpus has invalid provenance")
        archive_value = provenance.get("archive")
        review_value = provenance.get("license_review")
        if not isinstance(archive_value, str) or not isinstance(review_value, str):
            raise ValueError("locked public corpus lacks archive or review provenance")
        repo_root = Path(__file__).resolve().parent.parent
        datasets_root = (repo_root / "Datasets").resolve()
        archive = (repo_root / archive_value).resolve()
        review_path = (repo_root / review_value).resolve()
        for path, label in ((archive, "archive"), (review_path, "license review")):
            try:
                path.relative_to(datasets_root)
            except ValueError as error:
                raise ValueError(f"public corpus {label} escapes Datasets") from error
        if (
            not archive.is_file()
            or file_sha256(archive) != provenance.get("archive_sha256")
            or not review_path.is_file()
            or file_sha256(review_path) != provenance.get("license_review_sha256")
        ):
            raise ValueError("locked public corpus source provenance changed")
        review = json.loads(review_path.read_text(encoding="utf-8"))
        if (
            not isinstance(review, dict)
            or review.get("dataset_access_terms_accepted") is not True
            or review.get("license_approved_for_local_training") is not True
            or review.get("license") != provenance.get("license")
            or review.get("archive_sha256") != provenance.get("archive_sha256")
        ):
            raise ValueError("locked public corpus lacks approved human review")
        dataset_kind = "public-spontaneous-speech-supplement"
        representative_dictation = False
    lock["verified_lock_name"] = lock_name
    lock["frozen_test_sha256"] = expected_test_hash
    lock["dataset_kind"] = dataset_kind
    lock["representative_zenvoice_dictation"] = representative_dictation
    return lock


def verify_general_provenance(
    manifest: Path,
    repo_root: Path,
    approved_licenses: set[str],
) -> dict[str, Any]:
    provenance_path = manifest.parent / "provenance.json"
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    if not isinstance(provenance, dict) or provenance.get("schema_version") != 1:
        raise ValueError(f"invalid general-speech provenance: {provenance_path}")
    if provenance.get("manifest") != manifest.name:
        raise ValueError(f"provenance identifies another manifest: {manifest}")
    if provenance.get("manifest_sha256") != file_sha256(manifest):
        raise ValueError(f"general-speech manifest changed: {manifest}")
    if provenance.get("license") not in approved_licenses:
        raise ValueError(f"general-speech license is not approved: {manifest}")
    for key in (
        "source",
        "publisher",
        "source_url",
        "source_landing_page",
        "license_url",
        "required_attribution",
    ):
        value = provenance.get(key)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"general-speech provenance lacks {key}: {manifest}")
    if provenance.get("representative_dictation") is not False:
        raise ValueError(
            f"general speech must not claim to be representative dictation: {manifest}"
        )
    if provenance.get("redistribution_review") not in {
        "pending",
        "approved",
        "prohibited",
    }:
        raise ValueError(f"invalid redistribution review state: {manifest}")
    archive_value = provenance.get("archive")
    archive_hash = provenance.get("archive_sha256")
    if not isinstance(archive_value, str) or not isinstance(archive_hash, str):
        raise ValueError(f"general-speech archive provenance is missing: {manifest}")
    archive = (repo_root / archive_value).resolve()
    try:
        archive.relative_to((repo_root / "Datasets").resolve())
    except ValueError as error:
        raise ValueError("general-speech archive escapes Datasets") from error
    if not archive.is_file() or file_sha256(archive) != archive_hash:
        raise ValueError(f"general-speech source archive changed: {archive}")
    provenance["provenance_path"] = str(provenance_path.relative_to(repo_root))
    provenance["provenance_sha256"] = file_sha256(provenance_path)
    return provenance


def mix_training_rows(
    dictation_rows: list[dict[str, Any]],
    general_rows: list[dict[str, Any]],
    dictation_repeat: int,
    seed: int,
) -> list[dict[str, Any]]:
    if dictation_repeat < 1:
        raise ValueError("--dictation-repeat must be at least 1")
    dictation_audio = {row["audio_sha256"] for row in dictation_rows}
    general_audio = {row["audio_sha256"] for row in general_rows}
    overlap = dictation_audio & general_audio
    if overlap:
        raise ValueError(
            f"dictation and general training data overlap: {next(iter(overlap))}"
        )
    if len(general_audio) != len(general_rows):
        raise ValueError("general training manifests contain duplicate audio")
    mixed = dictation_rows * dictation_repeat + general_rows
    random.Random(seed).shuffle(mixed)
    return mixed


def load_pcm16_mono(path: Path) -> np.ndarray:
    if path.suffix.lower() == ".flac":
        try:
            import soundfile as sf
        except ImportError as error:
            raise ValueError(
                "FLAC training audio requires the soundfile package"
            ) from error
        samples, sample_rate = sf.read(
            path,
            dtype="float32",
            always_2d=False,
        )
        if sample_rate != SAMPLE_RATE or samples.ndim != 1:
            raise ValueError(f"expected 16 kHz mono FLAC: {path}")
        return np.asarray(samples, dtype=np.float32)
    with wave.open(str(path), "rb") as reader:
        if (
            reader.getnchannels() != 1
            or reader.getsampwidth() != 2
            or reader.getframerate() != SAMPLE_RATE
        ):
            raise ValueError(f"expected 16 kHz mono 16-bit PCM WAV: {path}")
        frames = reader.readframes(reader.getnframes())
    return np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0


class WhisperManifestDataset(Dataset):
    def __init__(
        self,
        rows: list[dict[str, Any]],
        processor: WhisperProcessor,
        max_label_length: int,
    ) -> None:
        self.rows = rows
        self.processor = processor
        self.max_label_length = max_label_length

    def __len__(self) -> int:
        return len(self.rows)

    def __getitem__(self, index: int) -> dict[str, Any]:
        row = self.rows[index]
        samples = load_pcm16_mono(row["audio"])
        features = self.processor.feature_extractor(
            samples,
            sampling_rate=SAMPLE_RATE,
            return_tensors="np",
        ).input_features[0]
        labels = self.processor.tokenizer(
            row["text"],
            add_special_tokens=True,
        ).input_ids
        if len(labels) > self.max_label_length:
            raise ValueError(
                f"transcript has {len(labels)} tokens; maximum is "
                f"{self.max_label_length}: {row['audio']}"
            )
        return {"input_features": features, "labels": labels}


@dataclass
class WhisperDataCollator:
    processor: WhisperProcessor
    decoder_start_token_id: int

    def __call__(self, features: list[dict[str, Any]]) -> dict[str, torch.Tensor]:
        inputs = [
            {"input_features": feature["input_features"]}
            for feature in features
        ]
        batch = self.processor.feature_extractor.pad(
            inputs,
            return_tensors="pt",
        )
        label_features = [
            {"input_ids": feature["labels"]}
            for feature in features
        ]
        labels_batch = self.processor.tokenizer.pad(
            label_features,
            return_tensors="pt",
        )
        labels = labels_batch["input_ids"].masked_fill(
            labels_batch["attention_mask"].ne(1),
            -100,
        )
        if (
            labels.shape[1] > 0
            and torch.all(labels[:, 0] == self.decoder_start_token_id)
        ):
            labels = labels[:, 1:]
        batch["labels"] = labels
        return batch


def bounded_rows(
    rows: list[dict[str, Any]],
    limit: int | None,
    seed: int,
) -> list[dict[str, Any]]:
    if limit is None or limit >= len(rows):
        return rows
    selected = list(rows)
    random.Random(seed).shuffle(selected)
    return selected[:limit]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--model-revision", required=True)
    parser.add_argument("--train-manifest", type=Path)
    parser.add_argument("--validation-manifest", type=Path)
    parser.add_argument(
        "--locked-dataset-dir",
        type=Path,
        help="checksum-locked target-speech dataset; enables conservative mode",
    )
    parser.add_argument(
        "--general-train-manifest",
        type=Path,
        action="append",
        default=[],
        help="licensed general-speech training manifest; repeatable",
    )
    parser.add_argument(
        "--approved-general-license",
        action="append",
        default=[],
        help="exact reviewed license identifier; repeatable",
    )
    parser.add_argument("--dictation-repeat", type=int, default=2)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--epochs", type=float)
    parser.add_argument("--learning-rate", type=float)
    parser.add_argument("--batch-size", type=int, default=1)
    parser.add_argument("--gradient-accumulation", type=int, default=8)
    parser.add_argument("--lora-rank", type=int, default=16)
    parser.add_argument("--lora-alpha", type=int, default=32)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--max-train-samples", type=int)
    parser.add_argument("--max-validation-samples", type=int)
    parser.add_argument(
        "--validate-inputs-only",
        action="store_true",
        help="verify all manifests, licenses, hashes, and overlap without training",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    model_dir = args.model_dir.resolve()
    output = args.output_dir.resolve()
    datasets_root = (repo_root / "Datasets").resolve()
    for path, label in [(model_dir, "--model-dir"), (output, "--output-dir")]:
        try:
            path.relative_to(datasets_root)
        except ValueError:
            parser.error(f"{label} must be inside the gitignored Datasets directory")
    if output.exists() and any(output.iterdir()):
        parser.error("--output-dir must be empty or absent")

    conservative_mode = args.locked_dataset_dir is not None
    locked_dataset: Path | None = None
    frozen_lock: dict[str, Any] | None = None
    if conservative_mode:
        if args.train_manifest is not None or args.validation_manifest is not None:
            parser.error(
                "do not combine --locked-dataset-dir with explicit train or "
                "validation manifests"
            )
        if not args.general_train_manifest:
            parser.error(
                "conservative mode requires at least one "
                "--general-train-manifest"
            )
        if not args.approved_general_license:
            parser.error(
                "conservative mode requires at least one exact "
                "--approved-general-license"
            )
        locked_dataset = args.locked_dataset_dir.resolve()
        try:
            locked_dataset.relative_to(datasets_root)
        except ValueError:
            parser.error("--locked-dataset-dir must be inside Datasets")
        frozen_lock = verify_locked_dataset(locked_dataset)
        train_manifest = locked_dataset / "train.jsonl"
        validation_manifest = locked_dataset / "validation.jsonl"
    else:
        if args.train_manifest is None or args.validation_manifest is None:
            parser.error(
                "legacy mode requires --train-manifest and "
                "--validation-manifest"
            )
        if args.general_train_manifest:
            parser.error(
                "--general-train-manifest requires --locked-dataset-dir"
            )
        if args.approved_general_license:
            parser.error(
                "--approved-general-license requires --locked-dataset-dir"
            )
        train_manifest = args.train_manifest.resolve()
        validation_manifest = args.validation_manifest.resolve()

    for manifest, label in [
        (train_manifest, "training manifest"),
        (validation_manifest, "validation manifest"),
        *[
            (path.resolve(), "general training manifest")
            for path in args.general_train_manifest
        ],
    ]:
        try:
            manifest.relative_to(datasets_root)
        except ValueError:
            parser.error(f"{label} must be inside Datasets")
        if not manifest.is_file():
            parser.error(f"{label} not found: {manifest}")

    epochs = args.epochs if args.epochs is not None else (
        2.0 if conservative_mode else 3.0
    )
    learning_rate = (
        args.learning_rate
        if args.learning_rate is not None
        else (5e-5 if conservative_mode else 1e-4)
    )

    dictation_train_rows = bounded_rows(
        read_manifest(train_manifest, repo_root),
        args.max_train_samples,
        args.seed,
    )
    approved_licenses = set(args.approved_general_license)
    general_provenance: list[dict[str, Any]] = []
    general_train_rows: list[dict[str, Any]] = []
    for general_manifest_argument in args.general_train_manifest:
        general_manifest = general_manifest_argument.resolve()
        provenance = verify_general_provenance(
            general_manifest,
            repo_root,
            approved_licenses,
        )
        rows = read_manifest(
            general_manifest,
            repo_root,
            approved_licenses=approved_licenses,
        )
        if any(
            row["source"] != provenance["source"]
            or row["license"] != provenance["license"]
            for row in rows
        ):
            raise ValueError(
                f"general manifest rows do not match provenance: {general_manifest}"
            )
        general_provenance.append(provenance)
        general_train_rows.extend(rows)
    if conservative_mode and locked_dataset is not None:
        locked_hashes = {
            row["audio_sha256"]
            for split_name in ("train", "validation", "test")
            for row in read_manifest(
                locked_dataset / f"{split_name}.jsonl",
                repo_root,
            )
        }
        leaked_hashes = locked_hashes & {
            row["audio_sha256"] for row in general_train_rows
        }
        if leaked_hashes:
            raise ValueError(
                "general training speech overlaps a locked dictation split"
            )
    train_rows = mix_training_rows(
        dictation_train_rows,
        general_train_rows,
        args.dictation_repeat if conservative_mode else 1,
        args.seed,
    )
    validation_rows = bounded_rows(
        read_manifest(validation_manifest, repo_root),
        args.max_validation_samples,
        args.seed,
    )
    if args.validate_inputs_only:
        validation = {
            "schema_version": 1,
            "status": "inputs-valid",
            "locked_dataset": (
                str(locked_dataset.relative_to(repo_root))
                if locked_dataset is not None
                else None
            ),
            "frozen_test_sha256": (
                frozen_lock.get("frozen_test_sha256")
                if frozen_lock is not None
                else None
            ),
            "locked_dataset_kind": (
                frozen_lock.get("dataset_kind")
                if frozen_lock is not None
                else None
            ),
            "representative_zenvoice_dictation": (
                frozen_lock.get("representative_zenvoice_dictation")
                if frozen_lock is not None
                else None
            ),
            "dictation_train_samples": len(dictation_train_rows),
            "general_train_samples": len(general_train_rows),
            "mixed_train_samples": len(train_rows),
            "validation_samples": len(validation_rows),
            "general_sources": [
                {
                    "source": item["source"],
                    "license": item["license"],
                    "manifest_sha256": item["manifest_sha256"],
                    "provenance_sha256": item["provenance_sha256"],
                    "redistribution_review": item["redistribution_review"],
                }
                for item in general_provenance
            ],
        }
        print(json.dumps(validation, indent=2, sort_keys=True))
        return 0

    set_seed(args.seed)
    processor = WhisperProcessor.from_pretrained(
        model_dir,
        local_files_only=True,
        trust_remote_code=False,
    )
    model = WhisperForConditionalGeneration.from_pretrained(
        model_dir,
        local_files_only=True,
        trust_remote_code=False,
        dtype=torch.float32,
    )
    model.config.use_cache = False

    train_dataset = WhisperManifestDataset(
        train_rows,
        processor,
        model.config.max_target_positions,
    )
    validation_dataset = WhisperManifestDataset(
        validation_rows,
        processor,
        model.config.max_target_positions,
    )

    lora = LoraConfig(
        r=args.lora_rank,
        lora_alpha=args.lora_alpha,
        lora_dropout=0.05,
        bias="none",
        target_modules=["q_proj", "v_proj"],
    )
    model = get_peft_model(model, lora)
    model.print_trainable_parameters()

    output.mkdir(parents=True, exist_ok=True)
    training_args = Seq2SeqTrainingArguments(
        output_dir=str(output / "checkpoints"),
        overwrite_output_dir=False,
        do_train=True,
        do_eval=True,
        eval_strategy="epoch",
        save_strategy="epoch",
        logging_strategy="steps",
        logging_steps=10,
        logging_first_step=True,
        per_device_train_batch_size=args.batch_size,
        per_device_eval_batch_size=1,
        gradient_accumulation_steps=args.gradient_accumulation,
        learning_rate=learning_rate,
        warmup_ratio=0.05,
        num_train_epochs=epochs,
        optim="adamw_torch",
        save_total_limit=None if conservative_mode else 2,
        load_best_model_at_end=not conservative_mode,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        remove_unused_columns=False,
        label_names=["labels"],
        report_to=[],
        push_to_hub=False,
        dataloader_num_workers=0,
        dataloader_pin_memory=False,
        fp16=False,
        bf16=False,
        seed=args.seed,
        data_seed=args.seed,
    )
    trainer = Seq2SeqTrainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=validation_dataset,
        data_collator=WhisperDataCollator(
            processor,
            model.config.decoder_start_token_id,
        ),
    )
    result = trainer.train()

    adapter_dir = output / (
        "final-unselected-adapter" if conservative_mode else "adapter"
    )
    trainer.model.save_pretrained(adapter_dir, safe_serialization=True)
    processor.save_pretrained(adapter_dir)

    if not conservative_mode:
        merged_dir = output / "merged"
        trainer.model.to("cpu")
        merged = trainer.model.merge_and_unload()
        merged.config.use_cache = True
        merged.save_pretrained(merged_dir, safe_serialization=True)
        processor.save_pretrained(merged_dir)

    provenance = {
        "schema_version": 1,
        "base_model": "openai/whisper-small.en",
        "base_revision": args.model_revision,
        "base_model_sha256": file_sha256(model_dir / "model.safetensors"),
        "base_model_license": "Apache-2.0",
        "training_method": (
            "LoRA candidates; merge deferred pending composite selection"
            if conservative_mode
            else "LoRA merged into base checkpoint"
        ),
        "selection_required": conservative_mode,
        "merged_model_written": not conservative_mode,
        "lora": {
            "rank": args.lora_rank,
            "alpha": args.lora_alpha,
            "dropout": 0.05,
            "target_modules": ["q_proj", "v_proj"],
        },
        "dictation_train_manifest": {
            "path": str(train_manifest.relative_to(repo_root)),
            "sha256": file_sha256(train_manifest),
            "unique_samples": len(dictation_train_rows),
            "repeat": args.dictation_repeat if conservative_mode else 1,
        },
        "general_train_manifests": [
            {
                "path": str(path.resolve().relative_to(repo_root)),
                "sha256": file_sha256(path.resolve()),
            }
            for path in args.general_train_manifest
        ],
        "approved_general_licenses": sorted(
            set(args.approved_general_license)
        ),
        "general_training_sources": sorted(
            {
                f"{row['source']} ({row['license']})"
                for row in general_train_rows
            }
        ),
        "general_source_provenance": [
            {
                "source": item["source"],
                "publisher": item["publisher"],
                "license": item["license"],
                "license_url": item["license_url"],
                "required_attribution": item["required_attribution"],
                "manifest_sha256": item["manifest_sha256"],
                "archive_sha256": item["archive_sha256"],
                "provenance_path": item["provenance_path"],
                "provenance_sha256": item["provenance_sha256"],
                "redistribution_review": item["redistribution_review"],
            }
            for item in general_provenance
        ],
        "mixed_train_samples": len(train_rows),
        "validation_manifest": {
            "path": str(validation_manifest.relative_to(repo_root)),
            "sha256": file_sha256(validation_manifest),
            "samples": len(validation_rows),
        },
        "locked_dataset": (
            {
                "path": str(locked_dataset.relative_to(repo_root)),
                "lock_name": frozen_lock["verified_lock_name"],
                "lock_sha256": file_sha256(
                    locked_dataset / frozen_lock["verified_lock_name"]
                ),
                "frozen_test_sha256": frozen_lock["frozen_test_sha256"],
                "dataset_kind": frozen_lock["dataset_kind"],
                "representative_zenvoice_dictation": frozen_lock[
                    "representative_zenvoice_dictation"
                ],
            }
            if locked_dataset is not None and frozen_lock is not None
            else None
        ),
        "seed": args.seed,
        "epochs": epochs,
        "learning_rate": learning_rate,
        "device": str(trainer.args.device),
        "software": {
            name: importlib.metadata.version(name)
            for name in ("torch", "transformers", "peft", "accelerate")
        },
        "train_result": {
            key: value
            for key, value in result.metrics.items()
                if isinstance(value, (int, float, str, bool))
        },
        "best_validation_loss": trainer.state.best_metric,
        "best_model_checkpoint": trainer.state.best_model_checkpoint,
        "evaluation_history": [
            entry
            for entry in trainer.state.log_history
            if "eval_loss" in entry
        ],
    }
    (output / "training-result.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(provenance, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, wave.Error, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
