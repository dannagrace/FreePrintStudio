#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

failures=0

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
  else
    printf 'OK: APP_STORE_BUILD_NUMBER is set to %s\n' "$APP_STORE_BUILD_NUMBER"
  fi
  printf '\n'
}

run_step "App Store metadata" Scripts/validate_app_store_metadata.sh
run_step "Screenshot sync" Scripts/validate_screenshot_sync.sh
run_step "Privacy surface" Scripts/validate_privacy_surface.sh
run_step "App Privacy Details" Scripts/validate_app_privacy_details.sh
run_step "App Store questionnaires" Scripts/validate_app_store_questionnaires.sh
run_step "App Review contact" Scripts/validate_app_review_contact.sh
run_step "Manual release verification evidence" Scripts/validate_manual_release_verification.sh
run_step "App Store Connect credentials" Scripts/check_app_store_connect_credentials.sh
run_build_number_step
run_step "App Store Connect selected build" Scripts/check_app_store_connect_state.sh

if (( failures > 0 )); then
  printf 'App Review submission preflight blocked with %d failed step(s).\n' "$failures"
  printf 'Fix the BLOCKED items above before running Scripts/run_fastlane.sh ios submit_review.\n'
  exit 1
fi

printf 'App Review submission preflight passed.\n'
printf 'Next: APP_STORE_BUILD_NUMBER=%s CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review\n' "$APP_STORE_BUILD_NUMBER"
