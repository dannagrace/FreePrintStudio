#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/freeprintstudio-photo-import-derived-data}"
TEST_LOG_PATH="${FREEPRINTSTUDIO_PHOTO_IMPORT_LOG_PATH:-/tmp/freeprintstudio-photo-import-test.log}"
SAMPLE_IMAGE="$ROOT_DIR/AppStore/Assets/sample-print-image.png"
MEDIA_IMAGE="${FREEPRINTSTUDIO_PHOTO_IMPORT_MEDIA_IMAGE:-/tmp/freeprintstudio-photo-import-sample.jpg}"
ADDMEDIA_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_ADDMEDIA_TIMEOUT_SECONDS:-20}"

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
  if [[ "$device" != "booted" ]]; then
    xcrun simctl boot "$device" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$device" -b >/dev/null
  fi
}

seed_media() {
  local device="$1"
  local media_path="$2"
  local timeout_seconds="$3"

  # Runs xcrun simctl addmedia with a timeout because a stale simulator media service can hang indefinitely.
  python3 - "$device" "$media_path" "$timeout_seconds" <<'PY'
import subprocess
import sys

device, media_path, timeout_text = sys.argv[1:4]
try:
    result = subprocess.run(
        ["xcrun", "simctl", "addmedia", device, media_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=float(timeout_text),
    )
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        print(exc.stdout, end="")
    print(f"simctl addmedia timed out after {timeout_text} seconds")
    sys.exit(124)

if result.stdout:
    print(result.stdout, end="")
sys.exit(result.returncode)
PY
}

select_seeded_simulator() {
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
    boot_simulator "$candidate"
    seed_output=""
    if seed_output="$(seed_media "$candidate" "$MEDIA_IMAGE" "$ADDMEDIA_TIMEOUT_SECONDS" 2>&1)"; then
      if [[ -n "$seed_output" ]]; then
        printf '%s\n' "$seed_output" >&2
      fi
      printf '%s\n' "$candidate"
      return
    fi
    if [[ -n "$seed_output" ]]; then
      printf '%s\n' "$seed_output" >&2
    fi
    printf 'Skipping simulator after media seed failure: %s\n' "$candidate" >&2
  done <<<"$candidates"

  printf 'No simulator accepted seeded photo media.\n' >&2
  exit 1
}

Scripts/generate_store_sample_image.py
sips -s format jpeg "$SAMPLE_IMAGE" --out "$MEDIA_IMAGE" >/tmp/freeprintstudio-photo-import-jpeg.log

DEVICE="$(select_seeded_simulator)"
printf 'Using simulator: %s\n' "$DEVICE"
printf 'Seeded simulator photo library: %s\n' "$MEDIA_IMAGE"

set +e
xcodebuild \
  -project FreePrintStudio.xcodeproj \
  -scheme FreePrintStudio \
  -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:FreePrintStudioUITests/PhotoImportUITests \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  test >"$TEST_LOG_PATH" 2>&1
test_status="$?"
set -e

tail -n 40 "$TEST_LOG_PATH"

if [[ "$test_status" -ne 0 ]]; then
  printf '\nPhoto import validation failed. See %s\n' "$TEST_LOG_PATH"
  exit "$test_status"
fi

printf '\nPhoto import validation passed.\n'
