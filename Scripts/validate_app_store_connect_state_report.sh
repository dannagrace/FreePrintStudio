#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <app-store-connect-state-report.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
report_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: External readiness actions file is missing or empty: %s\n' "$actions_path" >&2
  exit 1
fi

if [[ ! -s "$report_path" ]]; then
  printf 'FAIL: App Store Connect state report is missing or empty: %s\n' "$report_path" >&2
  exit 1
fi

python3 - "$actions_path" "$report_path" <<'PY'
import csv
import sys
from pathlib import Path

actions_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])

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

with actions_path.open(newline="", encoding="utf-8") as actions_file:
    reader = csv.DictReader(actions_file, delimiter="\t")
    if reader.fieldnames != required_columns:
        raise SystemExit(
            "FAIL: external-readiness-actions.tsv has unexpected header: "
            + "\t".join(reader.fieldnames or [])
        )
    actions = list(reader)

report = report_path.read_text(encoding="utf-8")
failures: list[str] = []


def require(fragment: str, description: str) -> None:
    if fragment not in report:
        failures.append(f"{description}: missing {fragment}")


def has_action(predicate) -> bool:
    return any(predicate(action) for action in actions)


require("# FreePrint Studio App Store Connect State Report", "report title")
require("This report is redacted", "redaction disclosure")
require("State check command: `Scripts/check_app_store_connect_state.sh`", "state check command")
require("Exit Code:", "state check exit code")
require("Status:", "state check status")
require("Timeout Seconds:", "state check timeout")
require("## Selected Build Input", "selected build input section")
require("| `APP_STORE_BUILD_NUMBER` |", "selected build row")
require("## Redacted Output", "redacted output section")
require("```text", "redacted output code fence")
require("## Required Next Actions", "required next actions section")
require("Configure App Store Connect credentials", "credential setup guidance")
require("Upload a signed TestFlight build", "TestFlight upload guidance")
require("Wait for the build to finish App Store Connect processing", "build processing guidance")
require("Set `APP_STORE_BUILD_NUMBER`", "selected build number guidance")
require("processed build selected for App Review", "processed selected build guidance")
require(
    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/check_app_store_connect_state.sh",
    "selected build verification command",
)
require("Keep this report in the submission packet", "submission packet evidence guidance")

selected_build_action = has_action(
    lambda action: action.get("category") == "App Store Connect"
    and (
        "APP_STORE_BUILD_NUMBER" in action.get("field", "")
        or "check_app_store_connect_state.sh" in action.get("validation_command", "")
        or "selected TestFlight build" in action.get("next_action", "")
        or "selected build" in action.get("item", "")
    )
)
if selected_build_action:
    require("`APP_STORE_BUILD_NUMBER`", "APP_STORE_BUILD_NUMBER action coverage")
    require("Scripts/check_app_store_connect_state.sh", "selected build validation action coverage")
    require("processed build selected for App Review", "selected build action guidance")

credential_action = has_action(
    lambda action: action.get("category") == "App Store Connect"
    and (
        "APP_STORE_CONNECT_API_KEY_JSON" in action.get("field", "")
        or "ASC_KEY_ID" in action.get("field", "")
        or "check_app_store_connect_credentials.sh" in action.get("validation_command", "")
        or "API credentials" in action.get("item", "")
    )
)
if credential_action:
    require("Configure App Store Connect credentials", "App Store Connect credential action coverage")
    require("untracked `Config/release.env`", "private credential storage guidance")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    raise SystemExit(1)

print("App Store Connect state report matches external readiness actions.")
PY
