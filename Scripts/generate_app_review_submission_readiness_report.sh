#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

output_path="${1:-build/app-review-submission-readiness-report.md}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

usage() {
  cat <<'EOF'
Usage: Scripts/generate_app_review_submission_readiness_report.sh [output-path]

Generates a redacted App Review submission readiness report. The report is safe
to package because it records pass/blocker status without printing App Review
contact values, Apple IDs, App Store Connect key paths, private key contents,
manual evidence values, or raw validator output.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

mkdir -p "$(dirname "$output_path")"

ready_count=0
blocker_count=0
warning_count=0

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

run_step() {
  local status_variable="$1"
  local command_text="$2"
  shift 2
  local log_path
  local status
  log_path="$(mktemp)"

  set +e
  "$@" >"$log_path" 2>&1
  status="$?"
  set -e
  rm -f "$log_path"

  if [[ "$status" -eq 0 ]]; then
    printf -v "$status_variable" 'Pass'
    ready_count=$((ready_count + 1))
  else
    printf -v "$status_variable" 'Blocked; run `%s` for details' "$command_text"
    blocker_count=$((blocker_count + 1))
  fi
}

run_step status_metadata "Scripts/validate_app_store_metadata.sh" Scripts/validate_app_store_metadata.sh
run_step status_screenshots "Scripts/validate_screenshot_sync.sh" Scripts/validate_screenshot_sync.sh
run_step status_public_pages "Scripts/validate_public_pages.sh" Scripts/validate_public_pages.sh
run_step status_privacy_surface "Scripts/validate_privacy_surface.sh" Scripts/validate_privacy_surface.sh
run_step status_app_privacy "Scripts/validate_app_privacy_details.sh" Scripts/validate_app_privacy_details.sh
run_step status_questionnaires "Scripts/validate_app_store_questionnaires.sh" Scripts/validate_app_store_questionnaires.sh
run_step status_review_contact "Scripts/validate_app_review_contact.sh" Scripts/validate_app_review_contact.sh
run_step status_manual_evidence "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh" Scripts/validate_manual_release_verification.sh
run_step status_asc_credentials "Scripts/check_app_store_connect_credentials.sh" Scripts/check_app_store_connect_credentials.sh

if [[ -n "${APP_STORE_BUILD_NUMBER:-}" ]]; then
  if looks_placeholder_like "$APP_STORE_BUILD_NUMBER"; then
    status_selected_build='Blocked; `APP_STORE_BUILD_NUMBER` still uses a placeholder'
    blocker_count=$((blocker_count + 1))
    selected_build_ready=0
  else
    status_selected_build="Configured ($(mask_value "$APP_STORE_BUILD_NUMBER"))"
    ready_count=$((ready_count + 1))
    selected_build_ready=1
  fi
else
  status_selected_build='Blocked; set `APP_STORE_BUILD_NUMBER` to the processed App Store Connect build'
  blocker_count=$((blocker_count + 1))
  selected_build_ready=0
fi

if [[ "$status_asc_credentials" == "Pass" && "$selected_build_ready" == "1" ]]; then
  run_step status_asc_state "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/check_app_store_connect_state.sh" Scripts/check_app_store_connect_state.sh
else
  status_asc_state='Blocked; configure App Store Connect credentials and `APP_STORE_BUILD_NUMBER` before selected-build state can be checked'
  blocker_count=$((blocker_count + 1))
fi

cat >"$output_path" <<EOF
# FreePrint Studio App Review Submission Readiness Report

- Generated At: $generated_at
- This report is redacted: it does not print App Review contact values, Apple IDs, App Store Connect key paths, private key contents, manual evidence values, or raw validator output.
- Final preflight command: \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh\`
- Final submission command: \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review\`
- Selected build placeholder: replace \`PROCESSED_BUILD_NUMBER\` with the processed App Store Connect build number before running selected-build commands; local validators intentionally reject that placeholder.

## Summary

| Status | Count |
| --- | ---: |
| Ready submission checks | $ready_count |
| Blocking submission checks | $blocker_count |
| Warning submission checks | $warning_count |

## Store Listing And Policy Checks

| Check | Command | Status |
| --- | --- | --- |
| App Store metadata limits | \`Scripts/validate_app_store_metadata.sh\` | $status_metadata |
| Screenshot sync | \`Scripts/validate_screenshot_sync.sh\` | $status_screenshots |
| Public privacy/support pages | \`Scripts/validate_public_pages.sh\` | $status_public_pages |
| Privacy surface | \`Scripts/validate_privacy_surface.sh\` | $status_privacy_surface |
| App Privacy Details JSON | \`Scripts/validate_app_privacy_details.sh\` | $status_app_privacy |
| App Store questionnaires | \`Scripts/validate_app_store_questionnaires.sh\` | $status_questionnaires |

## Review And Evidence Checks

| Check | Command | Status |
| --- | --- | --- |
| App Review contact | \`Scripts/validate_app_review_contact.sh\` | $status_review_contact |
| Manual real-device, AirPrint, and TestFlight evidence | \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh\` | $status_manual_evidence |

## App Store Connect Checks

| Check | Command | Status |
| --- | --- | --- |
| API credentials | \`Scripts/check_app_store_connect_credentials.sh\` | $status_asc_credentials |
| Selected processed build value | \`APP_STORE_BUILD_NUMBER\` | $status_selected_build |
| App record, version, and selected build state | \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/check_app_store_connect_state.sh\` | $status_asc_state |

## Required Next Actions

- [ ] Resolve every blocking row above.
- [ ] Run \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh\`.
- [ ] Submit only after the preflight passes and the selected processed build matches the TestFlight evidence build.
- [ ] Run \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review\` for the final guarded submission.
EOF

printf 'App Review submission readiness report generated: %s\n' "$output_path"
