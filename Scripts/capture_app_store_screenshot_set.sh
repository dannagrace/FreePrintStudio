#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APPSTORE_SCREENSHOTS_DIR="$ROOT_DIR/AppStore/Screenshots"
FASTLANE_SCREENSHOTS_DIR="$ROOT_DIR/fastlane/screenshots/en-US"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/freeprintstudio-derived-data}"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-5}"

mkdir -p "$APPSTORE_SCREENSHOTS_DIR" "$FASTLANE_SCREENSHOTS_DIR"

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

capture_mode fit iphone-fit.jpg
capture_mode fill iphone-fill.jpg
capture_mode stretch iphone-stretch.jpg

printf '\nSynced screenshots to %s\n' "$FASTLANE_SCREENSHOTS_DIR"
