#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "${SIMULATOR_UDID:-}" ]]; then
  DEVICE="$SIMULATOR_UDID"
else
  IPHONE_DEVICE_PATTERN="${FREEPRINTSTUDIO_IPHONE_DEVICE_PATTERN:-iPhone 17 Pro Max|iPhone Air|iPhone 16 Pro Max|iPhone 16 Plus|iPhone 15 Pro Max|iPhone 15 Plus|iPhone 14 Pro Max}"
  DEVICE="$(
    xcrun simctl list devices available \
      | grep -E "$IPHONE_DEVICE_PATTERN" \
      | sed -nE 's/.*\(([A-F0-9-]{36})\).*/\1/p' \
      | head -n 1 || true
  )"
  if [[ -z "$DEVICE" ]]; then
    DEVICE="$(
      xcrun simctl list devices available \
      | sed -nE '/iPhone/s/.*\(([A-F0-9-]{36})\).*/\1/p' \
      | head -n 1
    )"
  fi
  if [[ -z "$DEVICE" ]]; then
    DEVICE="$(
      xcrun simctl list devices booted \
      | sed -nE 's/.*iPhone.*\(([A-F0-9-]{36})\).*/\1/p' \
      | head -n 1
    )"
  fi
  if [[ -z "$DEVICE" ]]; then
    printf 'No available iPhone simulator found. Set SIMULATOR_UDID to a booted simulator UDID.\n'
    exit 1
  fi
fi

BUNDLE_ID="com.dannagrace.FreePrintStudio"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/freeprintstudio-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/FreePrintStudio.app"
SAMPLE_IMAGE="$ROOT_DIR/AppStore/Assets/sample-print-image.png"
SCREENSHOT_PATH="${PRINT_SHEET_SCREENSHOT_PATH:-/tmp/freeprintstudio-print-sheet-validation.jpg}"

Scripts/generate_store_sample_image.py

if [[ "$DEVICE" != "booted" ]]; then
  xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$DEVICE" -b >/dev/null
fi
printf 'Using simulator: %s\n' "$DEVICE"

xcodebuild \
  -project FreePrintStudio.xcodeproj \
  -scheme FreePrintStudio \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build >/tmp/freeprintstudio-print-sheet-build.log

xcrun simctl install "$DEVICE" "$APP_PATH"

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
