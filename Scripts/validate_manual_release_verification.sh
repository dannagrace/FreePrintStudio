#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

EVIDENCE_PATH="${MANUAL_RELEASE_VERIFICATION_PATH:-$ROOT_DIR/Config/manual-release-verification.env}"
MAX_AGE_DAYS="${MANUAL_RELEASE_VERIFICATION_MAX_AGE_DAYS:-45}"
DEFAULT_AIRPRINT_RULER_TARGET_INCHES="${MANUAL_AIRPRINT_RULER_TARGET_DEFAULT_INCHES:-6}"
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

looks_like_processed_build_number() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]
}

validate_private_file_permissions() {
  local path="$1"
  local label="$2"

  python3 - "$path" "$label" <<'PY'
from pathlib import Path
import stat
import sys

path = Path(sys.argv[1]).expanduser()
label = sys.argv[2]

try:
    mode = path.stat().st_mode
except Exception:
    print(f"{label} permissions could not be checked")
    raise SystemExit(1)

if stat.S_IMODE(mode) & 0o077:
    print(f"{label} permissions are too broad; run chmod 600 on the configured file")
    raise SystemExit(1)
PY
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

require_physical_device_value() {
  local name="$1"
  local label="$2"
  local value
  local lower_value
  value="$(value_for "$name")"
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  if [[ -z "$value" ]]; then
    block "$label is missing ($name)"
  elif looks_placeholder_like "$value"; then
    block "$label still looks like a placeholder ($name)"
  elif [[ "$lower_value" == *"simulator"* ]]; then
    block "$label must be a physical device, not a simulator"
  else
    ok "$label recorded"
  fi
}

require_ipad_device_value() {
  local name="$1"
  local label="$2"
  local value
  local lower_value
  value="$(value_for "$name")"
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  if [[ -z "$value" ]]; then
    block "$label is missing ($name)"
  elif looks_placeholder_like "$value"; then
    block "$label still looks like a placeholder ($name)"
  elif [[ "$lower_value" == *"simulator"* ]]; then
    block "$label must be a physical iPad device, not a simulator"
  elif [[ "$lower_value" != *"ipad"* ]]; then
    block "$label must be a physical iPad device"
  else
    ok "$label recorded"
  fi
}

require_ios_version() {
  local name="$1"
  local label="$2"
  local value
  value="$(value_for "$name")"

  if [[ -z "$value" ]]; then
    block "$label is missing ($name)"
  elif looks_placeholder_like "$value"; then
    block "$label still looks like a placeholder ($name)"
  elif [[ "$value" =~ ^([iI][oO][sS][[:space:]]*)?[0-9]+(\.[0-9]+){0,2}$ ]]; then
    ok "$label recorded"
  else
    block "$label must be a numeric iOS version ($name), for example 18.5 or iOS 18.5"
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

require_airprint_ruler_measurement() {
  local target
  local target_value
  local measured
  local tolerance
  local measurement_status
  local missing=0
  target_value="$(value_for MANUAL_AIRPRINT_RULER_TARGET_INCHES)"
  target="$target_value"
  measured="$(value_for MANUAL_AIRPRINT_RULER_MEASURED_INCHES)"
  tolerance="${MANUAL_AIRPRINT_RULER_TOLERANCE_INCHES:-0.0625}"

  if [[ -z "$target_value" ]]; then
    target="$DEFAULT_AIRPRINT_RULER_TARGET_INCHES"
    ok "AirPrint ruler target length defaulted to $target inch(es)"
  elif looks_placeholder_like "$target_value"; then
    block "AirPrint ruler target length still looks like a placeholder (MANUAL_AIRPRINT_RULER_TARGET_INCHES)"
    missing=1
  fi

  if [[ -z "$measured" ]]; then
    block "AirPrint ruler measured length is missing (MANUAL_AIRPRINT_RULER_MEASURED_INCHES)"
    missing=1
  elif looks_placeholder_like "$measured"; then
    block "AirPrint ruler measured length still looks like a placeholder (MANUAL_AIRPRINT_RULER_MEASURED_INCHES)"
    missing=1
  fi

  if [[ "$missing" == "1" ]]; then
    return
  fi

  if ! measurement_status="$(python3 - "$target" "$measured" "$tolerance" <<'PY'
import math
import sys

target_raw, measured_raw, tolerance_raw = sys.argv[1:4]

def parse_positive(label: str, value: str) -> float:
    try:
        parsed = float(value)
    except ValueError:
        raise ValueError(f"{label} must be a positive decimal inch value")
    if not math.isfinite(parsed) or parsed <= 0:
        raise ValueError(f"{label} must be a positive decimal inch value")
    return parsed

try:
    target = parse_positive("AirPrint ruler target length", target_raw)
    measured = parse_positive("AirPrint ruler measured length", measured_raw)
    tolerance = parse_positive("AirPrint ruler measurement tolerance", tolerance_raw)
except ValueError as exc:
    print(str(exc))
    raise SystemExit(1)

delta = abs(target - measured)
if delta > tolerance:
    print(
        "AirPrint measured ruler length differs from target by "
        f"{delta:.4f} inch(es); maximum allowed is {tolerance:.4f}"
    )
    raise SystemExit(1)

print(f"AirPrint ruler measurement is within {tolerance:.4f} inch(es) of target")
PY
)"; then
    block "$measurement_status"
  else
    ok "$measurement_status"
  fi
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

  require_physical_device_value MANUAL_REAL_IPHONE_MODEL "Real iPhone model"
  require_ios_version MANUAL_REAL_IPHONE_IOS_VERSION "Real iPhone iOS version"
  require_recent_date MANUAL_REAL_IPHONE_TEST_DATE "Real iPhone verification"
  require_pass MANUAL_REAL_IPHONE_PHOTOS_IMPORT "Real iPhone Photos import"
  require_pass MANUAL_REAL_IPHONE_PDF_EXPORT "Real iPhone PDF export"
  require_pass MANUAL_REAL_IPHONE_PRINT_SHEET "Real iPhone print sheet"

  require_recent_date MANUAL_AIRPRINT_TEST_DATE "AirPrint verification"
  require_value MANUAL_AIRPRINT_PRINTER "AirPrint printer or production-equivalent workflow"
  require_pass MANUAL_AIRPRINT_EXACT_SIZE "AirPrint exact-size output"
  require_airprint_ruler_measurement

  require_value MANUAL_TESTFLIGHT_BUILD_NUMBER "TestFlight build number"
  require_physical_device_value MANUAL_TESTFLIGHT_DEVICE "TestFlight device"
  require_recent_date MANUAL_TESTFLIGHT_TEST_DATE "TestFlight verification"
  require_pass MANUAL_TESTFLIGHT_INSTALL "TestFlight install"
  require_pass MANUAL_TESTFLIGHT_PRINT_WORKFLOW "TestFlight print workflow"

  require_ipad_device_value MANUAL_IPAD_TESTFLIGHT_DEVICE "iPad TestFlight device"
  require_recent_date MANUAL_IPAD_TESTFLIGHT_TEST_DATE "iPad TestFlight verification"
  require_pass MANUAL_IPAD_TESTFLIGHT_INSTALL "iPad TestFlight install"
  require_pass MANUAL_IPAD_TESTFLIGHT_LAYOUT "iPad TestFlight layout"
  require_pass MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW "iPad TestFlight print workflow"
}

if [[ ! -f "$EVIDENCE_PATH" ]]; then
  block "Manual release verification evidence file is missing: Config/manual-release-verification.env"
  printf '  Install or sync generated private templates first: Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config\n'
  printf '  Then record real-device, AirPrint, iPad, and TestFlight evidence in Config/manual-release-verification.env before rerunning this validator.\n'
  validate_required_evidence_values
  printf '\nManual release verification evidence failed with %d issue(s).\n' "$failures"
  exit 1
fi

if ! permission_status="$(validate_private_file_permissions "$EVIDENCE_PATH" "Manual release verification evidence")"; then
  block "$permission_status"
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
  block "Manual release verification evidence is not a valid shell env file"
  while IFS= read -r source_line; do
    source_line="${source_line//$EVIDENCE_PATH/[configured manual evidence]}"
    printf '  %s\n' "$source_line"
  done </tmp/freeprintstudio-manual-evidence-source.log
  printf '  Quote values that contain spaces, for example MANUAL_REAL_IPHONE_MODEL=\"iPhone 15 Pro\".\n'
  exit 1
fi

validate_required_evidence_values

if [[ -n "${APP_STORE_BUILD_NUMBER:-}" ]] && looks_placeholder_like "$APP_STORE_BUILD_NUMBER"; then
  block "Selected App Store build still looks like a placeholder (APP_STORE_BUILD_NUMBER=$APP_STORE_BUILD_NUMBER)"
fi

if [[ -n "${APP_STORE_BUILD_NUMBER:-}" ]] \
  && ! looks_placeholder_like "$APP_STORE_BUILD_NUMBER" \
  && ! looks_like_processed_build_number "$APP_STORE_BUILD_NUMBER"; then
  block "Selected App Store build must be a processed App Store Connect build number (APP_STORE_BUILD_NUMBER=$APP_STORE_BUILD_NUMBER), for example 42 or 1.0.1"
fi

if [[ -n "${MANUAL_TESTFLIGHT_BUILD_NUMBER:-}" ]] \
  && ! looks_placeholder_like "$MANUAL_TESTFLIGHT_BUILD_NUMBER" \
  && ! looks_like_processed_build_number "$MANUAL_TESTFLIGHT_BUILD_NUMBER"; then
  block "TestFlight build number must be a processed App Store Connect build number (MANUAL_TESTFLIGHT_BUILD_NUMBER=$MANUAL_TESTFLIGHT_BUILD_NUMBER), for example 42 or 1.0.1"
fi

if [[ -n "${APP_STORE_BUILD_NUMBER:-}" && -n "${MANUAL_TESTFLIGHT_BUILD_NUMBER:-}" ]] \
  && ! looks_placeholder_like "$APP_STORE_BUILD_NUMBER" \
  && ! looks_placeholder_like "$MANUAL_TESTFLIGHT_BUILD_NUMBER" \
  && looks_like_processed_build_number "$APP_STORE_BUILD_NUMBER" \
  && looks_like_processed_build_number "$MANUAL_TESTFLIGHT_BUILD_NUMBER"; then
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
