#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <app-review-contact-readiness-report.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
report_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

if [[ ! -s "$report_path" ]]; then
  printf 'FAIL: App Review contact readiness report is missing or empty: %s\n' "$report_path"
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
        fail(f"{description} is missing from App Review contact readiness report")


def require_contact_row(field: str) -> None:
    pattern = re.compile(rf"^\| [^|\n]+ \| `{re.escape(field)}` \| [^|\n]+ \|$", re.MULTILINE)
    if not pattern.search(report):
        fail(f"{field} readiness row is missing from App Review contact readiness report")


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

contact_rows = [
    row
    for row in rows
    if row["category"] == "App Review Contact"
    or row["field"].startswith("APP_REVIEW_CONTACT_")
]

require_contains("# FreePrint Studio App Review Contact Readiness Report", "App Review contact readiness report title")
require_contains("This report is redacted", "redaction guidance")
require_contains("## Summary", "contact summary section")
require_contains("## Required Contact Fields", "required contact fields section")
require_contains("Config/release.env", "release environment target guidance")
require_contains("Scripts/validate_app_review_contact.sh", "App Review contact validation command")
require_contains(
    "processed App Store Connect build number",
    "selected processed build replacement guidance",
)

for row in contact_rows:
    field = row["field"]
    if field.startswith("APP_REVIEW_CONTACT_"):
        require_contact_row(field)

if failures:
    for message in failures:
        print(f"FAIL: {message}")
    raise SystemExit(1)

print("App Review contact readiness report matches external readiness actions.")
PY
