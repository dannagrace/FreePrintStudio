#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import json
import subprocess
import sys
from pathlib import Path

failures = []
privacy_json_path = Path("AppStore/app_privacy_details.json")
privacy_markdown_path = Path("AppStore/app-privacy.md")
privacy_manifest_path = Path("FreePrintStudio/Resources/PrivacyInfo.xcprivacy")

expected_privacy_details = [
    {
        "data_protections": [
            "DATA_NOT_COLLECTED",
        ],
    },
]

try:
    privacy_details = json.loads(privacy_json_path.read_text(encoding="utf-8"))
except Exception as exc:
    failures.append(f"{privacy_json_path} is not valid JSON: {exc}")
    privacy_details = None

if privacy_details != expected_privacy_details:
    failures.append(
        "App Privacy Details JSON must declare only DATA_NOT_COLLECTED and no collected data categories"
    )

privacy_markdown = privacy_markdown_path.read_text(encoding="utf-8") if privacy_markdown_path.is_file() else ""
for required_text in (
    "No, we do not collect data from this app",
    "Tracking: No",
    "Data Types: None",
    "Third-party SDKs: None",
):
    if required_text not in privacy_markdown:
        failures.append(f"{privacy_markdown_path} is missing: {required_text}")

try:
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(privacy_manifest_path)],
        check=True,
        capture_output=True,
        text=True,
    )
    privacy_manifest = json.loads(result.stdout)
except Exception as exc:
    failures.append(f"{privacy_manifest_path} could not be parsed as JSON plist: {exc}")
    privacy_manifest = {}

if privacy_manifest.get("NSPrivacyTracking") is not False:
    failures.append("Privacy manifest must declare NSPrivacyTracking as false")
if privacy_manifest.get("NSPrivacyCollectedDataTypes") != []:
    failures.append("Privacy manifest must declare no collected data types")
if privacy_manifest.get("NSPrivacyTrackingDomains") != []:
    failures.append("Privacy manifest must declare no tracking domains")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}")
    sys.exit(1)

print("App Privacy Details validation passed.")
PY
