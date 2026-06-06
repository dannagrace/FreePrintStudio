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
HOST_PDF_PATH="${PDF_EXPORT_PATH:-/tmp/freeprintstudio-export-validation.pdf}"
TEST_PAPER="${FREEPRINTSTUDIO_PAPER:-letter}"
TEST_FIT_MODE="${FREEPRINTSTUDIO_FIT_MODE:-fit}"
TEST_TARGET_WIDTH="${FREEPRINTSTUDIO_TARGET_WIDTH:-4}"
TEST_TARGET_HEIGHT="${FREEPRINTSTUDIO_TARGET_HEIGHT:-6}"

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
APP_PDF_PATH="$TEST_DIR/export-validation.pdf"
mkdir -p "$TEST_DIR"
rm -f "$APP_PDF_PATH" "$HOST_PDF_PATH"
cp "$SAMPLE_IMAGE" "$TEST_DIR/sample-print-image.png"

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
  -FreePrintStudioTestImagePath "$TEST_DIR/sample-print-image.png" \
  -FreePrintStudioPaper "$TEST_PAPER" \
  -FreePrintStudioFitMode "$TEST_FIT_MODE" \
  -FreePrintStudioTargetWidth "$TEST_TARGET_WIDTH" \
  -FreePrintStudioTargetHeight "$TEST_TARGET_HEIGHT" \
  -FreePrintStudioAutoExportPDFPath "$APP_PDF_PATH" \
  >/tmp/freeprintstudio-pdf-validation-launch.log

for _ in {1..30}; do
  if [[ -s "$APP_PDF_PATH" ]]; then
    break
  fi
  sleep 0.5
done

if [[ ! -s "$APP_PDF_PATH" ]]; then
  printf 'Timed out waiting for exported PDF: %s\n' "$APP_PDF_PATH"
  exit 1
fi

cp "$APP_PDF_PATH" "$HOST_PDF_PATH"

python3 - "$HOST_PDF_PATH" "$EXPECTED_WIDTH_POINTS" "$EXPECTED_HEIGHT_POINTS" <<'PY'
import re
import sys

path = sys.argv[1]
expected_width = float(sys.argv[2])
expected_height = float(sys.argv[3])
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

if len(data) < 1000:
    raise SystemExit("Exported PDF is unexpectedly small")
PY

printf 'Validated exported PDF: %s\n' "$HOST_PDF_PATH"
