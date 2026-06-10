#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

output_path="${1:-build/signing-readiness-report.md}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

usage() {
  cat <<'EOF'
Usage: Scripts/generate_signing_readiness_report.sh [output-path]

Generates a redacted App Store signing readiness report. The report is safe to
package because it summarizes status and counts without printing certificate
common names, provisioning profile names, private key paths, or personal values.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

mkdir -p "$(dirname "$output_path")"

setting_value() {
  local key="$1"
  xcodebuild \
    -project FreePrintStudio.xcodeproj \
    -scheme FreePrintStudio \
    -configuration Release \
    -showBuildSettings 2>/dev/null \
    | awk -F'= ' -v key="$key" '{
        lhs = $1
        gsub(/^[ \t]+|[ \t]+$/, "", lhs)
        if (lhs == key) {
          gsub(/^[ \t]+|[ \t]+$/, "", $2)
          print $2
          exit
        }
      }'
}

mask_value() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    printf 'missing'
  elif (( ${#value} <= 4 )); then
    printf 'redacted'
  else
    printf 'redacted-%s' "${value: -4}"
  fi
}

status_text() {
  local ready="$1"
  local ok_text="$2"
  local missing_text="$3"
  if [[ "$ready" == "1" ]]; then
    printf '%s' "$ok_text"
  else
    printf '%s' "$missing_text"
  fi
}

bundle_id="$(setting_value PRODUCT_BUNDLE_IDENTIFIER || true)"
project_team_id="$(setting_value DEVELOPMENT_TEAM || true)"
team_source="missing"
team_id=""
if [[ -n "${DEVELOPMENT_TEAM_ID:-}" ]]; then
  team_id="$DEVELOPMENT_TEAM_ID"
  team_source="Config/release.env or shell"
elif [[ -n "$project_team_id" ]]; then
  team_id="$project_team_id"
  team_source="Xcode project"
fi

export_method="$(plutil -extract method raw -o - Config/ExportOptions-AppStore.plist 2>/dev/null || true)"
identity_log="$(security find-identity -v -p codesigning 2>/dev/null || true)"
distribution_identity_count="$(grep -c 'Apple Distribution' <<<"$identity_log" || true)"
matching_identity_ready=0
if [[ -n "$team_id" ]] && grep -Eq "Apple Distribution: .*\($team_id\)" <<<"$identity_log"; then
  matching_identity_ready=1
elif [[ -z "$team_id" && "$distribution_identity_count" -gt 0 ]]; then
  matching_identity_ready=1
fi

profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
profile_count=0
profile_summary_path="$(mktemp)"
if [[ -d "$profiles_dir" ]]; then
  while IFS= read -r -d '' _profile_path; do
    profile_count=$((profile_count + 1))
  done < <(find "$profiles_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print0 2>/dev/null)
fi

python3 - "$bundle_id" "$team_id" "$profiles_dir" >"$profile_summary_path" <<'PY'
import plistlib
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

bundle_id = sys.argv[1]
team_id = sys.argv[2]
profiles_dir = Path(sys.argv[3])
now = datetime.now(timezone.utc)
summary = {
    "readable": 0,
    "matching_app_store": 0,
    "expired": 0,
    "wrong_team": 0,
    "wrong_bundle": 0,
    "device_bound": 0,
    "debuggable": 0,
}

profile_paths = []
if profiles_dir.is_dir():
    profile_paths.extend(profiles_dir.glob("*.mobileprovision"))
    profile_paths.extend(profiles_dir.glob("*.provisionprofile"))

for path in profile_paths:
    try:
        result = subprocess.run(
            ["security", "cms", "-D", "-i", str(path)],
            check=True,
            capture_output=True,
        )
        profile = plistlib.loads(result.stdout)
    except Exception:
        continue

    summary["readable"] += 1
    entitlements = profile.get("Entitlements", {})
    application_identifier = entitlements.get("application-identifier", "")
    team_ids = profile.get("TeamIdentifier", [])
    expiration_date = profile.get("ExpirationDate")
    provisioned_devices = profile.get("ProvisionedDevices")
    get_task_allow = entitlements.get("get-task-allow")

    expired = False
    if expiration_date is not None:
        if expiration_date.tzinfo is None:
            expiration_date = expiration_date.replace(tzinfo=timezone.utc)
        expired = expiration_date <= now
        if expired:
            summary["expired"] += 1

    wrong_team = bool(team_id) and team_id not in team_ids
    if wrong_team:
        summary["wrong_team"] += 1

    expected_identifier = f"{team_id}.{bundle_id}" if team_id and bundle_id else ""
    wrong_bundle = bool(expected_identifier) and application_identifier != expected_identifier
    if wrong_bundle:
        summary["wrong_bundle"] += 1

    if provisioned_devices:
        # App Store Connect provisioning profiles do not contain ProvisionedDevices.
        summary["device_bound"] += 1

    if get_task_allow:
        summary["debuggable"] += 1

    if (
        not expired
        and team_id
        and bundle_id
        and not wrong_team
        and not wrong_bundle
        and not provisioned_devices
        and not get_task_allow
    ):
        summary["matching_app_store"] += 1

for key, value in summary.items():
    print(f"{key}={value}")
PY

read_profile_summary() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { print $2; found=1 } END { if (!found) print 0 }' "$profile_summary_path"
}

readable_profile_count="$(read_profile_summary readable)"
matching_profile_count="$(read_profile_summary matching_app_store)"
expired_profile_count="$(read_profile_summary expired)"
wrong_team_profile_count="$(read_profile_summary wrong_team)"
wrong_bundle_profile_count="$(read_profile_summary wrong_bundle)"
device_bound_profile_count="$(read_profile_summary device_bound)"
debuggable_profile_count="$(read_profile_summary debuggable)"
rm -f "$profile_summary_path"

bundle_ready=0
[[ "$bundle_id" == "com.dannagrace.FreePrintStudio" ]] && bundle_ready=1
export_ready=0
[[ "$export_method" == "app-store-connect" ]] && export_ready=1
team_ready=0
[[ -n "$team_id" ]] && team_ready=1
profile_ready=0
(( matching_profile_count > 0 )) && profile_ready=1

cat >"$output_path" <<EOF
# FreePrint Studio Signing Readiness Report

- Generated At: $generated_at
- This report is redacted: it does not print certificate common names, provisioning profile names, private key paths, or personal contact values.
- Full validation command: \`Scripts/check_code_signing_assets.sh\`
- Archive preflight command: \`Scripts/preflight_app_store_archive.sh\`

## Required App Store Signing State

| Item | Status |
| --- | --- |
| Bundle ID | $(status_text "$bundle_ready" "OK: com.dannagrace.FreePrintStudio" "Missing or unexpected: ${bundle_id:-missing}") |
| Export method | $(status_text "$export_ready" "OK: app-store-connect" "Missing or unexpected: ${export_method:-missing}") |
| Apple Developer Team ID | $(status_text "$team_ready" "Configured via $team_source ($(mask_value "$team_id"))" "Missing") |
| Apple Distribution identity | $(status_text "$matching_identity_ready" "Available for the selected team or available pending team selection" "Missing or not matched to the selected team") |
| App Store provisioning profile | $(status_text "$profile_ready" "Matching profile installed" "Missing matching App Store profile") |

## Local Signing Inventory

| Inventory | Count |
| --- | ---: |
| Apple Distribution identities | $distribution_identity_count |
| Provisioning profile files | $profile_count |
| Readable provisioning profiles | $readable_profile_count |
| Matching App Store profiles | $matching_profile_count |
| Expired profiles | $expired_profile_count |
| Profiles for another team | $wrong_team_profile_count |
| Profiles for another bundle ID | $wrong_bundle_profile_count |
| Device-bound profiles containing \`ProvisionedDevices\` | $device_bound_profile_count |
| Debuggable profiles with \`get-task-allow\` | $debuggable_profile_count |

## Required Next Actions

- [ ] Set \`DEVELOPMENT_TEAM_ID\` in the git-ignored \`Config/release.env\`, or configure \`DEVELOPMENT_TEAM\` in Xcode.
- [ ] Install an \`Apple Distribution\` certificate for that Apple Developer Program team.
- [ ] Install an App Store Connect provisioning profile for \`com.dannagrace.FreePrintStudio\`; it must not contain \`ProvisionedDevices\`.
- [ ] Run \`Scripts/check_code_signing_assets.sh\`.
- [ ] Run \`Scripts/preflight_app_store_archive.sh\`.
- [ ] Create the signed archive with \`DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh\`.
EOF

printf 'Signing readiness report generated: %s\n' "$output_path"
