#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/freeprintstudio-review-ui-derived-data}"
TEST_LOG_PATH="${FREEPRINTSTUDIO_REVIEW_UI_LOG_PATH:-/tmp/freeprintstudio-review-ui-test.log}"

candidate_simulators() {
  if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    printf '%s\n' "$SIMULATOR_UDID"
    return
  fi

  local device_pattern
  local fallback_device_name
  device_pattern="${FREEPRINTSTUDIO_DEVICE_PATTERN:-iPhone 17 Pro Max|iPhone Air|iPhone 16 Pro Max|iPhone 16 Plus|iPhone 15 Pro Max|iPhone 15 Plus|iPhone 14 Pro Max}"
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
  xcrun simctl boot "$device" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$device" -b >/dev/null
}

select_simulator() {
  local candidate
  local candidates
  candidates="$(unique_candidate_simulators)"
  if [[ -z "$candidates" ]]; then
    printf 'No available simulator found. Set SIMULATOR_UDID to a booted simulator UDID.\n' >&2
    exit 1
  fi

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    printf 'Trying simulator: %s\n' "$candidate" >&2
    if boot_simulator "$candidate"; then
      printf '%s\n' "$candidate"
      return
    fi
    printf 'Skipping simulator after boot failure: %s\n' "$candidate" >&2
  done <<<"$candidates"

  printf 'No simulator could be booted for review UI validation.\n' >&2
  exit 1
}

DEVICE="$(select_simulator)"
printf 'Using simulator: %s\n' "$DEVICE"

set +e
xcodebuild \
  -project FreePrintStudio.xcodeproj \
  -scheme FreePrintStudio \
  -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:FreePrintStudioUITests/PhotoImportUITests/testAboutScreenShowsReviewAndSupportInformation \
  CODE_SIGNING_ALLOWED=NO \
  test >"$TEST_LOG_PATH" 2>&1
test_status="$?"
set -e

tail -n 40 "$TEST_LOG_PATH"

if [[ "$test_status" -ne 0 ]]; then
  printf '\nReview UI validation failed. See %s\n' "$TEST_LOG_PATH"
  exit "$test_status"
fi

printf '\nReview UI validation passed.\n'
