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

run_confirmation_step() {
  printf '== App Privacy upload confirmation ==\n'
  if [[ "${CONFIRM_UPLOAD_APP_PRIVACY:-}" == "1" ]]; then
    printf 'OK: CONFIRM_UPLOAD_APP_PRIVACY=1\n'
  else
    printf 'BLOCKED: Set CONFIRM_UPLOAD_APP_PRIVACY=1 after reviewing AppStore/app_privacy_details.json against AppStore/app-privacy.md.\n'
    failures=$((failures + 1))
  fi
  printf '\n'
}

run_fastlane_user_step() {
  printf '== Fastlane Apple ID ==\n'
  if [[ -n "${FASTLANE_USER:-}" ]]; then
    printf 'OK: FASTLANE_USER is configured\n'
  else
    printf 'BLOCKED: FASTLANE_USER is missing; set it to the Apple ID used for App Store Connect.\n'
    failures=$((failures + 1))
  fi
  printf '\n'
}

run_step "Release input status" Scripts/print_release_input_status.sh --strict --scope app-privacy-upload
run_confirmation_step
run_fastlane_user_step
run_step "Private release environment" Scripts/validate_release_env.sh
run_step "Privacy surface" Scripts/validate_privacy_surface.sh
run_step "App Privacy Details" Scripts/validate_app_privacy_details.sh
run_step "App Store questionnaires" Scripts/validate_app_store_questionnaires.sh

if (( failures > 0 )); then
  printf 'App Privacy Details upload preflight blocked with %d failed step(s).\n' "$failures"
  printf 'Fix the BLOCKED items above before running Scripts/run_fastlane.sh ios privacy_details.\n'
  exit 1
fi

printf 'App Privacy Details upload preflight passed.\n'
printf 'Next: CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details\n'
printf 'Run the command from an environment where FASTLANE_USER is already configured.\n'
