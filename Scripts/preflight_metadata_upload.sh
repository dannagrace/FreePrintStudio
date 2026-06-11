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

run_app_version_step() {
  printf '== App Store Connect app and version ==\n'
  set +e
  APP_STORE_CONNECT_SKIP_BUILD_CHECK=1 Scripts/check_app_store_connect_state.sh
  local status="$?"
  set -e

  if [[ "$status" -ne 0 ]]; then
    printf 'BLOCKED: App Store Connect app and version failed with exit code %s\n' "$status"
    failures=$((failures + 1))
  fi
  printf '\n'
}

run_step "Private release environment" Scripts/validate_release_env.sh
run_step "App Store metadata" Scripts/validate_app_store_metadata.sh
run_step "Screenshot sync" Scripts/validate_screenshot_sync.sh
run_step "App Store questionnaires" Scripts/validate_app_store_questionnaires.sh
run_step "App Review contact" Scripts/validate_app_review_contact.sh
run_step "App Store Connect credentials" Scripts/check_app_store_connect_credentials.sh
run_app_version_step

if (( failures > 0 )); then
  printf 'Metadata upload preflight blocked with %d failed step(s).\n' "$failures"
  printf 'Fix the BLOCKED items above before running Scripts/run_fastlane.sh ios metadata.\n'
  exit 1
fi

printf 'Metadata upload preflight passed.\n'
printf 'Next: Scripts/run_fastlane.sh ios metadata\n'
