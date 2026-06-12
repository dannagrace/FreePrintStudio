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

run_step "Local store-ready release gate" Scripts/verify_release.sh store-ready
run_step "Private release environment" Scripts/validate_release_env.sh
run_step "App Review contact" Scripts/validate_app_review_contact.sh
run_step "Code signing assets" Scripts/check_code_signing_assets.sh
run_step "App Store readiness audit" Scripts/check_app_store_readiness.sh

if (( failures > 0 )); then
  printf 'App Store archive preflight blocked with %d failed step(s).\n' "$failures"
  printf 'Fix the BLOCKED items above before running Scripts/archive_app_store.sh.\n'
  exit 1
fi

printf 'App Store archive preflight passed.\n'
printf 'Next: DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh\n'
