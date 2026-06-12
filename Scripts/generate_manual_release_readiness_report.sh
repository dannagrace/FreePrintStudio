#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

output_path="${1:-build/manual-release-readiness-report.md}"
evidence_path="${MANUAL_RELEASE_VERIFICATION_PATH:-$ROOT_DIR/Config/manual-release-verification.env}"
max_age_days="${MANUAL_RELEASE_VERIFICATION_MAX_AGE_DAYS:-45}"
airprint_ruler_tolerance="${MANUAL_AIRPRINT_RULER_TOLERANCE_INCHES:-0.0625}"
DEFAULT_AIRPRINT_RULER_TARGET_INCHES="${MANUAL_AIRPRINT_RULER_TARGET_DEFAULT_INCHES:-6}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

usage() {
  cat <<'EOF'
Usage: Scripts/generate_manual_release_readiness_report.sh [output-path]

Generates a redacted manual release readiness report. The report is safe to
package because it summarizes real-device, AirPrint, and TestFlight evidence
status without printing verifier names, device names, printer names, screenshots,
private notes, or full build identifiers.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

mkdir -p "$(dirname "$output_path")"

failures=0
ready_count=0
warning_count=0
evidence_file_exists=0
evidence_permission_status='Not checked'
evidence_source_valid=0

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
  [[ "$value" == *YOUR_* ]] && return 0
  [[ "$lower_value" == *todo* ]] && return 0
  [[ "$lower_value" == *tbd* ]] && return 0
  [[ "$lower_value" == *example* ]] && return 0
  [[ "$lower_value" == *placeholder* ]] && return 0
  [[ "$value" == "PROCESSED_BUILD_NUMBER" ]] && return 0
  return 1
}

manual_evidence_permissions_status() {
  local path="$1"

  python3 - "$path" <<'PY'
from pathlib import Path
import stat
import sys

path = Path(sys.argv[1]).expanduser()

try:
    mode = path.stat().st_mode
except Exception:
    print("Could not be checked")
    raise SystemExit(1)

if stat.S_IMODE(mode) & 0o077:
    print("Too broad; run `chmod 600 Config/manual-release-verification.env`")
    raise SystemExit(1)

print("Private")
PY
}

record_ready() {
  ready_count=$((ready_count + 1))
}

record_failure() {
  failures=$((failures + 1))
}

record_warning() {
  warning_count=$((warning_count + 1))
}

value_status() {
  local name="$1"
  local value
  value="$(value_for "$name")"
  if [[ -z "$value" ]]; then
    record_failure
    status_result='Missing'
  elif looks_placeholder_like "$value"; then
    record_failure
    status_result='Placeholder-like'
  else
    record_ready
    status_result='Recorded; value redacted'
  fi
}

ios_version_status() {
  local name="$1"
  local value
  value="$(value_for "$name")"
  if [[ -z "$value" ]]; then
    record_failure
    status_result='Missing; expected numeric iOS version'
  elif looks_placeholder_like "$value"; then
    record_failure
    status_result='Placeholder-like'
  elif [[ "$value" =~ ^([iI][oO][sS][[:space:]]*)?[0-9]+(\.[0-9]+){0,2}$ ]]; then
    record_ready
    status_result='Recorded; numeric iOS version'
  else
    record_failure
    status_result='Invalid; expected numeric iOS version'
  fi
}

pass_status() {
  local name="$1"
  local value
  local lower_value
  value="$(value_for "$name")"
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$lower_value" in
    pass)
      record_ready
      status_result='Pass'
      ;;
    "")
      record_failure
      status_result='Missing; expected pass'
      ;;
    *)
      record_failure
      status_result='Not pass; value redacted'
      ;;
  esac
}

airprint_target_status() {
  local value
  value="$(value_for MANUAL_AIRPRINT_RULER_TARGET_INCHES)"
  if [[ -z "$value" ]]; then
    record_ready
    status_result="Defaulted to built-in ${DEFAULT_AIRPRINT_RULER_TARGET_INCHES} inch Test Ruler target"
  else
    value_status MANUAL_AIRPRINT_RULER_TARGET_INCHES
  fi
}

date_status() {
  local name="$1"
  local value
  local result
  value="$(value_for "$name")"
  if [[ -z "$value" ]]; then
    record_failure
    status_result='Missing; expected YYYY-MM-DD'
    return
  fi

  result="$(python3 - "$value" "$max_age_days" <<'PY'
from datetime import date
import sys

value = sys.argv[1]
max_age_days = int(sys.argv[2])
try:
    checked = date.fromisoformat(value)
except ValueError:
    print("invalid")
    raise SystemExit(0)

today = date.today()
age = (today - checked).days
if age < 0:
    print("future")
elif age > max_age_days:
    print(f"stale:{age}")
else:
    print(f"recent:{age}")
PY
)"

  case "$result" in
    recent:*)
      record_ready
      status_result="Recent; ${result#recent:} day(s) old"
      ;;
    stale:*)
      record_failure
      status_result="Stale; ${result#stale:} day(s) old, maximum $max_age_days"
      ;;
    future)
      record_failure
      status_result='Future date'
      ;;
    *)
      record_failure
      status_result='Invalid; expected YYYY-MM-DD'
      ;;
  esac
}

airprint_measurement_status() {
  local target_raw="${MANUAL_AIRPRINT_RULER_TARGET_INCHES:-}"
  local target="${target_raw:-$DEFAULT_AIRPRINT_RULER_TARGET_INCHES}"
  local measured="${MANUAL_AIRPRINT_RULER_MEASURED_INCHES:-}"
  local result

  if [[ -z "$measured" ]]; then
    record_failure
    status_result='Missing measured ruler length'
    return
  fi

  if looks_placeholder_like "$target_raw" || looks_placeholder_like "$measured"; then
    record_failure
    status_result='Placeholder-like target or measured ruler length'
    return
  fi

  result="$(python3 - "$target" "$measured" "$airprint_ruler_tolerance" <<'PY'
import math
import sys

target_raw, measured_raw, tolerance_raw = sys.argv[1:4]

def parse_positive(value: str) -> float:
    try:
        parsed = float(value)
    except ValueError:
        raise ValueError
    if not math.isfinite(parsed) or parsed <= 0:
        raise ValueError
    return parsed

try:
    target = parse_positive(target_raw)
    measured = parse_positive(measured_raw)
    tolerance = parse_positive(tolerance_raw)
except ValueError:
    print("invalid")
    raise SystemExit(0)

delta = abs(target - measured)
if delta > tolerance:
    print("outside")
else:
    print("within")
PY
)"

  case "$result" in
    within)
      record_ready
      status_result="Within ${airprint_ruler_tolerance} inch tolerance"
      ;;
    outside)
      record_failure
      status_result="Outside ${airprint_ruler_tolerance} inch tolerance"
      ;;
    *)
      record_failure
      status_result='Invalid decimal inch measurement'
      ;;
  esac
}

build_match_status() {
  local selected_build="${APP_STORE_BUILD_NUMBER:-}"
  local tested_build="${MANUAL_TESTFLIGHT_BUILD_NUMBER:-}"
  if [[ -z "$selected_build" && -z "$tested_build" ]]; then
    record_failure
    status_result='Missing selected App Store build and TestFlight evidence build'
  elif [[ -z "$selected_build" ]]; then
    record_warning
    status_result="Selected App Store build missing; TestFlight evidence build is $(mask_value "$tested_build")"
  elif looks_placeholder_like "$selected_build"; then
    record_failure
    status_result='Selected App Store build still uses a placeholder'
  elif [[ -z "$tested_build" ]]; then
    record_failure
    status_result="TestFlight evidence build missing; selected build is $(mask_value "$selected_build")"
  elif looks_placeholder_like "$tested_build"; then
    record_failure
    status_result='TestFlight evidence build still uses a placeholder'
  elif [[ "$selected_build" == "$tested_build" ]]; then
    record_ready
    status_result="Match ($(mask_value "$selected_build"))"
  else
    record_failure
    status_result="Mismatch; selected $(mask_value "$selected_build"), evidence $(mask_value "$tested_build")"
  fi
}

if [[ -f "$evidence_path" ]]; then
  evidence_file_exists=1
  if evidence_permission_status="$(manual_evidence_permissions_status "$evidence_path" 2>&1)"; then
    set +e
    set -a
    # shellcheck source=/dev/null
    source "$evidence_path" >/tmp/freeprintstudio-manual-report-source.log 2>&1
    source_status="$?"
    set +a
    set -e
    if [[ "$source_status" -eq 0 ]]; then
      evidence_source_valid=1
    else
      record_failure
    fi
  else
    record_failure
  fi
else
  evidence_permission_status='Not checked; evidence file missing'
  record_failure
fi

value_status MANUAL_VERIFIER_NAME
status_verifier_name="$status_result"
value_status MANUAL_REAL_IPHONE_MODEL
status_iphone_model="$status_result"
ios_version_status MANUAL_REAL_IPHONE_IOS_VERSION
status_iphone_ios_version="$status_result"
date_status MANUAL_REAL_IPHONE_TEST_DATE
status_iphone_test_date="$status_result"
pass_status MANUAL_REAL_IPHONE_PHOTOS_IMPORT
status_iphone_photos_import="$status_result"
pass_status MANUAL_REAL_IPHONE_PDF_EXPORT
status_iphone_pdf_export="$status_result"
pass_status MANUAL_REAL_IPHONE_PRINT_SHEET
status_iphone_print_sheet="$status_result"
date_status MANUAL_AIRPRINT_TEST_DATE
status_airprint_test_date="$status_result"
value_status MANUAL_AIRPRINT_PRINTER
status_airprint_printer="$status_result"
pass_status MANUAL_AIRPRINT_EXACT_SIZE
status_airprint_exact_size="$status_result"
airprint_target_status
status_airprint_ruler_target="$status_result"
value_status MANUAL_AIRPRINT_RULER_MEASURED_INCHES
status_airprint_ruler_measured="$status_result"
airprint_measurement_status
status_airprint_ruler_measurement="$status_result"
value_status MANUAL_TESTFLIGHT_BUILD_NUMBER
status_testflight_build_number="$status_result"
value_status MANUAL_TESTFLIGHT_DEVICE
status_testflight_device="$status_result"
date_status MANUAL_TESTFLIGHT_TEST_DATE
status_testflight_test_date="$status_result"
pass_status MANUAL_TESTFLIGHT_INSTALL
status_testflight_install="$status_result"
pass_status MANUAL_TESTFLIGHT_PRINT_WORKFLOW
status_testflight_print_workflow="$status_result"
build_match_status
status_build_match="$status_result"

cat >"$output_path" <<EOF
# FreePrint Studio Manual Release Readiness Report

- Generated At: $generated_at
- This report is redacted: it does not print verifier names, device names, printer names, screenshots, private notes, or full build identifiers.
- Evidence file configured: $(if [[ "$evidence_file_exists" == "1" ]]; then printf 'Yes'; else printf 'No'; fi)
- Evidence file permissions: $evidence_permission_status
- Evidence file parses as shell env: $(if [[ "$evidence_source_valid" == "1" ]]; then printf 'Yes'; else printf 'No or not checked'; fi)
- Maximum evidence age: $max_age_days day(s)
- Strict validation command: \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh\`
- Evidence form command: \`Scripts/verify_release.sh manual-evidence-form\`
- Status command: \`Scripts/print_release_input_status.sh --strict\`
- Selected build placeholder: replace \`PROCESSED_BUILD_NUMBER\` with the processed App Store Connect build number before running selected-build commands; local validators intentionally reject that placeholder.

## Summary

| Status | Count |
| --- | ---: |
| Ready evidence checks | $ready_count |
| Blocking evidence checks | $failures |
| Warning evidence checks | $warning_count |

## Real iPhone Evidence

| Evidence | Env field | Status |
| --- | --- | --- |
| Verifier name or team | \`MANUAL_VERIFIER_NAME\` | $status_verifier_name |
| iPhone model | \`MANUAL_REAL_IPHONE_MODEL\` | $status_iphone_model |
| iOS version | \`MANUAL_REAL_IPHONE_IOS_VERSION\` | $status_iphone_ios_version |
| Test date | \`MANUAL_REAL_IPHONE_TEST_DATE\` | $status_iphone_test_date |
| Photos import succeeds | \`MANUAL_REAL_IPHONE_PHOTOS_IMPORT\` | $status_iphone_photos_import |
| Exact-size PDF export succeeds | \`MANUAL_REAL_IPHONE_PDF_EXPORT\` | $status_iphone_pdf_export |
| System print sheet opens | \`MANUAL_REAL_IPHONE_PRINT_SHEET\` | $status_iphone_print_sheet |

## AirPrint Evidence

| Evidence | Env field | Status |
| --- | --- | --- |
| Test date | \`MANUAL_AIRPRINT_TEST_DATE\` | $status_airprint_test_date |
| Printer or production-equivalent workflow | \`MANUAL_AIRPRINT_PRINTER\` | $status_airprint_printer |
| 0-6 inch ruler prints at exact size | \`MANUAL_AIRPRINT_EXACT_SIZE\` | $status_airprint_exact_size |
| Target ruler length | \`MANUAL_AIRPRINT_RULER_TARGET_INCHES\` | $status_airprint_ruler_target |
| Measured printed ruler length | \`MANUAL_AIRPRINT_RULER_MEASURED_INCHES\` | $status_airprint_ruler_measured |
| Target and measured length are within tolerance | \`MANUAL_AIRPRINT_RULER_TARGET_INCHES\` and \`MANUAL_AIRPRINT_RULER_MEASURED_INCHES\` | $status_airprint_ruler_measurement |

## TestFlight Evidence

| Evidence | Env field | Status |
| --- | --- | --- |
| TestFlight build number | \`MANUAL_TESTFLIGHT_BUILD_NUMBER\` | $status_testflight_build_number |
| TestFlight device | \`MANUAL_TESTFLIGHT_DEVICE\` | $status_testflight_device |
| Test date | \`MANUAL_TESTFLIGHT_TEST_DATE\` | $status_testflight_test_date |
| TestFlight install succeeds | \`MANUAL_TESTFLIGHT_INSTALL\` | $status_testflight_install |
| Print workflow succeeds from TestFlight build | \`MANUAL_TESTFLIGHT_PRINT_WORKFLOW\` | $status_testflight_print_workflow |
| Selected build matches evidence build | \`APP_STORE_BUILD_NUMBER\` and \`MANUAL_TESTFLIGHT_BUILD_NUMBER\` | $status_build_match |

## Required Next Actions

- [ ] Run \`Scripts/bootstrap_release_inputs.sh\` to create the git-ignored evidence file if it is missing.
- [ ] Fill \`Config/manual-release-verification.env\` only after real iPhone, AirPrint, and TestFlight checks.
- [ ] Set \`APP_STORE_BUILD_NUMBER\` to the processed build selected in App Store Connect.
- [ ] Run \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh\`.
- [ ] Run \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh\`.
EOF

printf 'Manual release readiness report generated: %s\n' "$output_path"
