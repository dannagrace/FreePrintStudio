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
  [[ -z "$value" ]] && return 1
  [[ "$value" == *YOUR* ]] && return 0
  [[ "$value" == *TODO* ]] && return 0
  [[ "$value" == *TBD* ]] && return 0
  [[ "$value" == *example* ]] && return 0
  [[ "$value" == *placeholder* ]] && return 0
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

json_configured=0
json_file_exists=0
json_valid=0
json_key_id_present=0
json_issuer_id_present=0
json_key_material_present=0

if [[ -n "${APP_STORE_CONNECT_API_KEY_JSON:-}" ]]; then
  json_configured=1
  if [[ -f "$APP_STORE_CONNECT_API_KEY_JSON" ]]; then
    json_file_exists=1
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

triplet_present_count=0
[[ -n "${ASC_KEY_ID:-}" ]] && triplet_present_count=$((triplet_present_count + 1))
[[ -n "${ASC_ISSUER_ID:-}" ]] && triplet_present_count=$((triplet_present_count + 1))
[[ -n "${ASC_KEY_PATH:-}" ]] && triplet_present_count=$((triplet_present_count + 1))

asc_key_path_exists=0
asc_key_path_private_key=0
if [[ -n "${ASC_KEY_PATH:-}" && -f "$ASC_KEY_PATH" ]]; then
  asc_key_path_exists=1
  if grep -q "BEGIN PRIVATE KEY" "$ASC_KEY_PATH"; then
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

submit_review_confirmed=0
[[ "${CONFIRM_SUBMIT_FOR_REVIEW:-}" == "1" ]] && submit_review_confirmed=1

cat >"$output_path" <<EOF
# FreePrint Studio App Store Connect Readiness Report

- Generated At: $generated_at
- This report is redacted: it does not print API key JSON paths, .p8 private key paths, Apple ID values, App Review contact values, or private credential contents.
- Credential validation command: \`Scripts/check_app_store_connect_credentials.sh\`
- App/version/build state command: \`Scripts/run_fastlane.sh ios app_store_connect_state\`
- TestFlight preflight command: \`Scripts/preflight_testflight_upload.sh\`
- App Review preflight command: \`Scripts/preflight_app_review_submission.sh\`

## Credential Mode

| Item | Status |
| --- | --- |
| Selected credential mode | $credential_mode |
| \`APP_STORE_CONNECT_API_KEY_JSON\` configured | $(status_from_bool "$json_configured" "Yes; value redacted" "No") |
| \`APP_STORE_CONNECT_API_KEY_JSON\` file exists | $(status_from_bool "$json_file_exists" "Yes" "No or not configured") |
| API JSON parses as JSON | $(status_from_bool "$json_valid" "Yes" "No or not checked") |
| API JSON \`key_id\` present | $(status_from_bool "$json_key_id_present" "Yes" "No or not checked") |
| API JSON \`issuer_id\` present | $(status_from_bool "$json_issuer_id_present" "Yes" "No or not checked") |
| API JSON key material present | $(status_from_bool "$json_key_material_present" "Yes" "No or not checked") |
| \`ASC_KEY_ID\` configured | $(status_from_bool "$([[ -n "${ASC_KEY_ID:-}" ]] && printf 1 || printf 0)" "Yes; value redacted" "No") |
| \`ASC_ISSUER_ID\` configured | $(status_from_bool "$([[ -n "${ASC_ISSUER_ID:-}" ]] && printf 1 || printf 0)" "Yes; value redacted" "No") |
| \`ASC_KEY_PATH\` configured | $(status_from_bool "$([[ -n "${ASC_KEY_PATH:-}" ]] && printf 1 || printf 0)" "Yes; path redacted" "No") |
| \`ASC_KEY_PATH\` file exists | $(status_from_bool "$asc_key_path_exists" "Yes" "No or not configured") |
| \`ASC_KEY_PATH\` looks like a private key | $(status_from_bool "$asc_key_path_private_key" "Yes" "No or not checked") |

## Upload And Submission Inputs

| Item | Status |
| --- | --- |
| \`FASTLANE_USER\` configured | $(status_from_bool "$fastlane_user_configured" "Yes ($(mask_value "${FASTLANE_USER:-}"))" "No") |
| \`APP_STORE_BUILD_NUMBER\` configured | $build_number_status |
| \`CONFIRM_UPLOAD_APP_PRIVACY=1\` | $(status_from_bool "$privacy_upload_confirmed" "Yes" "No") |
| \`CONFIRM_SUBMIT_FOR_REVIEW=1\` | $(status_from_bool "$submit_review_confirmed" "Yes" "No") |

## Account-Dependent Checks

Replace \`PROCESSED_BUILD_NUMBER\` with the processed App Store Connect build number before running selected-build commands; local validators intentionally reject that placeholder.

| Check | Command | When To Run |
| --- | --- | --- |
| Credential syntax | \`Scripts/check_app_store_connect_credentials.sh\` | After configuring API JSON or API key triplet. |
| App record, version, and selected build | \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state\` | After TestFlight processing completes. |
| TestFlight upload preflight | \`Scripts/preflight_testflight_upload.sh\` | After signing and App Store Connect credentials are configured. |
| App Review submission preflight | \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh\` | After listing fields, manual evidence, and selected build are final. |

## Required Next Actions

- [ ] Configure either \`APP_STORE_CONNECT_API_KEY_JSON\` or the \`ASC_KEY_ID\`, \`ASC_ISSUER_ID\`, and \`ASC_KEY_PATH\` triplet in untracked local release inputs.
- [ ] Run \`Scripts/check_app_store_connect_credentials.sh\`.
- [ ] Create or verify the App Store Connect app record for \`com.dannagrace.FreePrintStudio\`.
- [ ] Upload a signed IPA to TestFlight with \`Scripts/run_fastlane.sh ios upload_testflight\`.
- [ ] Wait for the build to finish processing, then set \`APP_STORE_BUILD_NUMBER\`.
- [ ] Run \`Scripts/run_fastlane.sh ios app_store_connect_state\`.
- [ ] Run \`Scripts/preflight_app_review_submission.sh\` before final submission.
EOF

printf 'App Store Connect readiness report generated: %s\n' "$output_path"
