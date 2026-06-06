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
      | head -n 1
  )"
  if [[ -z "$DEVICE" ]]; then
    DEVICE="$(
      xcrun simctl list devices booted \
      | sed -nE 's/.*iPhone.*\(([A-F0-9-]{36})\).*/\1/p' \
      | head -n 1
    )"
  fi
  DEVICE="${DEVICE:-booted}"
fi
BUNDLE_ID="com.dannagrace.FreePrintStudio"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/freeprintstudio-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/FreePrintStudio.app"
SAMPLE_IMAGE="$ROOT_DIR/AppStore/Assets/sample-print-image.png"
SCREENSHOT_PATH="${SCREENSHOT_PATH:-$ROOT_DIR/AppStore/Screenshots/iphone-main.jpg}"
TEST_PAPER="${FREEPRINTSTUDIO_PAPER:-fourBySix}"
TEST_FIT_MODE="${FREEPRINTSTUDIO_FIT_MODE:-fit}"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-5}"

Scripts/generate_store_sample_image.py

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

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
  build >/tmp/freeprintstudio-screenshot-build.log

xcrun simctl install "$DEVICE" "$APP_PATH"

CONTAINER="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)"
TEST_DIR="$CONTAINER/Documents/FreePrintStudioScreenshot"
mkdir -p "$TEST_DIR"
cp "$SAMPLE_IMAGE" "$TEST_DIR/sample-print-image.png"

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
  -FreePrintStudioTestImagePath "$TEST_DIR/sample-print-image.png" \
  -FreePrintStudioPaper "$TEST_PAPER" \
  -FreePrintStudioFitMode "$TEST_FIT_MODE" >/tmp/freeprintstudio-screenshot-launch.log

sleep "$SCREENSHOT_DELAY"
xcrun simctl io "$DEVICE" screenshot --type=jpeg "$SCREENSHOT_PATH" >/tmp/freeprintstudio-screenshot-capture.log
printf 'Wrote %s\n' "$SCREENSHOT_PATH"
