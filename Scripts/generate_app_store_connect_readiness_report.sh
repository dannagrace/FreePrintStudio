#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

output_path="${1:-build/app-store-connect-readiness-report.md}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

usage() {
  cat <<'EOF'
Usage: Scripts/generate_app_store_connect_readiness_report.sh [output-path]

Generates a redacted App Store Connect readiness report. The report is safe to
package because it summarizes credential and account-check status without
printing API key JSON paths, .p8 private key paths, Apple ID values, or contact
details.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

mkdir -p "$(dirname "$output_path")"

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

looks_placeholder_like() {
  local value="${1:-}"
  local lower_value
  [[ -z "$value" ]] && return 1
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" == *YOUR* ]] && return 0
  [[ "$value" == *YOUR_* ]] && return 0
  [[ "$lower_value" == *todo* ]] && return 0
  [[ "$lower_value" == *tbd* ]] && return 0
  [[ "$lower_value" == *example* ]] && return 0
  [[ "$lower_value" == *placeholder* ]] && return 0
  [[ "$value" == "PROCESSED_BUILD_NUMBER" ]] && return 0
  return 1
}

status_from_bool() {
  local ready="$1"
  local ok_text="$2"
  local missing_text="$3"
  if [[ "$ready" == "1" ]]; then
    printf '%s' "$ok_text"
  else
    printf '%s' "$missing_text"
  fi
}

private_file_permissions_status() {
  local path="$1"

  python3 - "$path" <<'PY'
from pathlib import Path
import stat
import sys

path = Path(sys.argv[1]).expanduser()

try:
    mode = path.stat().st_mode
except Exception:
    print("Could not be checked")
    raise SystemExit(1)

if stat.S_IMODE(mode) & 0o077:
    print("Too broad; run `chmod 600` on the configured file")
    raise SystemExit(1)

print("Private")
PY
}

json_configured=0
json_file_exists=0
json_permission_status="Not checked"
json_valid=0
json_key_id_present=0
json_issuer_id_present=0
json_key_material_present=0

if [[ -n "${APP_STORE_CONNECT_API_KEY_JSON:-}" ]]; then
  json_configured=1
  if [[ -f "$APP_STORE_CONNECT_API_KEY_JSON" ]]; then
    json_file_exists=1
    if json_permission_status="$(private_file_permissions_status "$APP_STORE_CONNECT_API_KEY_JSON" 2>&1)"; then
      json_summary_path="$(mktemp)"
      set +e
      python3 - "$APP_STORE_CONNECT_API_KEY_JSON" >"$json_summary_path" <<'PY'
import json
import sys

try:
    payload = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("json_valid=0")
    raise SystemExit(0)

print("json_valid=1")
print(f"json_key_id_present={1 if payload.get('key_id') else 0}")
print(f"json_issuer_id_present={1 if payload.get('issuer_id') else 0}")
print(f"json_key_material_present={1 if payload.get('key') or payload.get('key_filepath') else 0}")
PY
      set -e

      read_json_summary() {
        local key="$1"
        awk -F= -v key="$key" '$1 == key { print $2; found=1 } END { if (!found) print 0 }' "$json_summary_path"
      }

      json_valid="$(read_json_summary json_valid)"
      json_key_id_present="$(read_json_summary json_key_id_present)"
      json_issuer_id_present="$(read_json_summary json_issuer_id_present)"
      json_key_material_present="$(read_json_summary json_key_material_present)"
      rm -f "$json_summary_path"
    fi
  fi
fi

triplet_present_count=0
[[ -n "${ASC_KEY_ID:-}" ]] && triplet_present_count=$((triplet_present_count + 1))
[[ -n "${ASC_ISSUER_ID:-}" ]] && triplet_present_count=$((triplet_present_count + 1))
[[ -n "${ASC_KEY_PATH:-}" ]] && triplet_present_count=$((triplet_present_count + 1))

asc_key_path_exists=0
asc_key_path_permission_status="Not checked"
asc_key_path_private_key=0
if [[ -n "${ASC_KEY_PATH:-}" && -f "$ASC_KEY_PATH" ]]; then
  asc_key_path_exists=1
  if asc_key_path_permission_status="$(private_file_permissions_status "$ASC_KEY_PATH" 2>&1)" \
    && grep -q "BEGIN PRIVATE KEY" "$ASC_KEY_PATH"; then
    asc_key_path_private_key=1
  fi
fi

credential_mode="Missing"
if [[ "$json_configured" == "1" ]]; then
  credential_mode="API JSON"
elif (( triplet_present_count > 0 )); then
  credential_mode="API key triplet ($triplet_present_count/3)"
fi

fastlane_user_configured=0
[[ -n "${FASTLANE_USER:-}" ]] && fastlane_user_configured=1

if [[ -z "${APP_STORE_BUILD_NUMBER:-}" ]]; then
  build_number_status="No"
elif looks_placeholder_like "${APP_STORE_BUILD_NUMBER:-}"; then
  build_number_status="Blocked; APP_STORE_BUILD_NUMBER still uses a placeholder"
else
  build_number_status="Yes ($(mask_value "${APP_STORE_BUILD_NUMBER:-}"))"
fi

privacy_upload_confirmed=0
[[ "${CONFIRM_UPLOAD_APP_PRIVACY:-}" == "1" ]] && privacy_upload_confirmed=1

privacy_connect_confirmed=0
[[ "${APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT:-}" == "1" ]] && privacy_connect_confirmed=1

submit_review_confirmed=0
[[ "${CONFIRM_SUBMIT_FOR_REVIEW:-}" == "1" ]] && submit_review_confirmed=1

cat >"$output_path" <<EOF
# FreePrint Studio App Store Connect Readiness Report

- Generated At: $generated_at
- This report is redacted: it does not print API key JSON paths, .p8 private key paths, Apple ID values, App Review contact values, or private credential contents.
- Credential validation command: \`Scripts/check_app_store_connect_credentials.sh\`
- Metadata upload preflight command: \`Scripts/preflight_metadata_upload.sh\`
- App Privacy upload preflight command: \`Scripts/preflight_app_privacy_upload.sh\`
- App/version/build state command: \`Scripts/run_fastlane.sh ios app_store_connect_state\`
- TestFlight preflight command: \`Scripts/preflight_testflight_upload.sh\`
- App Review preflight command: \`Scripts/preflight_app_review_submission.sh\`

## Credential Mode

| Item | Status |
| --- | --- |
| Selected credential mode | $credential_mode |
| \`APP_STORE_CONNECT_API_KEY_JSON\` configured | $(status_from_bool "$json_configured" "Yes; value redacted" "No") |
| \`APP_STORE_CONNECT_API_KEY_JSON\` file exists | $(status_from_bool "$json_file_exists" "Yes" "No or not configured") |
| \`APP_STORE_CONNECT_API_KEY_JSON\` permissions | $json_permission_status |
| API JSON parses as JSON | $(status_from_bool "$json_valid" "Yes" "No or not checked") |
| API JSON \`key_id\` present | $(status_from_bool "$json_key_id_present" "Yes" "No or not checked") |
| API JSON \`issuer_id\` present | $(status_from_bool "$json_issuer_id_present" "Yes" "No or not checked") |
| API JSON key material present | $(status_from_bool "$json_key_material_present" "Yes" "No or not checked") |
| \`ASC_KEY_ID\` configured | $(status_from_bool "$([[ -n "${ASC_KEY_ID:-}" ]] && printf 1 || printf 0)" "Yes; value redacted" "No") |
| \`ASC_ISSUER_ID\` configured | $(status_from_bool "$([[ -n "${ASC_ISSUER_ID:-}" ]] && printf 1 || printf 0)" "Yes; value redacted" "No") |
| \`ASC_KEY_PATH\` configured | $(status_from_bool "$([[ -n "${ASC_KEY_PATH:-}" ]] && printf 1 || printf 0)" "Yes; path redacted" "No") |
| \`ASC_KEY_PATH\` file exists | $(status_from_bool "$asc_key_path_exists" "Yes" "No or not configured") |
| \`ASC_KEY_PATH\` permissions | $asc_key_path_permission_status |
| \`ASC_KEY_PATH\` looks like a private key | $(status_from_bool "$asc_key_path_private_key" "Yes" "No or not checked") |

## Upload And Submission Inputs

| Item | Status |
| --- | --- |
| \`FASTLANE_USER\` configured | $(status_from_bool "$fastlane_user_configured" "Yes ($(mask_value "${FASTLANE_USER:-}"))" "No") |
| \`APP_STORE_BUILD_NUMBER\` configured | $build_number_status |
| \`CONFIRM_UPLOAD_APP_PRIVACY=1\` | $(status_from_bool "$privacy_upload_confirmed" "Yes" "No") |
| \`APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1\` | $(status_from_bool "$privacy_connect_confirmed" "Yes" "No") |
| \`CONFIRM_SUBMIT_FOR_REVIEW=1\` | $(status_from_bool "$submit_review_confirmed" "Yes" "No") |

## Account-Dependent Checks

Replace \`PROCESSED_BUILD_NUMBER\` with the processed App Store Connect build number before running selected-build commands; local validators intentionally reject that placeholder.
Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.

| Check | Command | When To Run |
| --- | --- | --- |
| Credential syntax | \`Scripts/check_app_store_connect_credentials.sh\` | After configuring API JSON or API key triplet. |
| Metadata and screenshot upload preflight | \`Scripts/preflight_metadata_upload.sh\` | After App Store Connect credentials and App Review contact values are configured. |
| Metadata and screenshot upload | \`Scripts/run_fastlane.sh ios metadata\` | After the metadata upload preflight passes. |
| App Privacy Details upload preflight | \`FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh\` | After reviewing \`AppStore/app_privacy_details.json\` against App Store Connect answers. |
| App Privacy Details upload | \`FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details\` | After the App Privacy upload preflight passes. |
| App Privacy Details confirmation | \`APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh\` | After App Store Connect matches \`AppStore/app_privacy_details.json\`. |
| App record, version, and selected build | \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state\` | After TestFlight processing completes. |
| TestFlight upload preflight | \`Scripts/preflight_testflight_upload.sh\` | After signing and App Store Connect credentials are configured. |
| App Review submission preflight | \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh\` | After listing fields, manual evidence, and selected build are final. |

## Required Next Actions

- [ ] Configure either \`APP_STORE_CONNECT_API_KEY_JSON\` or the \`ASC_KEY_ID\`, \`ASC_ISSUER_ID\`, and \`ASC_KEY_PATH\` triplet in untracked local release inputs.
- [ ] Run \`Scripts/check_app_store_connect_credentials.sh\`.
- [ ] Create or verify the App Store Connect app record for \`com.dannagrace.FreePrintStudio\`.
- [ ] Run \`Scripts/preflight_metadata_upload.sh\`, then upload metadata and screenshots with \`Scripts/run_fastlane.sh ios metadata\`.
- [ ] Run \`FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh\`, then upload App Privacy Details with \`Scripts/run_fastlane.sh ios privacy_details\`.
- [ ] Upload a signed IPA to TestFlight with \`Scripts/run_fastlane.sh ios upload_testflight\`.
- [ ] Confirm App Privacy Details in App Store Connect match \`AppStore/app_privacy_details.json\`, then set \`APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1\` and run \`APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh\`.
- [ ] Wait for the build to finish processing, then set \`APP_STORE_BUILD_NUMBER\`.
- [ ] Run \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state\`.
- [ ] Run \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh\` before final submission.
EOF

printf 'App Store Connect readiness report generated: %s\n' "$output_path"
