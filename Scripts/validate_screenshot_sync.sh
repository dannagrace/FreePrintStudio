#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APPSTORE_SCREENSHOTS_DIR="AppStore/Screenshots"
FASTLANE_SCREENSHOTS_DIR="fastlane/screenshots/en-US"
expected_screenshots=(
  "iphone-main.jpg"
  "iphone-test-ruler.jpg"
  "iphone-fit.jpg"
  "iphone-fill.jpg"
  "iphone-stretch.jpg"
  "iphone-metric-landscape.jpg"
  "ipad-main.jpg"
)

failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

contains_expected_screenshot() {
  local filename="$1"
  local expected
  for expected in "${expected_screenshots[@]}"; do
    [[ "$filename" == "$expected" ]] && return 0
  done
  return 1
}

for screenshot in "${expected_screenshots[@]}"; do
  appstore_path="$APPSTORE_SCREENSHOTS_DIR/$screenshot"
  fastlane_path="$FASTLANE_SCREENSHOTS_DIR/$screenshot"

  [[ -s "$appstore_path" ]] || fail "Reviewed screenshot missing: $appstore_path"
  [[ -s "$fastlane_path" ]] || fail "Fastlane screenshot missing: $fastlane_path"

  if [[ -s "$appstore_path" && -s "$fastlane_path" ]] && ! cmp -s "$appstore_path" "$fastlane_path"; then
    appstore_sha="$(shasum -a 256 "$appstore_path" | awk '{ print $1 }')"
    fastlane_sha="$(shasum -a 256 "$fastlane_path" | awk '{ print $1 }')"
    fail "Screenshot differs between reviewed and Fastlane copies: $screenshot ($appstore_sha != $fastlane_sha)"
  fi
done

while IFS= read -r screenshot_path; do
  filename="$(basename "$screenshot_path")"
  contains_expected_screenshot "$filename" || fail "Unexpected reviewed screenshot: $screenshot_path"
done < <(find "$APPSTORE_SCREENSHOTS_DIR" -maxdepth 1 -type f -name '*.jpg' | sort)

while IFS= read -r screenshot_path; do
  filename="$(basename "$screenshot_path")"
  contains_expected_screenshot "$filename" || fail "Unexpected Fastlane screenshot: $screenshot_path"
done < <(find "$FASTLANE_SCREENSHOTS_DIR" -maxdepth 1 -type f -name '*.jpg' | sort)

if (( failures > 0 )); then
  exit 1
fi

printf 'Screenshot sync validation passed.\n'
