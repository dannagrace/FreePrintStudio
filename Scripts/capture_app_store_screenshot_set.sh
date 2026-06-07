#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APPSTORE_SCREENSHOTS_DIR="$ROOT_DIR/AppStore/Screenshots"
FASTLANE_SCREENSHOTS_DIR="$ROOT_DIR/fastlane/screenshots/en-US"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/freeprintstudio-derived-data}"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-5}"
IPAD_DEVICE_PATTERN="${FREEPRINTSTUDIO_IPAD_DEVICE_PATTERN:-iPad Pro 13-inch|iPad Air 13-inch}"

mkdir -p "$APPSTORE_SCREENSHOTS_DIR" "$FASTLANE_SCREENSHOTS_DIR"

capture_main() {
  printf '== iPhone main screenshot ==\n'
  DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
    FREEPRINTSTUDIO_APPEARANCE=light \
    SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
    SCREENSHOT_PATH="$APPSTORE_SCREENSHOTS_DIR/iphone-main.jpg" \
    Scripts/capture_app_store_screenshots.sh

  cp "$APPSTORE_SCREENSHOTS_DIR/iphone-main.jpg" "$FASTLANE_SCREENSHOTS_DIR/iphone-main.jpg"
}

capture_mode() {
  local mode="$1"
  local output_name="$2"

  printf '== iPhone %s screenshot ==\n' "$mode"
  DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
    FREEPRINTSTUDIO_FIT_MODE="$mode" \
    SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
    SCREENSHOT_PATH="$APPSTORE_SCREENSHOTS_DIR/$output_name" \
    Scripts/capture_app_store_screenshots.sh

  cp "$APPSTORE_SCREENSHOTS_DIR/$output_name" "$FASTLANE_SCREENSHOTS_DIR/$output_name"
}

capture_main
capture_mode fit iphone-fit.jpg
capture_mode fill iphone-fill.jpg
capture_mode stretch iphone-stretch.jpg

printf '== iPhone metric landscape screenshot ==\n'
DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
  FREEPRINTSTUDIO_PAPER=a4 \
  FREEPRINTSTUDIO_ORIENTATION=landscape \
  FREEPRINTSTUDIO_UNIT=centimeter \
  FREEPRINTSTUDIO_TARGET_WIDTH=15 \
  FREEPRINTSTUDIO_TARGET_HEIGHT=10 \
  FREEPRINTSTUDIO_FIT_MODE=stretch \
  SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
  SCREENSHOT_PATH="$APPSTORE_SCREENSHOTS_DIR/iphone-metric-landscape.jpg" \
  Scripts/capture_app_store_screenshots.sh

cp "$APPSTORE_SCREENSHOTS_DIR/iphone-metric-landscape.jpg" "$FASTLANE_SCREENSHOTS_DIR/iphone-metric-landscape.jpg"

printf '== iPad main screenshot ==\n'
DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
  FREEPRINTSTUDIO_DEVICE_PATTERN="$IPAD_DEVICE_PATTERN" \
  FREEPRINTSTUDIO_DEVICE_FALLBACK_NAME=iPad \
  SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
  SCREENSHOT_PATH="$APPSTORE_SCREENSHOTS_DIR/ipad-main.jpg" \
  Scripts/capture_app_store_screenshots.sh

cp "$APPSTORE_SCREENSHOTS_DIR/ipad-main.jpg" "$FASTLANE_SCREENSHOTS_DIR/ipad-main.jpg"

printf '\nSynced screenshots to %s\n' "$FASTLANE_SCREENSHOTS_DIR"
