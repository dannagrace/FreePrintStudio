#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <manual-release-evidence-form.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
form_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

if [[ ! -s "$form_path" ]]; then
  printf 'FAIL: manual release evidence form is missing or empty: %s\n' "$form_path"
  exit 1
fi

python3 - "$actions_path" "$form_path" <<'PY'
import csv
from pathlib import Path
import sys

actions_path = Path(sys.argv[1])
form_path = Path(sys.argv[2])
form = form_path.read_text(encoding="utf-8")
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
    if fragment not in form:
        fail(f"{description} is missing from manual release evidence form")


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

manual_rows = [
    row
    for row in rows
    if row["category"] == "Manual Verification"
    or row["target"] == "Config/manual-release-verification.env"
]

require_contains("# FreePrint Studio Manual Release Evidence Form", "manual release evidence form title")
require_contains("Config/manual-release-verification.env", "manual evidence target file guidance")
require_contains(
    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh",
    "manual evidence validation command",
)
require_contains(
    "processed App Store Connect build number",
    "selected processed build replacement guidance",
)

for row in manual_rows:
    field = row["field"]
    item = row["item"]
    if field.startswith("MANUAL_"):
        require_contains(f"`{field}`", f"{field} field mapping")
    elif field in {"manual-release-verification.env file", "MANUAL_RELEASE_VERIFICATION_PATH"} or (
        "manual-release-verification.env" in item
    ):
        require_contains(
            "Scripts/install_private_release_input_templates.sh",
            "manual evidence private template installer guidance",
        )

if failures:
    for message in failures:
        print(f"FAIL: {message}")
    raise SystemExit(1)

print("Manual release evidence form matches external readiness actions.")
PY
