#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <signing-readiness-report.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
report_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

if [[ ! -s "$report_path" ]]; then
  printf 'FAIL: signing readiness report is missing or empty: %s\n' "$report_path"
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

field_to_report_item = {
    "DEVELOPMENT_TEAM_ID": "Apple Developer Team ID",
    "Apple Distribution certificate": "Apple Distribution identity",
    "App Store provisioning profile": "App Store provisioning profile",
}


def fail(message: str) -> None:
    failures.append(message)


def require_contains(fragment: str, description: str) -> None:
    if fragment not in report:
        fail(f"{description} is missing from signing readiness report")


def require_signing_row(field: str, report_item: str) -> None:
    pattern = re.compile(
        rf"^\| {re.escape(report_item)} \| [^|\n]+ \|$",
        re.MULTILINE,
    )
    if not pattern.search(report):
        fail(f"{field} signing readiness row is missing from signing readiness report")


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

signing_rows = [row for row in rows if row["category"] == "Signing"]

require_contains("# FreePrint Studio Signing Readiness Report", "signing readiness report title")
require_contains("This report is redacted", "redaction guidance")
require_contains("## Required App Store Signing State", "required signing state section")
require_contains("## Local Signing Inventory", "local signing inventory section")
require_contains("## Required Next Actions", "required next actions section")
require_contains("Scripts/check_code_signing_assets.sh", "code signing validation command")
require_contains("Scripts/preflight_app_store_archive.sh", "archive preflight command")
require_contains("DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh", "archive command")
require_contains(
    "Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands.",
    "Team ID replacement guidance",
)

for row in signing_rows:
    field = row["field"]
    report_item = field_to_report_item.get(field)
    if report_item is None:
        fail(f"{field} has no mapped signing readiness report row")
        continue
    require_signing_row(field, report_item)

if failures:
    for message in failures:
        print(f"FAIL: {message}")
    raise SystemExit(1)

print("Signing readiness report matches external readiness actions.")
PY
