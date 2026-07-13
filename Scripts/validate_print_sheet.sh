#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="com.dannagrace.FreePrintStudio"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/freeprintstudio-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/FreePrintStudio.app"
SAMPLE_IMAGE="$ROOT_DIR/AppStore/Assets/sample-print-image.png"
SCREENSHOT_PATH="${PRINT_SHEET_SCREENSHOT_PATH:-/tmp/freeprintstudio-print-sheet-validation.jpg}"
SIMCTL_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SIMCTL_TIMEOUT_SECONDS:-30}"

Scripts/generate_store_sample_image.py

candidate_simulators() {
  if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    printf '%s\n' "$SIMULATOR_UDID"
    return
  fi

  local device_pattern
  local fallback_device_name
  device_pattern="${FREEPRINTSTUDIO_IPHONE_DEVICE_PATTERN:-iPhone 17 Pro Max|iPhone Air|iPhone 16 Pro Max|iPhone 16 Plus|iPhone 15 Pro Max|iPhone 15 Plus|iPhone 14 Pro Max}"
  fallback_device_name="${FREEPRINTSTUDIO_DEVICE_FALLBACK_NAME:-iPhone}"

  xcrun simctl list devices booted \
    | grep -E "$device_pattern" \
    | sed -nE 's/.*\(([A-F0-9-]{36})\).*/\1/p'
  xcrun simctl list devices available \
    | grep -E "$device_pattern" \
    | sed -nE 's/.*\(([A-F0-9-]{36})\).*/\1/p'
  xcrun simctl list devices booted \
    | sed -nE "/$fallback_device_name/s/.*\\(([A-F0-9-]{36})\\).*/\\1/p"
  xcrun simctl list devices available \
    | sed -nE "/$fallback_device_name/s/.*\\(([A-F0-9-]{36})\\).*/\\1/p"
}

unique_candidate_simulators() {
  candidate_simulators | awk 'NF && !seen[$0]++'
}

boot_simulator() {
  local device="$1"
  if [[ "$device" != "booted" ]]; then
    xcrun simctl boot "$device" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$device" -b >/dev/null
  fi
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout_text = sys.argv[1]
command = sys.argv[2:]
try:
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=float(timeout_text),
    )
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        print(exc.stdout, end="")
    print(f"{' '.join(command)} timed out after {timeout_text} seconds")
    sys.exit(124)

if result.stdout:
    print(result.stdout, end="")
sys.exit(result.returncode)
PY
}

select_installed_simulator() {
  local candidate
  local candidates
  local install_output
  candidates="$(unique_candidate_simulators)"
  if [[ -z "$candidates" ]]; then
    printf 'No available iPhone simulator found. Set SIMULATOR_UDID to a booted simulator UDID.\n' >&2
    exit 1
  fi

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    printf 'Trying simulator: %s\n' "$candidate" >&2
    boot_simulator "$candidate"
    install_output=""
    if install_output="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl install "$candidate" "$APP_PATH" 2>&1)"; then
      if [[ -n "$install_output" ]]; then
        printf '%s\n' "$install_output" >&2
      fi
      printf '%s\n' "$candidate"
      return
    fi
    if [[ -n "$install_output" ]]; then
      printf '%s\n' "$install_output" >&2
    fi
    printf 'Skipping simulator after install failure: %s\n' "$candidate" >&2
  done <<<"$candidates"

  printf 'No simulator accepted the print sheet validation app install.\n' >&2
  exit 1
}

xcodebuild \
  -project FreePrintStudio.xcodeproj \
  -scheme FreePrintStudio \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  build >/tmp/freeprintstudio-print-sheet-build.log

DEVICE="$(select_installed_simulator)"
printf 'Using simulator: %s\n' "$DEVICE"

CONTAINER="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)"
TEST_DIR="$CONTAINER/Documents/FreePrintStudioPrintSheetValidation"
STATUS_PATH="$TEST_DIR/print-sheet-status.txt"
mkdir -p "$TEST_DIR"
rm -f "$STATUS_PATH" "$SCREENSHOT_PATH"
cp "$SAMPLE_IMAGE" "$TEST_DIR/sample-print-image.png"

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
  -FreePrintStudioTestImagePath "$TEST_DIR/sample-print-image.png" \
  -FreePrintStudioPaper letter \
  -FreePrintStudioOrientation portrait \
  -FreePrintStudioUnit inch \
  -FreePrintStudioFitMode fit \
  -FreePrintStudioTargetWidth 4 \
  -FreePrintStudioTargetHeight 6 \
  -FreePrintStudioAutoOpenPrintSheet \
  -FreePrintStudioPrintSheetStatusPath "$STATUS_PATH" \
  >/tmp/freeprintstudio-print-sheet-launch.log

for _ in {1..40}; do
  if [[ -s "$STATUS_PATH" ]] && grep -q '^presented$' "$STATUS_PATH"; then
    break
  fi
  sleep 0.5
done

if [[ ! -s "$STATUS_PATH" ]]; then
  printf 'Timed out waiting for print sheet validation status: %s\n' "$STATUS_PATH"
  exit 1
fi

status="$(cat "$STATUS_PATH")"
if [[ "$status" != "presented" ]]; then
  printf 'Print sheet validation failed: %s\n' "$status"
  exit 1
fi

sleep 1
xcrun simctl io "$DEVICE" screenshot --type=jpeg "$SCREENSHOT_PATH" >/tmp/freeprintstudio-print-sheet-screenshot.log
if [[ ! -s "$SCREENSHOT_PATH" ]]; then
  printf 'Print sheet validation screenshot missing: %s\n' "$SCREENSHOT_PATH"
  exit 1
fi

printf 'Print sheet validation passed. Screenshot written to %s\n' "$SCREENSHOT_PATH"
