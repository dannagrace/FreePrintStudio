#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <app-store-connect-readiness-report.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
report_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

if [[ ! -s "$report_path" ]]; then
  printf 'FAIL: App Store Connect readiness report is missing or empty: %s\n' "$report_path"
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


def fail(message: str) -> None:
    failures.append(message)


def require_contains(fragment: str, description: str) -> None:
    if fragment not in report:
        fail(f"{description} is missing from App Store Connect readiness report")


def require_table_row(item: str, field: str) -> None:
    pattern = re.compile(rf"^\| {re.escape(item)} \| [^|\n]+ \|$", re.MULTILINE)
    if not pattern.search(report):
        fail(f"{field} readiness row is missing from App Store Connect readiness report")


def require_credential_rows(field: str) -> None:
    for item in [
        "`APP_STORE_CONNECT_API_KEY_JSON` configured",
        "`ASC_KEY_ID` configured",
        "`ASC_ISSUER_ID` configured",
        "`ASC_KEY_PATH` configured",
    ]:
        require_table_row(item, field)
    require_contains("Scripts/check_app_store_connect_credentials.sh", f"{field} validation command")


def require_privacy_confirmation(field: str) -> None:
    require_table_row("`APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1`", field)
    require_contains(
        "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh",
        f"{field} confirmation command",
    )
    require_contains("Scripts/preflight_app_privacy_upload.sh", f"{field} upload preflight")
    require_contains("Scripts/run_fastlane.sh ios privacy_details", f"{field} upload command")


def require_commercial_confirmation(field: str) -> None:
    require_table_row("`APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1`", field)
    require_contains(
        "APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_commercial_configuration_connect_entry.sh",
        f"{field} confirmation command",
    )
    require_contains("AppStore/commercial-configuration.md", f"{field} source configuration")


def require_account_state_warning(field: str) -> None:
    require_contains("App record, version, and selected build", f"{field} account-state check")
    require_contains("Scripts/run_fastlane.sh ios app_store_connect_state", f"{field} account-state command")
    require_contains(
        "processed App Store Connect build number",
        f"{field} selected-build replacement guidance",
    )


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

tracked_rows = [
    row
    for row in rows
    if row["category"] in {"App Store Connect", "App Privacy", "Commercial Configuration"}
]

require_contains("# FreePrint Studio App Store Connect Readiness Report", "App Store Connect readiness report title")
require_contains("This report is redacted", "redaction guidance")
require_contains("## Credential Mode", "credential mode section")
require_contains("## Upload And Submission Inputs", "upload and submission inputs section")
require_contains("## Account-Dependent Checks", "account-dependent checks section")
require_contains("## Required Next Actions", "required next actions section")
require_contains("Scripts/preflight_metadata_upload.sh", "metadata upload preflight")
require_contains("Scripts/run_fastlane.sh ios metadata", "metadata upload command")
require_contains("Scripts/preflight_testflight_upload.sh", "TestFlight preflight")
require_contains("Scripts/preflight_app_review_submission.sh", "App Review preflight")
require_contains(
    "Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.",
    "Fastlane Apple ID replacement guidance",
)

for row in tracked_rows:
    field = row["field"]
    if field == "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT":
        require_privacy_confirmation(field)
    elif field == "APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT":
        require_commercial_confirmation(field)
    elif field == "APP_STORE_CONNECT_API_KEY_JSON or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH":
        require_credential_rows(field)
    elif field == "App Store Connect app record/TestFlight status":
        require_account_state_warning(field)
    else:
        fail(f"{field} has no mapped App Store Connect readiness report coverage")

if failures:
    for message in failures:
        print(f"FAIL: {message}")
    raise SystemExit(1)

print("App Store Connect readiness report matches external readiness actions.")
PY
