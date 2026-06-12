#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

failures=0

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
  local title="$1"
  shift

  printf '== %s ==\n' "$title"
  set +e
  "$@"
  local status="$?"
  set -e

  if [[ "$status" -ne 0 ]]; then
    printf 'BLOCKED: %s failed with exit code %s\n' "$title" "$status"
    failures=$((failures + 1))
  fi
  printf '\n'
}

run_build_number_step() {
  printf '== Selected App Store build ==\n'
  if [[ -z "${APP_STORE_BUILD_NUMBER:-}" ]]; then
    printf 'BLOCKED: APP_STORE_BUILD_NUMBER is missing; set it to the processed App Store Connect build number.\n'
    failures=$((failures + 1))
  elif [[ "$APP_STORE_BUILD_NUMBER" == "PROCESSED_BUILD_NUMBER" ]]; then
    printf 'BLOCKED: APP_STORE_BUILD_NUMBER still uses the PROCESSED_BUILD_NUMBER placeholder.\n'
    failures=$((failures + 1))
  elif looks_placeholder_like "$APP_STORE_BUILD_NUMBER"; then
    printf 'BLOCKED: APP_STORE_BUILD_NUMBER still looks like a placeholder; set it to the processed App Store Connect build number.\n'
    failures=$((failures + 1))
  else
    printf 'OK: APP_STORE_BUILD_NUMBER is set to %s\n' "$APP_STORE_BUILD_NUMBER"
  fi
  printf '\n'
}

run_step "Private release environment" Scripts/validate_release_env.sh
run_build_number_step
run_step "App Store metadata" Scripts/validate_app_store_metadata.sh
run_step "Screenshot sync" Scripts/validate_screenshot_sync.sh
run_step "Screenshot privacy metadata" Scripts/validate_screenshot_privacy.sh
run_step "Public privacy and support pages" Scripts/validate_public_pages.sh
run_step "Privacy surface" Scripts/validate_privacy_surface.sh
run_step "App Privacy Details" Scripts/validate_app_privacy_details.sh
run_step "App Privacy Details App Store Connect confirmation" Scripts/validate_app_privacy_connect_entry.sh
run_step "App Store questionnaires" Scripts/validate_app_store_questionnaires.sh
run_step "App Review contact" Scripts/validate_app_review_contact.sh
run_step "Manual release verification evidence" Scripts/validate_manual_release_verification.sh
run_step "App Store Connect credentials" Scripts/check_app_store_connect_credentials.sh
run_step "App Store Connect selected build" Scripts/check_app_store_connect_state.sh

if (( failures > 0 )); then
  printf 'App Review submission preflight blocked with %d failed step(s).\n' "$failures"
  printf 'Fix the BLOCKED items above before running Scripts/run_fastlane.sh ios submit_review.\n'
  exit 1
fi

printf 'App Review submission preflight passed.\n'
printf 'Next: APP_STORE_BUILD_NUMBER=%s CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review\n' "$APP_STORE_BUILD_NUMBER"
