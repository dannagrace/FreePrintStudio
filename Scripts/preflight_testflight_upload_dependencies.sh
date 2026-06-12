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

run_step "Release input status" Scripts/print_release_input_status.sh --strict
run_step "Private release environment" Scripts/validate_release_env.sh
run_step "App Store Connect credentials" Scripts/check_app_store_connect_credentials.sh
run_step "App Store Connect app and version" env APP_STORE_CONNECT_SKIP_BUILD_CHECK=1 Scripts/check_app_store_connect_state.sh

if (( failures > 0 )); then
  printf 'TestFlight upload dependency preflight blocked with %d failed step(s).\n' "$failures"
  printf 'Fix the BLOCKED items above before creating or uploading a TestFlight archive.\n'
  exit 1
fi

printf 'TestFlight upload dependency preflight passed.\n'
printf 'Next: Scripts/run_fastlane.sh ios upload_testflight\n'
