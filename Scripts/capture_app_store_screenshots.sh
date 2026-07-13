#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="com.dannagrace.FreePrintStudio"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/freeprintstudio-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/FreePrintStudio.app"
SAMPLE_IMAGE="$ROOT_DIR/AppStore/Assets/sample-print-image.png"
SCREENSHOT_PATH="${SCREENSHOT_PATH:-$ROOT_DIR/AppStore/Screenshots/iphone-main.jpg}"
TEST_PAPER="${FREEPRINTSTUDIO_PAPER:-fourBySix}"
TEST_ORIENTATION="${FREEPRINTSTUDIO_ORIENTATION:-portrait}"
TEST_UNIT="${FREEPRINTSTUDIO_UNIT:-inch}"
TEST_FIT_MODE="${FREEPRINTSTUDIO_FIT_MODE:-fit}"
TEST_TARGET_WIDTH="${FREEPRINTSTUDIO_TARGET_WIDTH:-}"
TEST_TARGET_HEIGHT="${FREEPRINTSTUDIO_TARGET_HEIGHT:-}"
TEST_APPEARANCE="${FREEPRINTSTUDIO_APPEARANCE:-}"
TEST_CONTENT_SIZE="${FREEPRINTSTUDIO_CONTENT_SIZE:-}"
TEST_CONTENT="${FREEPRINTSTUDIO_SCREENSHOT_CONTENT:-image}"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-5}"
SIMCTL_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SIMCTL_TIMEOUT_SECONDS:-30}"
BOOTSTATUS_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SCREENSHOT_BOOTSTATUS_TIMEOUT_SECONDS:-180}"
XCODEBUILD_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SCREENSHOT_XCODEBUILD_TIMEOUT_SECONDS:-300}"

validate_capture_options() {
  if [[ -n "$TEST_APPEARANCE" ]]; then
    case "$TEST_APPEARANCE" in
      light|dark)
        ;;
      *)
        printf 'Invalid FREEPRINTSTUDIO_APPEARANCE: %s. Use light or dark.\n' "$TEST_APPEARANCE"
        exit 1
        ;;
    esac
  fi

  case "$TEST_CONTENT" in
    image|testRuler)
      ;;
    *)
      printf 'Invalid FREEPRINTSTUDIO_SCREENSHOT_CONTENT: %s. Use image or testRuler.\n' "$TEST_CONTENT"
      exit 1
      ;;
  esac

  case "$TEST_PAPER" in
    letter|a4|fourBySix|fiveBySeven)
      ;;
    *)
      printf 'Invalid FREEPRINTSTUDIO_PAPER: %s. Use letter, a4, fourBySix, or fiveBySeven.\n' "$TEST_PAPER"
      exit 1
      ;;
  esac

  case "$TEST_ORIENTATION" in
    portrait|landscape)
      ;;
    *)
      printf 'Invalid FREEPRINTSTUDIO_ORIENTATION: %s. Use portrait or landscape.\n' "$TEST_ORIENTATION"
      exit 1
      ;;
  esac

  case "$TEST_UNIT" in
    inch|centimeter|millimeter)
      ;;
    *)
      printf 'Invalid FREEPRINTSTUDIO_UNIT: %s. Use inch, centimeter, or millimeter.\n' "$TEST_UNIT"
      exit 1
      ;;
  esac

  case "$TEST_FIT_MODE" in
    fit|fill|stretch)
      ;;
    *)
      printf 'Invalid FREEPRINTSTUDIO_FIT_MODE: %s. Use fit, fill, or stretch.\n' "$TEST_FIT_MODE"
      exit 1
      ;;
  esac
}

validate_capture_options

if [[ "${FREEPRINTSTUDIO_VALIDATE_OPTIONS_ONLY:-}" == "1" ]]; then
  printf 'Screenshot capture options valid.\n'
  exit 0
fi

IPHONE_DEVICE_PATTERN="${FREEPRINTSTUDIO_IPHONE_DEVICE_PATTERN:-iPhone 17 Pro Max|iPhone Air|iPhone 16 Pro Max|iPhone 16 Plus|iPhone 15 Pro Max|iPhone 15 Plus|iPhone 14 Pro Max}"
DEVICE_PATTERN="${FREEPRINTSTUDIO_DEVICE_PATTERN:-$IPHONE_DEVICE_PATTERN}"
FALLBACK_DEVICE_NAME="${FREEPRINTSTUDIO_DEVICE_FALLBACK_NAME:-iPhone}"

candidate_simulators() {
  if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    printf '%s\n' "$SIMULATOR_UDID"
    return
  fi

  run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl list devices booted \
    | grep -E "$DEVICE_PATTERN" \
    | sed -nE 's/.*\(([A-F0-9-]{36})\).*/\1/p' \
    || true
  run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl list devices available \
    | grep -E "$DEVICE_PATTERN" \
    | sed -nE 's/.*\(([A-F0-9-]{36})\).*/\1/p' \
    || true
  run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl list devices booted \
    | sed -nE "/$FALLBACK_DEVICE_NAME/s/.*\\(([A-F0-9-]{36})\\).*/\\1/p" \
    || true
  run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl list devices available \
    | sed -nE "/$FALLBACK_DEVICE_NAME/s/.*\\(([A-F0-9-]{36})\\).*/\\1/p" \
    || true
}

unique_candidate_simulators() {
  candidate_simulators | awk 'NF && !seen[$0]++'
}

boot_simulator() {
  local device="$1"
  if [[ "$device" != "booted" ]]; then
    run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl boot "$device" >/dev/null 2>&1 || true
    run_with_timeout "$BOOTSTATUS_TIMEOUT_SECONDS" xcrun simctl bootstatus "$device" -b >/dev/null
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
    print(f"Screenshot capture command timed out after {timeout_text} seconds: {' '.join(command)}")
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
    printf 'No available simulator found for pattern %s. Set SIMULATOR_UDID to a booted simulator UDID.\n' "$DEVICE_PATTERN" >&2
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

  printf 'No simulator accepted the screenshot app install.\n' >&2
  exit 1
}

ORIGINAL_APPEARANCE=""
ORIGINAL_CONTENT_SIZE=""
RESTORE_SIMULATOR_UI=0

restore_simulator_ui() {
  if [[ "$RESTORE_SIMULATOR_UI" != "1" ]]; then
    return
  fi
  if [[ -n "$ORIGINAL_APPEARANCE" && "$ORIGINAL_APPEARANCE" != "unsupported" && "$ORIGINAL_APPEARANCE" != "unknown" ]]; then
    run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl ui "$DEVICE" appearance "$ORIGINAL_APPEARANCE" >/dev/null 2>&1 || true
  fi
  if [[ -n "$ORIGINAL_CONTENT_SIZE" && "$ORIGINAL_CONTENT_SIZE" != "unsupported" && "$ORIGINAL_CONTENT_SIZE" != "unknown" ]]; then
    run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl ui "$DEVICE" content_size "$ORIGINAL_CONTENT_SIZE" >/dev/null 2>&1 || true
  fi
}

trap restore_simulator_ui EXIT

Scripts/generate_store_sample_image.py

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

run_with_timeout "$XCODEBUILD_TIMEOUT_SECONDS" xcodebuild \
  -project FreePrintStudio.xcodeproj \
  -scheme FreePrintStudio \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  build >/tmp/freeprintstudio-screenshot-build.log

DEVICE="$(select_installed_simulator)"
printf 'Using simulator: %s\n' "$DEVICE"

if [[ -n "$TEST_APPEARANCE" || -n "$TEST_CONTENT_SIZE" ]]; then
  ORIGINAL_APPEARANCE="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl ui "$DEVICE" appearance 2>/dev/null || true)"
  ORIGINAL_CONTENT_SIZE="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl ui "$DEVICE" content_size 2>/dev/null || true)"
  RESTORE_SIMULATOR_UI=1
fi

if [[ -n "$TEST_APPEARANCE" ]]; then
  run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl ui "$DEVICE" appearance "$TEST_APPEARANCE"
fi

if [[ -n "$TEST_CONTENT_SIZE" ]]; then
  run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl ui "$DEVICE" content_size "$TEST_CONTENT_SIZE"
fi

CONTAINER="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)"
TEST_DIR="$CONTAINER/Documents/FreePrintStudioScreenshot"
mkdir -p "$TEST_DIR"
cp "$SAMPLE_IMAGE" "$TEST_DIR/sample-print-image.png"

run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
launch_args=(
  -FreePrintStudioTestImagePath "$TEST_DIR/sample-print-image.png" \
  -FreePrintStudioPaper "$TEST_PAPER" \
  -FreePrintStudioOrientation "$TEST_ORIENTATION" \
  -FreePrintStudioUnit "$TEST_UNIT" \
  -FreePrintStudioFitMode "$TEST_FIT_MODE"
)

if [[ "$TEST_CONTENT" == "testRuler" ]]; then
  launch_args+=(-FreePrintStudioUseTestRuler)
fi

if [[ -n "$TEST_TARGET_WIDTH" ]]; then
  launch_args+=(-FreePrintStudioTargetWidth "$TEST_TARGET_WIDTH")
fi

if [[ -n "$TEST_TARGET_HEIGHT" ]]; then
  launch_args+=(-FreePrintStudioTargetHeight "$TEST_TARGET_HEIGHT")
fi

run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" "${launch_args[@]}" >/tmp/freeprintstudio-screenshot-launch.log

sleep "$SCREENSHOT_DELAY"
run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl io "$DEVICE" screenshot --type=jpeg "$SCREENSHOT_PATH" >/tmp/freeprintstudio-screenshot-capture.log
printf 'Wrote %s\n' "$SCREENSHOT_PATH"
