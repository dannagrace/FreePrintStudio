#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path
import re
import sys

FASTFILE = Path("fastlane/Fastfile")
failures = []


def fail(message: str) -> None:
    failures.append(message)


def lane_body(source: str, lane_name: str) -> str:
    marker = re.search(rf"^\s*lane\s+:{re.escape(lane_name)}\s+do\b", source, re.M)
    if not marker:
        fail(f"fastlane/Fastfile is missing lane :{lane_name}")
        return ""

    index = marker.end()
    depth = 1
    token_pattern = re.compile(r"\b(do|end)\b")
    while True:
        token = token_pattern.search(source, index)
        if not token:
            fail(f"fastlane/Fastfile lane :{lane_name} is not closed")
            return source[marker.end():]

        if token.group(1) == "do":
            depth += 1
        else:
            depth -= 1
            if depth == 0:
                return source[marker.end():token.start()]
        index = token.end()


def index_of(body: str, pattern: str) -> int:
    index = body.find(pattern)
    if index == -1:
        fail(f"lane is missing {pattern}")
    return index


def require_before(lane_name: str, body: str, earlier: str, later: str) -> None:
    earlier_index = index_of(body, earlier)
    later_index = index_of(body, later)
    if earlier_index != -1 and later_index != -1 and earlier_index > later_index:
        fail(f"lane :{lane_name} must call {earlier} before {later}")


if not FASTFILE.is_file():
    fail("fastlane/Fastfile is missing")
    source = ""
else:
    source = FASTFILE.read_text(encoding="utf-8")

if source:
    if "Scripts/validate_app_review_contact.sh" not in source:
        fail("Fastfile must call Scripts/validate_app_review_contact.sh")
    if "Scripts/check_app_store_connect_state.sh" not in source:
        fail("Fastfile must call Scripts/check_app_store_connect_state.sh")
    if "Scripts/validate_app_store_metadata.sh" not in source:
        fail("Fastfile must call Scripts/validate_app_store_metadata.sh")
    if "Scripts/validate_screenshot_sync.sh" not in source:
        fail("Fastfile must call Scripts/validate_screenshot_sync.sh")
    if "Scripts/validate_app_privacy_details.sh" not in source:
        fail("Fastfile must call Scripts/validate_app_privacy_details.sh")
    if "Scripts/validate_privacy_surface.sh" not in source:
        fail("Fastfile must call Scripts/validate_privacy_surface.sh")

    metadata = lane_body(source, "metadata")
    if metadata:
        require_before("metadata", metadata, "validate_app_store_metadata!", "deliver(")
        require_before("metadata", metadata, "validate_screenshot_sync!", "deliver(")
        require_before("metadata", metadata, "validate_app_review_contact!", "deliver(")
        index_of(metadata, "review_information_options")
        if "submit_for_review: false" not in metadata:
            fail("lane :metadata must never submit for review")
        if "skip_binary_upload: true" not in metadata:
            fail("lane :metadata must skip binary upload")

    privacy_details = lane_body(source, "privacy_details")
    if privacy_details:
        require_before("privacy_details", privacy_details, "confirm_upload_app_privacy!", "upload_app_privacy_details_to_app_store")
        require_before("privacy_details", privacy_details, "validate_privacy_surface!", "upload_app_privacy_details_to_app_store")
        require_before("privacy_details", privacy_details, "validate_app_privacy_details!", "upload_app_privacy_details_to_app_store")
        if "APP_PRIVACY_SKIP_PUBLISH" not in privacy_details:
            fail("lane :privacy_details must preserve the APP_PRIVACY_SKIP_PUBLISH option")

    submit_review = lane_body(source, "submit_review")
    if submit_review:
        require_before("submit_review", submit_review, "confirm_submit_for_review!", "deliver(")
        require_before("submit_review", submit_review, "validate_app_review_contact!", "deliver(")
        require_before("submit_review", submit_review, "verify_app_store_connect_state!", "deliver(")
        index_of(submit_review, "submission_information_options")
        if "submit_for_review: true" not in submit_review:
            fail("lane :submit_review must submit for review")
        if "automatic_release: false" not in submit_review:
            fail("lane :submit_review must use manual release")
        if "build_number: build_number" not in submit_review:
            fail("lane :submit_review must submit only the explicit APP_STORE_BUILD_NUMBER")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}")
    sys.exit(1)

print("Fastlane release lane validation passed.")
PY
