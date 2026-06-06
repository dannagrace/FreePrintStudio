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
TEST_TARGET_WIDTH="${FREEPRINTSTUDIO_TARGET_WIDTH:-}"
TEST_TARGET_HEIGHT="${FREEPRINTSTUDIO_TARGET_HEIGHT:-}"
TEST_APPEARANCE="${FREEPRINTSTUDIO_APPEARANCE:-}"
TEST_CONTENT_SIZE="${FREEPRINTSTUDIO_CONTENT_SIZE:-}"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-5}"

ORIGINAL_APPEARANCE=""
ORIGINAL_CONTENT_SIZE=""
RESTORE_SIMULATOR_UI=0

restore_simulator_ui() {
  if [[ "$RESTORE_SIMULATOR_UI" != "1" ]]; then
    return
  fi
  if [[ -n "$ORIGINAL_APPEARANCE" && "$ORIGINAL_APPEARANCE" != "unsupported" && "$ORIGINAL_APPEARANCE" != "unknown" ]]; then
    xcrun simctl ui "$DEVICE" appearance "$ORIGINAL_APPEARANCE" >/dev/null 2>&1 || true
  fi
  if [[ -n "$ORIGINAL_CONTENT_SIZE" && "$ORIGINAL_CONTENT_SIZE" != "unsupported" && "$ORIGINAL_CONTENT_SIZE" != "unknown" ]]; then
    xcrun simctl ui "$DEVICE" content_size "$ORIGINAL_CONTENT_SIZE" >/dev/null 2>&1 || true
  fi
}

trap restore_simulator_ui EXIT

Scripts/generate_store_sample_image.py

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

if [[ "$DEVICE" != "booted" ]]; then
  xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$DEVICE" -b >/dev/null
fi
printf 'Using simulator: %s\n' "$DEVICE"

if [[ -n "$TEST_APPEARANCE" || -n "$TEST_CONTENT_SIZE" ]]; then
  ORIGINAL_APPEARANCE="$(xcrun simctl ui "$DEVICE" appearance 2>/dev/null || true)"
  ORIGINAL_CONTENT_SIZE="$(xcrun simctl ui "$DEVICE" content_size 2>/dev/null || true)"
  RESTORE_SIMULATOR_UI=1
fi

if [[ -n "$TEST_APPEARANCE" ]]; then
  case "$TEST_APPEARANCE" in
    light|dark)
      xcrun simctl ui "$DEVICE" appearance "$TEST_APPEARANCE"
      ;;
    *)
      printf 'Invalid FREEPRINTSTUDIO_APPEARANCE: %s. Use light or dark.\n' "$TEST_APPEARANCE"
      exit 1
      ;;
  esac
fi

if [[ -n "$TEST_CONTENT_SIZE" ]]; then
  xcrun simctl ui "$DEVICE" content_size "$TEST_CONTENT_SIZE"
fi

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
launch_args=(
  -FreePrintStudioTestImagePath "$TEST_DIR/sample-print-image.png" \
  -FreePrintStudioPaper "$TEST_PAPER" \
  -FreePrintStudioFitMode "$TEST_FIT_MODE"
)

if [[ -n "$TEST_TARGET_WIDTH" ]]; then
  launch_args+=(-FreePrintStudioTargetWidth "$TEST_TARGET_WIDTH")
fi

if [[ -n "$TEST_TARGET_HEIGHT" ]]; then
  launch_args+=(-FreePrintStudioTargetHeight "$TEST_TARGET_HEIGHT")
fi

xcrun simctl launch "$DEVICE" "$BUNDLE_ID" "${launch_args[@]}" >/tmp/freeprintstudio-screenshot-launch.log

sleep "$SCREENSHOT_DELAY"
xcrun simctl io "$DEVICE" screenshot --type=jpeg "$SCREENSHOT_PATH" >/tmp/freeprintstudio-screenshot-capture.log
printf 'Wrote %s\n' "$SCREENSHOT_PATH"
