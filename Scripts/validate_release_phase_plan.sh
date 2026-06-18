#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <release-phase-plan.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
plan_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

if [[ ! -s "$plan_path" ]]; then
  printf 'FAIL: release phase plan is missing or empty: %s\n' "$plan_path"
  exit 1
fi

python3 - "$actions_path" "$plan_path" <<'PY'
import csv
from collections import OrderedDict
from pathlib import Path
import re
import sys

actions_path = Path(sys.argv[1])
plan_path = Path(sys.argv[2])
plan = plan_path.read_text(encoding="utf-8")
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

phases = OrderedDict(
    (phase_name, None)
    for phase_name in [
        "Phase 1 - Private Inputs And Account Access",
        "Phase 2 - Signing And Archive",
        "Phase 3 - App Store Connect Metadata And Privacy",
        "Phase 4 - TestFlight And Manual QA",
        "Phase 5 - App Review Submission",
    ]
)


def fail(message: str) -> None:
    failures.append(message)


def markdown_cell(value: str) -> str:
    return str(value).replace("|", "\\|").replace("`", "\\`")


def code(value: str) -> str:
    return f"`{markdown_cell(value)}`"


def require_contains(fragment: str, description: str) -> None:
    if fragment not in plan:
        fail(f"{description} is missing from release phase plan")


def phase_for(row: dict[str, str]) -> str:
    category = row["category"]
    field = row["field"]
    target = row["target"]
    item = row["item"]

    if category == "Manual Verification" or target == "Config/manual-release-verification.env":
        return "Phase 4 - TestFlight And Manual QA"
    if (
        category == "Signing"
        or field == "DEVELOPMENT_TEAM_ID"
        or target in {"login keychain", "~/Library/MobileDevice/Provisioning Profiles"}
        or "Apple Distribution" in item
        or "provisioning profile" in item
    ):
        return "Phase 2 - Signing And Archive"
    if category in {"App Privacy", "Commercial Configuration", "GitHub Pages Source"}:
        return "Phase 3 - App Store Connect Metadata And Privacy"
    if category == "App Store Connect":
        if "API credentials" in item or "ASC_" in field or "APP_STORE_CONNECT_API_KEY_JSON" in field or "FASTLANE_USER" in field:
            return "Phase 1 - Private Inputs And Account Access"
        return "Phase 3 - App Store Connect Metadata And Privacy"
    if category == "App Review Contact" or target.startswith("Config/release.env"):
        return "Phase 1 - Private Inputs And Account Access"
    return "Phase 5 - App Review Submission"


with actions_path.open(newline="") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    if reader.fieldnames is None:
        print("FAIL: external readiness actions file is missing a header")
        raise SystemExit(1)
    missing = [column for column in required_columns if column not in reader.fieldnames]
    if missing:
        print("FAIL: external readiness actions file is missing required column(s): " + ", ".join(missing))
        raise SystemExit(1)
    rows = [row for row in reader if any((value or "").strip() for value in row.values())]

phase_rows = {phase: [] for phase in phases}
for row in rows:
    phase_rows[phase_for(row)].append(row)

total = len(rows)
blockers = sum(1 for row in rows if row["severity"] == "blocker")
warnings = sum(1 for row in rows if row["severity"] == "warning")

require_contains("# FreePrint Studio Release Phase Plan", "release phase plan title")
require_contains(f"- External Actions: `{total}`", "external action count")
require_contains(f"- Blockers: `{blockers}`", "blocker count")
require_contains(f"- Warnings: `{warnings}`", "warning count")
require_contains("## Phase Summary", "Phase Summary section")
require_contains("Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands.", "selected-build placeholder replacement guidance")
require_contains("Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands.", "Team ID placeholder replacement guidance")
require_contains("Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.", "Fastlane Apple ID placeholder replacement guidance")
require_contains("APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh", "final App Review submission preflight command")
require_contains("APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review", "final App Review submit command")
require_contains("Required final submission guards", "final submission guard section")
require_contains(
    "| `APP_STORE_BUILD_NUMBER` | Processed App Store Connect build selected for App Review. | `APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh` |",
    "APP_STORE_BUILD_NUMBER final guard row",
)
require_contains(
    "| `CONFIRM_SUBMIT_FOR_REVIEW=1` | Explicit final confirmation before Fastlane submits the selected build for review. | `APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review` |",
    "CONFIRM_SUBMIT_FOR_REVIEW=1 final submit confirmation guard row",
)

for phase_name, current_rows in phase_rows.items():
    phase_blockers = sum(1 for row in current_rows if row["severity"] == "blocker")
    phase_warnings = sum(1 for row in current_rows if row["severity"] == "warning")
    require_contains(f"## {phase_name}", f"{phase_name} section")
    require_contains(
        f"| {phase_name} | {len(current_rows)} | {phase_blockers} | {phase_warnings} |",
        f"{phase_name} summary row",
    )

for row in rows:
    expected_row = (
        "| "
        + " | ".join(
            [
                markdown_cell(row["category"]),
                markdown_cell(row["owner"]),
                markdown_cell(row["severity"]),
                code(row["field"]),
                code(row["target"]),
                markdown_cell(row["item"]),
                code(row["validation_command"]),
            ]
        )
        + " |"
    )
    if expected_row not in plan:
        fail(f"action detail row is missing or mismatched in release phase plan: {row['field']} - {row['item']}")

if re.search(r"\|\s*\|\s*\|", plan):
    fail("release phase plan contains an empty markdown table cell")

if failures:
    for message in failures:
        print(f"FAIL: {message}")
    raise SystemExit(1)

print("Release phase plan matches external readiness actions.")
PY
