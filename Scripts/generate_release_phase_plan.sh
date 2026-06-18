#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <release-phase-plan.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
output_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions file is missing or empty: %s\n' "$actions_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"

python3 - "$actions_path" "$output_path" <<'PY'
import csv
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path
import sys

actions_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

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
    [
        (
            "Phase 1 - Private Inputs And Account Access",
            {
                "purpose": "Install private templates, fill release contact and account access values, and run the redacted input checks before any account-side work.",
                "gates": [
                    "Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config",
                    "Scripts/print_release_input_status.sh --strict",
                    "Scripts/validate_release_env.sh",
                ],
            },
        ),
        (
            "Phase 2 - Signing And Archive",
            {
                "purpose": "Install Apple Developer signing assets and produce the App Store archive only after signing gates pass.",
                "gates": [
                    "Scripts/check_code_signing_assets.sh",
                    "Scripts/preflight_app_store_archive.sh",
                    "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh",
                ],
            },
        ),
        (
            "Phase 3 - App Store Connect Metadata And Privacy",
            {
                "purpose": "Upload or confirm store metadata, privacy answers, pricing, availability, monetization, release option, and phased release settings in App Store Connect.",
                "gates": [
                    "Scripts/preflight_metadata_upload.sh",
                    "FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh",
                    "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh",
                    "APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_commercial_configuration_connect_entry.sh",
                ],
            },
        ),
        (
            "Phase 4 - TestFlight And Manual QA",
            {
                "purpose": "Upload the signed build, wait for processing, then record real iPhone, AirPrint, iPad, and TestFlight evidence for the selected build.",
                "gates": [
                    "Scripts/preflight_testflight_upload.sh",
                    "ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight",
                    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state",
                    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh",
                ],
            },
        ),
        (
            "Phase 5 - App Review Submission",
            {
                "purpose": "Submit only the processed build that passed manual evidence and final App Review preflight.",
                "gates": [
                    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh",
                    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review",
                ],
            },
        ),
    ]
)

final_submission_guards = [
    (
        "APP_STORE_BUILD_NUMBER",
        "Processed App Store Connect build selected for App Review.",
        "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh",
    ),
    (
        "CONFIRM_SUBMIT_FOR_REVIEW=1",
        "Explicit final confirmation before Fastlane submits the selected build for review.",
        "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review",
    ),
]


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def markdown_cell(value: str) -> str:
    return str(value).replace("|", "\\|").replace("`", "\\`")


def code(value: str) -> str:
    return f"`{markdown_cell(value)}`"


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
        fail("external readiness actions file is missing a header")
    missing = [column for column in required_columns if column not in reader.fieldnames]
    if missing:
        fail("external readiness actions file is missing required column(s): " + ", ".join(missing))
    rows = [row for row in reader if any((value or "").strip() for value in row.values())]

phase_rows = {phase: [] for phase in phases}
for row in rows:
    phase_rows[phase_for(row)].append(row)

total = len(rows)
blockers = sum(1 for row in rows if row["severity"] == "blocker")
warnings = sum(1 for row in rows if row["severity"] == "warning")
generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

lines: list[str] = []
lines.append("# FreePrint Studio Release Phase Plan")
lines.append("")
lines.append(f"- Generated At: `{generated_at}`")
lines.append(f"- Source: `{actions_path}`")
lines.append(f"- External Actions: `{total}`")
lines.append(f"- Blockers: `{blockers}`")
lines.append(f"- Warnings: `{warnings}`")
lines.append("")
lines.append("## Placeholder Replacement Notes")
lines.append("")
lines.append("Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands.")
lines.append("Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands.")
lines.append("Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.")
lines.append("")
lines.append("## Phase Summary")
lines.append("")
lines.append("| Phase | Actions | Blockers | Warnings |")
lines.append("| --- | ---: | ---: | ---: |")
for phase_name, _metadata in phases.items():
    current_rows = phase_rows[phase_name]
    phase_blockers = sum(1 for row in current_rows if row["severity"] == "blocker")
    phase_warnings = sum(1 for row in current_rows if row["severity"] == "warning")
    lines.append(f"| {phase_name} | {len(current_rows)} | {phase_blockers} | {phase_warnings} |")

for phase_name, metadata in phases.items():
    current_rows = phase_rows[phase_name]
    lines.append("")
    lines.append(f"## {phase_name}")
    lines.append("")
    lines.append(metadata["purpose"])
    lines.append("")
    lines.append("Validation gates:")
    lines.append("")
    for gate in metadata["gates"]:
        lines.append(f"- `{markdown_cell(gate)}`")
    lines.append("")
    if phase_name == "Phase 5 - App Review Submission":
        lines.append("Required final submission guards:")
        lines.append("")
        lines.append("| Guard | Purpose | Validation Command |")
        lines.append("| --- | --- | --- |")
        for guard, purpose, command in final_submission_guards:
            lines.append(f"| {code(guard)} | {markdown_cell(purpose)} | {code(command)} |")
        lines.append("")
    if current_rows:
        lines.append("| Category | Owner | Severity | Field | Target | Item | Validation Command |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- |")
        for row in current_rows:
            lines.append(
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
    else:
        lines.append("No current external action rows for this phase.")

lines.append("")
output_path.write_text("\n".join(lines), encoding="utf-8")
PY
