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

normalize_iphone_screenshot() {
  local path="$1"
  local width
  local height
  local crop_height

  width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/{print $2}')"
  height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/{print $2}')"
  if [[ "$width" == "1284" && "$height" == "2778" ]]; then
    return
  fi

  crop_height="$(( (width * 2778 + 642) / 1284 ))"
  if (( crop_height > height )); then
    printf 'Cannot normalize %s from %sx%s to 1284x2778 without padding.\n' "$path" "$width" "$height" >&2
    exit 1
  fi

  sips --cropToHeightWidth "$crop_height" "$width" "$path" >/dev/null
  sips --resampleHeightWidth 2778 1284 "$path" >/dev/null
}

capture_main() {
  printf '== iPhone main screenshot ==\n'
  DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
    FREEPRINTSTUDIO_APPEARANCE=light \
    SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
    SCREENSHOT_PATH="$APPSTORE_SCREENSHOTS_DIR/iphone-main.jpg" \
    Scripts/capture_app_store_screenshots.sh

  normalize_iphone_screenshot "$APPSTORE_SCREENSHOTS_DIR/iphone-main.jpg"
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

  normalize_iphone_screenshot "$APPSTORE_SCREENSHOTS_DIR/$output_name"
  cp "$APPSTORE_SCREENSHOTS_DIR/$output_name" "$FASTLANE_SCREENSHOTS_DIR/$output_name"
}

capture_main

printf '== iPhone Test Ruler screenshot ==\n'
DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
  FREEPRINTSTUDIO_APPEARANCE=light \
  FREEPRINTSTUDIO_SCREENSHOT_CONTENT=testRuler \
  SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
  SCREENSHOT_PATH="$APPSTORE_SCREENSHOTS_DIR/iphone-test-ruler.jpg" \
  Scripts/capture_app_store_screenshots.sh

normalize_iphone_screenshot "$APPSTORE_SCREENSHOTS_DIR/iphone-test-ruler.jpg"
cp "$APPSTORE_SCREENSHOTS_DIR/iphone-test-ruler.jpg" "$FASTLANE_SCREENSHOTS_DIR/iphone-test-ruler.jpg"

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

normalize_iphone_screenshot "$APPSTORE_SCREENSHOTS_DIR/iphone-metric-landscape.jpg"
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
