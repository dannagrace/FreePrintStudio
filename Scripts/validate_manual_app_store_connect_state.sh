#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

failures=0
max_age_days="${APP_STORE_CONNECT_MANUAL_STATE_MAX_AGE_DAYS:-7}"

ok() {
  printf 'OK: %s\n' "$1"
}

block() {
  printf 'BLOCKED: %s\n' "$1"
  failures=$((failures + 1))
}

if [[ "${APP_STORE_CONNECT_SUBMISSION_MODE:-}" != "manual" ]]; then
  block "APP_STORE_CONNECT_SUBMISSION_MODE must be manual for browser-confirmed App Store Connect state"
fi

if [[ "${APP_STORE_CONNECT_MANUAL_STATE_CONFIRMED:-}" == "1" ]]; then
  ok "Manual App Store Connect state confirmation is recorded"
else
  block "APP_STORE_CONNECT_MANUAL_STATE_CONFIRMED must be 1 after checking the App Store version page"
fi

if [[ -z "${APP_STORE_BUILD_NUMBER:-}" ]]; then
  block "APP_STORE_BUILD_NUMBER is missing"
elif [[ ! "$APP_STORE_BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  block "APP_STORE_BUILD_NUMBER is not a valid processed build number"
elif [[ -z "${APP_STORE_CONNECT_MANUAL_STATE_BUILD_NUMBER:-}" ]]; then
  block "APP_STORE_CONNECT_MANUAL_STATE_BUILD_NUMBER is missing"
elif [[ "$APP_STORE_CONNECT_MANUAL_STATE_BUILD_NUMBER" != "$APP_STORE_BUILD_NUMBER" ]]; then
  block "APP_STORE_CONNECT_MANUAL_STATE_BUILD_NUMBER does not match APP_STORE_BUILD_NUMBER"
else
  ok "Manual App Store Connect state matches selected build $APP_STORE_BUILD_NUMBER"
fi

if [[ -z "${APP_STORE_CONNECT_MANUAL_STATE_VERIFIED_DATE:-}" ]]; then
  block "APP_STORE_CONNECT_MANUAL_STATE_VERIFIED_DATE is missing"
elif ! date_status="$(python3 - "$APP_STORE_CONNECT_MANUAL_STATE_VERIFIED_DATE" "$max_age_days" <<'PY'
from datetime import date
import sys

value = sys.argv[1]
try:
    max_age = int(sys.argv[2])
except ValueError:
    print("APP_STORE_CONNECT_MANUAL_STATE_MAX_AGE_DAYS must be a non-negative integer")
    raise SystemExit(1)

if max_age < 0:
    print("APP_STORE_CONNECT_MANUAL_STATE_MAX_AGE_DAYS must be a non-negative integer")
    raise SystemExit(1)

try:
    verified = date.fromisoformat(value)
except ValueError:
    print("APP_STORE_CONNECT_MANUAL_STATE_VERIFIED_DATE must use YYYY-MM-DD")
    raise SystemExit(1)

age = (date.today() - verified).days
if age < 0:
    print("APP_STORE_CONNECT_MANUAL_STATE_VERIFIED_DATE cannot be in the future")
    raise SystemExit(1)
if age > max_age:
    print(f"Manual App Store Connect state confirmation is stale ({age} days old; maximum {max_age})")
    raise SystemExit(1)

print(f"Manual App Store Connect state confirmation is current ({age} days old)")
PY
)"; then
  block "$date_status"
else
  ok "$date_status"
fi

if (( failures > 0 )); then
  printf '\nRe-open the App Store version page, confirm the selected processed build and submission-ready state, then update the manual state fields in Config/release.env.\n'
  exit 1
fi

