#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <app-review-submission-readiness-report.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
report_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

if [[ ! -s "$report_path" ]]; then
  printf 'FAIL: App Review submission readiness report is missing or empty: %s\n' "$report_path"
  exit 1
fi

python3 - "$actions_path" "$report_path" <<'PY'
import csv
from pathlib import Path
import re
import sys

actions_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
report = report_path.read_text(encoding="utf-8")
failures: list[str] = []

required_columns = [
    "category",
    "severity",
    "owner",
    "field",
    "target",
    "item",
    "next_action",
    "validation_command",
]

tracked_categories = {
    "App Review Contact",
    "Manual Verification",
    "Signing",
    "App Privacy",
    "Commercial Configuration",
    "App Store Connect",
}


def fail(message: str) -> None:
    failures.append(message)


def require_contains(fragment: str, description: str) -> None:
    if fragment not in report:
        fail(f"{description} is missing from App Review submission readiness report")


def require_check_row(check: str, field: str) -> None:
    pattern = re.compile(
        rf"^\| {re.escape(check)} \| [^|\n]+ \| [^|\n]+ \|$",
        re.MULTILINE,
    )
    if not pattern.search(report):
        fail(f"{field} final submission check row is missing from App Review submission readiness report")


def require_missing_field(field: str) -> None:
    if field not in report:
        fail(f"{field} missing release input field is missing from App Review submission readiness report")


def require_review_contact(field: str) -> None:
    require_check_row("App Review contact", field)
    require_contains("Scripts/validate_app_review_contact.sh", f"{field} contact validation command")
    require_missing_field(field)


def require_manual_verification(field: str) -> None:
    require_check_row("Manual real-device, AirPrint, iPad, and TestFlight evidence", field)
    require_contains(
        "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh",
        f"{field} manual evidence validation command",
    )
    if field not in report and "MANUAL_RELEASE_VERIFICATION_PATH" not in report:
        fail(f"{field} manual evidence private input tracking is missing from App Review submission readiness report")


def require_signing(field: str) -> None:
    require_missing_field(field)
    require_contains("Scripts/print_release_input_status.sh --strict", f"{field} release input status command")


def require_app_privacy(field: str) -> None:
    require_check_row("App Privacy Details confirmed in App Store Connect", field)
    require_contains("Scripts/validate_app_privacy_connect_entry.sh", f"{field} App Privacy confirmation command")
    require_missing_field(field)


def require_commercial_configuration(field: str) -> None:
    require_check_row("Commercial configuration confirmed in App Store Connect", field)
    require_contains(
        "Scripts/validate_commercial_configuration_connect_entry.sh",
        f"{field} commercial configuration confirmation command",
    )
    require_missing_field(field)


def require_app_store_connect(field: str) -> None:
    if field == "APP_STORE_CONNECT_API_KEY_JSON or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH":
        require_check_row("API credentials", field)
        require_contains("Scripts/check_app_store_connect_credentials.sh", f"{field} credential validation command")
        require_missing_field(field)
    elif field == "App Store Connect app record/TestFlight status":
        require_check_row("App record, version, and selected build state", field)
        require_contains(
            "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_app_store_connect_submission_state.sh",
            f"{field} selected-build state command",
        )
    else:
        fail(f"{field} has no mapped App Store Connect final submission check")


with actions_path.open(newline="", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    if reader.fieldnames is None:
        print("FAIL: external readiness actions file is missing a header")
        raise SystemExit(1)
    missing_columns = [column for column in required_columns if column not in reader.fieldnames]
    if missing_columns:
        print(
            "FAIL: external readiness actions file is missing required column(s): "
            + ", ".join(missing_columns)
        )
        raise SystemExit(1)
    rows = [row for row in reader if any((value or "").strip() for value in row.values())]

tracked_rows = [row for row in rows if row["category"] in tracked_categories]

require_contains("# FreePrint Studio App Review Submission Readiness Report", "App Review submission readiness report title")
require_contains("This report is redacted", "redaction guidance")
require_contains("## Summary", "summary section")
require_contains("## Release Input Status", "release input status section")
require_contains("## Missing Release Input Fields", "missing release input fields section")
require_contains("## Store Listing And Policy Checks", "store listing and policy checks section")
require_contains("## Review And Evidence Checks", "review and evidence checks section")
require_contains("## App Store Connect Checks", "App Store Connect checks section")
require_contains("## Required Next Actions", "required next actions section")
require_contains(
    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh",
    "final App Review preflight command",
)
require_contains(
    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review",
    "final guarded App Review submission command",
)
require_contains(
    "processed App Store Connect build number",
    "selected-build replacement guidance",
)
require_contains("Scripts/validate_app_store_metadata.sh", "metadata validation command")
require_contains("Scripts/validate_screenshot_privacy.sh", "screenshot privacy validation command")
require_contains("Scripts/validate_public_pages.sh", "public page validation command")

for row in tracked_rows:
    category = row["category"]
    field = row["field"]
    if category == "App Review Contact":
        require_review_contact(field)
    elif category == "Manual Verification":
        require_manual_verification(field)
    elif category == "Signing":
        require_signing(field)
    elif category == "App Privacy":
        require_app_privacy(field)
    elif category == "Commercial Configuration":
        require_commercial_configuration(field)
    elif category == "App Store Connect":
        require_app_store_connect(field)

if failures:
    for message in failures:
        print(f"FAIL: {message}")
    raise SystemExit(1)

print("App Review submission readiness report matches external readiness actions.")
PY
