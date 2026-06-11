#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

EVIDENCE_PATH="${MANUAL_RELEASE_VERIFICATION_PATH:-$ROOT_DIR/Config/manual-release-verification.env}"
MAX_AGE_DAYS="${MANUAL_RELEASE_VERIFICATION_MAX_AGE_DAYS:-45}"
failures=0

ok() {
  printf 'OK: %s\n' "$1"
}

block() {
  printf 'BLOCKED: %s\n' "$1"
  failures=$((failures + 1))
}

value_for() {
  local name="$1"
  printf '%s' "${!name:-}"
}

looks_placeholder_like() {
  local value="$1"
  local lower_value
  [[ -z "$value" ]] && return 1
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  [[ "$value" == *YOUR* ]] && return 0
  [[ "$lower_value" == *todo* ]] && return 0
  [[ "$lower_value" == *tbd* ]] && return 0
  [[ "$lower_value" == *example* ]] && return 0
  [[ "$lower_value" == *placeholder* ]] && return 0
  [[ "$value" == "PROCESSED_BUILD_NUMBER" ]] && return 0
  return 1
}

require_value() {
  local name="$1"
  local label="$2"
  local value
  value="$(value_for "$name")"

  if [[ -z "$value" ]]; then
    block "$label is missing ($name)"
  elif looks_placeholder_like "$value"; then
    block "$label still looks like a placeholder ($name)"
  else
    ok "$label recorded"
  fi
}

require_pass() {
  local name="$1"
  local label="$2"
  local value
  local lower_value
  value="$(value_for "$name")"
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  case "$lower_value" in
    pass)
      ok "$label passed"
      ;;
    "")
      block "$label result is missing ($name=pass)"
      ;;
    *)
      block "$label result must be pass, found: $value"
      ;;
  esac
}

require_recent_date() {
  local name="$1"
  local label="$2"
  local value
  value="$(value_for "$name")"

  if [[ -z "$value" ]]; then
    block "$label date is missing ($name)"
    return
  fi

  if ! python3 - "$value" "$MAX_AGE_DAYS" <<'PY'
from datetime import date
import sys

value = sys.argv[1]
max_age_days = int(sys.argv[2])
try:
    checked = date.fromisoformat(value)
except ValueError:
    print(f"date must use YYYY-MM-DD, found: {value}")
    raise SystemExit(1)

today = date.today()
age = (today - checked).days
if age < 0:
    print(f"date is in the future: {value}")
    raise SystemExit(1)
if age > max_age_days:
    print(f"date is {age} days old, maximum allowed is {max_age_days}")
    raise SystemExit(1)
PY
  then
    block "$label date is not a recent YYYY-MM-DD value"
  else
    ok "$label date is recent"
  fi
}

validate_required_evidence_values() {
  require_value MANUAL_VERIFIER_NAME "Manual verifier"

  require_value MANUAL_REAL_IPHONE_MODEL "Real iPhone model"
  require_value MANUAL_REAL_IPHONE_IOS_VERSION "Real iPhone iOS version"
  require_recent_date MANUAL_REAL_IPHONE_TEST_DATE "Real iPhone verification"
  require_pass MANUAL_REAL_IPHONE_PHOTOS_IMPORT "Real iPhone Photos import"
  require_pass MANUAL_REAL_IPHONE_PDF_EXPORT "Real iPhone PDF export"
  require_pass MANUAL_REAL_IPHONE_PRINT_SHEET "Real iPhone print sheet"

  require_recent_date MANUAL_AIRPRINT_TEST_DATE "AirPrint verification"
  require_value MANUAL_AIRPRINT_PRINTER "AirPrint printer or production-equivalent workflow"
  require_pass MANUAL_AIRPRINT_EXACT_SIZE "AirPrint exact-size output"

  require_value MANUAL_TESTFLIGHT_BUILD_NUMBER "TestFlight build number"
  require_value MANUAL_TESTFLIGHT_DEVICE "TestFlight device"
  require_recent_date MANUAL_TESTFLIGHT_TEST_DATE "TestFlight verification"
  require_pass MANUAL_TESTFLIGHT_INSTALL "TestFlight install"
  require_pass MANUAL_TESTFLIGHT_PRINT_WORKFLOW "TestFlight print workflow"
}

if [[ ! -f "$EVIDENCE_PATH" ]]; then
  block "Manual release verification evidence file is missing: $EVIDENCE_PATH"
  printf '  Copy Config/manual-release-verification.env.example to Config/manual-release-verification.env after real-device testing.\n'
  validate_required_evidence_values
  printf '\nManual release verification evidence failed with %d issue(s).\n' "$failures"
  exit 1
fi

set +e
set -a
# shellcheck source=/dev/null
source "$EVIDENCE_PATH" >/tmp/freeprintstudio-manual-evidence-source.log 2>&1
source_status="$?"
set +a
set -e

if [[ "$source_status" -ne 0 ]]; then
  block "Manual release verification evidence is not a valid shell env file: $EVIDENCE_PATH"
  sed 's/^/  /' /tmp/freeprintstudio-manual-evidence-source.log
  printf '  Quote values that contain spaces, for example MANUAL_REAL_IPHONE_MODEL=\"iPhone 15 Pro\".\n'
  exit 1
fi

validate_required_evidence_values

if [[ -n "${APP_STORE_BUILD_NUMBER:-}" ]] && looks_placeholder_like "$APP_STORE_BUILD_NUMBER"; then
  block "Selected App Store build still looks like a placeholder (APP_STORE_BUILD_NUMBER=$APP_STORE_BUILD_NUMBER)"
fi

if [[ -n "${APP_STORE_BUILD_NUMBER:-}" && -n "${MANUAL_TESTFLIGHT_BUILD_NUMBER:-}" ]] \
  && ! looks_placeholder_like "$APP_STORE_BUILD_NUMBER" \
  && ! looks_placeholder_like "$MANUAL_TESTFLIGHT_BUILD_NUMBER"; then
  if [[ "$MANUAL_TESTFLIGHT_BUILD_NUMBER" == "$APP_STORE_BUILD_NUMBER" ]]; then
    ok "TestFlight build matches selected App Store build $APP_STORE_BUILD_NUMBER"
  else
    block "TestFlight build number $MANUAL_TESTFLIGHT_BUILD_NUMBER does not match selected APP_STORE_BUILD_NUMBER $APP_STORE_BUILD_NUMBER"
  fi
fi

if (( failures > 0 )); then
  printf '\nManual release verification evidence failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'Manual release verification evidence passed.\n'
