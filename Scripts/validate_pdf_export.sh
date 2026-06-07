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
TEST_PAPER="${FREEPRINTSTUDIO_PAPER:-letter}"
TEST_TARGET_WIDTH="${FREEPRINTSTUDIO_TARGET_WIDTH:-4}"
TEST_TARGET_HEIGHT="${FREEPRINTSTUDIO_TARGET_HEIGHT:-6}"
if [[ -n "${FREEPRINTSTUDIO_FIT_MODE:-}" ]]; then
  FIT_MODES=("$FREEPRINTSTUDIO_FIT_MODE")
else
  FIT_MODES=(fit fill stretch)
fi

case "$TEST_PAPER" in
  letter)
    EXPECTED_WIDTH_POINTS="612"
    EXPECTED_HEIGHT_POINTS="792"
    ;;
  a4)
    EXPECTED_WIDTH_POINTS="595.2755905512"
    EXPECTED_HEIGHT_POINTS="841.8897637795"
    ;;
  fourBySix)
    EXPECTED_WIDTH_POINTS="288"
    EXPECTED_HEIGHT_POINTS="432"
    ;;
  fiveBySeven)
    EXPECTED_WIDTH_POINTS="360"
    EXPECTED_HEIGHT_POINTS="504"
    ;;
  *)
    printf 'Unsupported FREEPRINTSTUDIO_PAPER for PDF validation: %s\n' "$TEST_PAPER"
    exit 1
    ;;
esac

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
  build >/tmp/freeprintstudio-pdf-validation-build.log

xcrun simctl install "$DEVICE" "$APP_PATH"

CONTAINER="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)"
TEST_DIR="$CONTAINER/Documents/FreePrintStudioPDFValidation"
mkdir -p "$TEST_DIR"
cp "$SAMPLE_IMAGE" "$TEST_DIR/sample-print-image.png"

host_pdf_path_for_mode() {
  local mode="$1"
  local requested_path="${PDF_EXPORT_PATH:-}"

  if [[ -z "$requested_path" ]]; then
    printf '/tmp/freeprintstudio-export-validation-%s.pdf\n' "$mode"
    return
  fi

  if (( ${#FIT_MODES[@]} == 1 )); then
    printf '%s\n' "$requested_path"
  elif [[ "$requested_path" == *.* ]]; then
    printf '%s-%s.%s\n' "${requested_path%.*}" "$mode" "${requested_path##*.}"
  else
    printf '%s-%s.pdf\n' "$requested_path" "$mode"
  fi
}

validate_pdf() {
  local mode="$1"
  local app_pdf_path="$TEST_DIR/export-validation-$mode.pdf"
  local host_pdf_path
  host_pdf_path="$(host_pdf_path_for_mode "$mode")"

  case "$mode" in
    fit|fill|stretch)
      ;;
    *)
      printf 'Unsupported FREEPRINTSTUDIO_FIT_MODE for PDF validation: %s\n' "$mode"
      exit 1
      ;;
  esac

  rm -f "$app_pdf_path" "$host_pdf_path"

  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
    -FreePrintStudioTestImagePath "$TEST_DIR/sample-print-image.png" \
    -FreePrintStudioPaper "$TEST_PAPER" \
    -FreePrintStudioFitMode "$mode" \
    -FreePrintStudioTargetWidth "$TEST_TARGET_WIDTH" \
    -FreePrintStudioTargetHeight "$TEST_TARGET_HEIGHT" \
    -FreePrintStudioAutoExportPDFPath "$app_pdf_path" \
    >/tmp/freeprintstudio-pdf-validation-launch.log

  for _ in {1..30}; do
    if [[ -s "$app_pdf_path" ]]; then
      break
    fi
    sleep 0.5
  done

  if [[ ! -s "$app_pdf_path" ]]; then
    printf 'Timed out waiting for exported PDF: %s\n' "$app_pdf_path"
    exit 1
  fi

  mkdir -p "$(dirname "$host_pdf_path")"
  cp "$app_pdf_path" "$host_pdf_path"

  python3 - "$host_pdf_path" "$EXPECTED_WIDTH_POINTS" "$EXPECTED_HEIGHT_POINTS" "$mode" <<'PY'
import re
import sys

path = sys.argv[1]
expected_width = float(sys.argv[2])
expected_height = float(sys.argv[3])
mode = sys.argv[4]
data = open(path, "rb").read()

if not data.startswith(b"%PDF-"):
    raise SystemExit("Exported file is not a PDF")

match = re.search(
    rb"/MediaBox\s*\[\s*([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s*\]",
    data,
)
if not match:
    raise SystemExit("PDF MediaBox not found")

x0, y0, x1, y1 = (float(value) for value in match.groups())
width = x1 - x0
height = y1 - y0
tolerance = 0.02

print(f"PDF MediaBox: {width:.4f} x {height:.4f} pt")
if abs(width - expected_width) > tolerance or abs(height - expected_height) > tolerance:
    raise SystemExit(
        f"Unexpected PDF page size: {width:.4f} x {height:.4f}, "
        f"expected {expected_width:.4f} x {expected_height:.4f}"
    )

if b"/Subtype /Image" not in data:
    raise SystemExit("Exported PDF does not contain an embedded image")

if len(data) < 1000:
    raise SystemExit("Exported PDF is unexpectedly small")

print(f"Validated {mode} exported PDF: {path}")
PY
}

for mode in "${FIT_MODES[@]}"; do
  validate_pdf "$mode"
done
