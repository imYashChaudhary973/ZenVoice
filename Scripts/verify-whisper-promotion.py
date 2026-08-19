#!/usr/bin/env python3
"""Authorize a selected Q5 artifact for catalog promotion only if all gates pass.

This verifier writes local approval evidence; it does not upload a model or edit
VerifiedModelCatalog. A stable HTTPS source, human redistribution review,
license/attribution review, exact artifact checksum, and the all-gates
checkpoint decision must agree before promotion_authorized can become true.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def require_inside_datasets(path: Path, repo_root: Path, label: str) -> Path:
    resolved = path.resolve()
    datasets = (repo_root / "Datasets").resolve()
    try:
        resolved.relative_to(datasets)
    except ValueError as error:
        raise ValueError(f"{label} must be inside {datasets}") from error
    return resolved


def require_https(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{label} must be an HTTPS URL")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username:
        raise ValueError(f"{label} must be an HTTPS URL without credentials")
    return value


def require_review_identity(review: dict[str, Any], label: str) -> None:
    reviewer = review.get("reviewed_by")
    reviewed_at = review.get("reviewed_at")
    if not isinstance(reviewer, str) or not reviewer.strip():
        raise ValueError(f"{label} reviewed_by is missing")
    if not isinstance(reviewed_at, str):
        raise ValueError(f"{label} reviewed_at is missing")
    try:
        datetime.fromisoformat(reviewed_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError(f"{label} reviewed_at is not ISO-8601") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selection-decision", type=Path, required=True)
    parser.add_argument("--artifact-inventory", type=Path, required=True)
    parser.add_argument("--license-review", type=Path, required=True)
    parser.add_argument("--distribution-review", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    decision_path = require_inside_datasets(
        args.selection_decision, repo_root, "--selection-decision"
    )
    inventory_path = require_inside_datasets(
        args.artifact_inventory, repo_root, "--artifact-inventory"
    )
    license_path = require_inside_datasets(
        args.license_review, repo_root, "--license-review"
    )
    distribution_path = require_inside_datasets(
        args.distribution_review, repo_root, "--distribution-review"
    )
    output = require_inside_datasets(args.output, repo_root, "--output")
    if output.exists():
        parser.error(f"refusing to overwrite promotion evidence: {output}")

    decision = read_json(decision_path)
    if decision.get("schema_version") != 1:
        raise ValueError("selection decision schema_version must be 1")
    selected = decision.get("selected")
    if not isinstance(selected, dict) or selected.get("passes_all_gates") is not True:
        raise ValueError("selection decision has no all-gates checkpoint")
    gates = selected.get("gates")
    if not isinstance(gates, dict) or not gates or not all(gates.values()):
        raise ValueError("selected checkpoint does not pass every gate")

    inventory = read_json(inventory_path)
    if inventory.get("schema_version") != 1:
        raise ValueError("artifact inventory schema_version must be 1")
    selection = inventory.get("selection")
    if not isinstance(selection, dict):
        raise ValueError("artifact was not quantized from a selected merge")
    if selection.get("selection_decision_sha256") != sha256(decision_path):
        raise ValueError("artifact inventory identifies another selection decision")
    if selection.get("checkpoint_id") != selected.get("checkpoint_id"):
        raise ValueError("artifact inventory identifies another checkpoint")
    if selection.get("frozen_test_sha256") != decision.get("frozen_test_sha256"):
        raise ValueError("artifact inventory identifies another frozen test")
    artifacts = inventory.get("artifacts")
    q5 = artifacts.get("q5_0") if isinstance(artifacts, dict) else None
    if not isinstance(q5, dict):
        raise ValueError("artifact inventory contains no Q5 model")
    q5_path = inventory_path.parent / str(q5.get("path", ""))
    if q5_path.parent.resolve() != inventory_path.parent.resolve():
        raise ValueError("Q5 artifact path escapes inventory directory")
    if not q5_path.is_file() or sha256(q5_path) != q5.get("sha256"):
        raise ValueError("Q5 artifact changed after quantization")
    if q5_path.stat().st_size != q5.get("bytes"):
        raise ValueError("Q5 artifact size does not match inventory")
    selected_q5_bytes = selected.get("metrics", {}).get("q5_model_bytes")
    if (
        not isinstance(selected_q5_bytes, (int, float))
        or not math.isfinite(float(selected_q5_bytes))
        or abs(float(selected_q5_bytes) - q5_path.stat().st_size)
        > max(1024.0, q5_path.stat().st_size * 0.02)
    ):
        raise ValueError("final Q5 size differs from the evaluated candidate")

    license_review = read_json(license_path)
    if license_review.get("schema_version") != 1:
        raise ValueError("license review schema_version must be 1")
    if (
        license_review.get("approved") is not True
        or license_review.get("attribution_recorded") is not True
    ):
        raise ValueError("license and attribution review is not approved")
    require_review_identity(license_review, "license review")
    licenses = license_review.get("licenses")
    attribution = license_review.get("attribution_notice")
    if not isinstance(licenses, list) or not licenses:
        raise ValueError("license review contains no licenses")
    if not isinstance(attribution, str) or not attribution.strip():
        raise ValueError("license review contains no attribution notice")

    distribution = read_json(distribution_path)
    if distribution.get("schema_version") != 1:
        raise ValueError("distribution review schema_version must be 1")
    if (
        distribution.get("approved") is not True
        or distribution.get("redistribution_allowed") is not True
    ):
        raise ValueError("redistribution review is not approved")
    require_review_identity(distribution, "distribution review")
    download_url = require_https(
        distribution.get("stable_download_url"), "stable_download_url"
    )
    require_https(distribution.get("model_card_url"), "model_card_url")
    if distribution.get("artifact_sha256") != q5.get("sha256"):
        raise ValueError("distribution review checksum does not match Q5 artifact")
    if distribution.get("artifact_bytes") != q5.get("bytes"):
        raise ValueError("distribution review size does not match Q5 artifact")

    approval = {
        "schema_version": 1,
        "promotion_authorized": True,
        "checkpoint_id": selected["checkpoint_id"],
        "frozen_test_sha256": decision["frozen_test_sha256"],
        "selection_decision": str(decision_path.relative_to(repo_root)),
        "selection_decision_sha256": sha256(decision_path),
        "artifact_inventory": str(inventory_path.relative_to(repo_root)),
        "artifact_inventory_sha256": sha256(inventory_path),
        "q5_artifact": str(q5_path.relative_to(repo_root)),
        "q5_sha256": q5["sha256"],
        "q5_bytes": q5["bytes"],
        "license_review": str(license_path.relative_to(repo_root)),
        "license_review_sha256": sha256(license_path),
        "distribution_review": str(distribution_path.relative_to(repo_root)),
        "distribution_review_sha256": sha256(distribution_path),
        "stable_download_url": download_url,
        "all_selection_gates": gates,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(approval, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(approval, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
