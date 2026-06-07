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
TEST_ORIENTATION="${FREEPRINTSTUDIO_ORIENTATION:-portrait}"
TEST_UNIT="${FREEPRINTSTUDIO_UNIT:-inch}"
TEST_TARGET_WIDTH="${FREEPRINTSTUDIO_TARGET_WIDTH:-4}"
TEST_TARGET_HEIGHT="${FREEPRINTSTUDIO_TARGET_HEIGHT:-6}"
if [[ -n "${FREEPRINTSTUDIO_FIT_MODE:-}" ]]; then
  FIT_MODES=("$FREEPRINTSTUDIO_FIT_MODE")
else
  FIT_MODES=(fit fill stretch)
fi

case "$TEST_PAPER" in
  letter|a4|fourBySix|fiveBySeven)
    ;;
  *)
    printf 'Unsupported FREEPRINTSTUDIO_PAPER for PDF validation: %s\n' "$TEST_PAPER"
    exit 1
    ;;
esac

case "$TEST_ORIENTATION" in
  portrait|landscape)
    ;;
  *)
    printf 'Unsupported FREEPRINTSTUDIO_ORIENTATION for PDF validation: %s\n' "$TEST_ORIENTATION"
    exit 1
    ;;
esac

case "$TEST_UNIT" in
  inch|centimeter|millimeter)
    ;;
  *)
    printf 'Unsupported FREEPRINTSTUDIO_UNIT for PDF validation: %s\n' "$TEST_UNIT"
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

host_pdf_path_for_label() {
  local label="$1"
  local requested_path="${PDF_EXPORT_PATH:-}"

  if [[ -z "$requested_path" ]]; then
    printf '/tmp/freeprintstudio-export-validation-%s.pdf\n' "$label"
    return
  fi

  if (( ${#FIT_MODES[@]} == 1 )); then
    printf '%s\n' "$requested_path"
  elif [[ "$requested_path" == *.* ]]; then
    printf '%s-%s.%s\n' "${requested_path%.*}" "$label" "${requested_path##*.}"
  else
    printf '%s-%s.pdf\n' "$requested_path" "$label"
  fi
}

validate_pdf() {
  local label="$1"
  local mode="$2"
  local paper="$3"
  local orientation="$4"
  local unit="$5"
  local target_width="$6"
  local target_height="$7"
  local app_pdf_path="$TEST_DIR/export-validation-$label.pdf"
  local host_pdf_path
  local expected_width_points
  local expected_height_points
  local portrait_width_points
  local portrait_height_points
  host_pdf_path="$(host_pdf_path_for_label "$label")"

  case "$mode" in
    fit|fill|stretch)
      ;;
    *)
      printf 'Unsupported FREEPRINTSTUDIO_FIT_MODE for PDF validation: %s\n' "$mode"
      exit 1
      ;;
  esac

  case "$paper" in
    letter)
      portrait_width_points="612"
      portrait_height_points="792"
      ;;
    a4)
      portrait_width_points="595.2755905512"
      portrait_height_points="841.8897637795"
      ;;
    fourBySix)
      portrait_width_points="288"
      portrait_height_points="432"
      ;;
    fiveBySeven)
      portrait_width_points="360"
      portrait_height_points="504"
      ;;
    *)
      printf 'Unsupported paper for PDF validation: %s\n' "$paper"
      exit 1
      ;;
  esac

  case "$orientation" in
    portrait)
      expected_width_points="$portrait_width_points"
      expected_height_points="$portrait_height_points"
      ;;
    landscape)
      expected_width_points="$portrait_height_points"
      expected_height_points="$portrait_width_points"
      ;;
    *)
      printf 'Unsupported orientation for PDF validation: %s\n' "$orientation"
      exit 1
      ;;
  esac

  case "$unit" in
    inch|centimeter|millimeter)
      ;;
    *)
      printf 'Unsupported measurement unit for PDF validation: %s\n' "$unit"
      exit 1
      ;;
  esac

  rm -f "$app_pdf_path" "$host_pdf_path"

  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
    -FreePrintStudioTestImagePath "$TEST_DIR/sample-print-image.png" \
    -FreePrintStudioPaper "$paper" \
    -FreePrintStudioOrientation "$orientation" \
    -FreePrintStudioUnit "$unit" \
    -FreePrintStudioFitMode "$mode" \
    -FreePrintStudioTargetWidth "$target_width" \
    -FreePrintStudioTargetHeight "$target_height" \
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

  python3 - "$host_pdf_path" "$expected_width_points" "$expected_height_points" "$mode" "$unit" "$target_width" "$target_height" <<'PY'
import re
import sys
import zlib

path = sys.argv[1]
expected_width = float(sys.argv[2])
expected_height = float(sys.argv[3])
mode = sys.argv[4]
unit = sys.argv[5]
target_width_text = sys.argv[6]
target_height_text = sys.argv[7]
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

def parse_measurement(value: str) -> float:
    value = value.strip()
    if value.count(",") == 1 and "." not in value:
        value = value.replace(",", ".")
    return float(value)

def target_points(value_text: str, unit_name: str) -> float:
    value = parse_measurement(value_text)
    if unit_name == "inch":
        return value * 72
    if unit_name == "centimeter":
        return value / 2.54 * 72
    if unit_name == "millimeter":
        return value / 25.4 * 72
    raise SystemExit(f"Unsupported measurement unit: {unit_name}")

expected_target_width = target_points(target_width_text, unit)
expected_target_height = target_points(target_height_text, unit)
decoded_streams = []
for stream in re.findall(rb"stream\r?\n(.*?)\r?\nendstream", data, re.S):
    try:
        decoded_streams.append(zlib.decompress(stream))
    except zlib.error:
        decoded_streams.append(stream)
content = b"\n".join(decoded_streams)
clip_match = re.search(
    rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+m\s+"
    rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+l\s+"
    rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+l\s+"
    rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+l\s+h\s+W\s+n",
    content,
)
if not clip_match:
    raise SystemExit("Image clip rectangle not found in PDF content stream")

clip_values = [float(value) for value in clip_match.groups()]
clip_x_values = clip_values[0::2]
clip_y_values = clip_values[1::2]
clip_width = max(clip_x_values) - min(clip_x_values)
clip_height = max(clip_y_values) - min(clip_y_values)
if abs(clip_width - expected_target_width) > tolerance or abs(clip_height - expected_target_height) > tolerance:
    raise SystemExit(
        f"Unexpected image clip rectangle size: {clip_width:.4f} x {clip_height:.4f}, "
        f"expected {expected_target_width:.4f} x {expected_target_height:.4f}"
    )
print(f"Image clip rectangle: {clip_width:.4f} x {clip_height:.4f} pt")

if mode == "stretch":
    expected_draw_width = expected_target_width
    expected_draw_height = expected_target_height
    matrix_match = re.search(
        rb"([-+]?[0-9]*\.?[0-9]+)\s+0\s+0\s+([-+]?[0-9]*\.?[0-9]+)\s+"
        rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+cm\s+/Im\d+\s+Do",
        content,
    )
    if not matrix_match:
        raise SystemExit("Image draw matrix not found in stretch PDF content stream")

    draw_width = float(matrix_match.group(1))
    draw_height = float(matrix_match.group(2))
    if abs(draw_width - expected_draw_width) > tolerance or abs(draw_height - expected_draw_height) > tolerance:
        raise SystemExit(
            f"Unexpected stretch image draw size: {draw_width:.4f} x {draw_height:.4f}, "
            f"expected {expected_draw_width:.4f} x {expected_draw_height:.4f}"
        )
    print(f"Image draw matrix: {draw_width:.4f} x {draw_height:.4f} pt")

print(f"Validated {mode} exported PDF: {path}")
PY
}

for mode in "${FIT_MODES[@]}"; do
  validate_pdf "$mode" "$mode" "$TEST_PAPER" "$TEST_ORIENTATION" "$TEST_UNIT" "$TEST_TARGET_WIDTH" "$TEST_TARGET_HEIGHT"
done

if [[ -z "${FREEPRINTSTUDIO_TARGET_WIDTH:-}" && -z "${FREEPRINTSTUDIO_TARGET_HEIGHT:-}" && -z "${FREEPRINTSTUDIO_FIT_MODE:-}" && -z "${FREEPRINTSTUDIO_PAPER:-}" && -z "${FREEPRINTSTUDIO_ORIENTATION:-}" && -z "${FREEPRINTSTUDIO_UNIT:-}" ]]; then
  validate_pdf "localized-decimal-stretch" "stretch" "letter" "portrait" "inch" "4,5" "6,25"
  validate_pdf "landscape-letter-stretch" "stretch" "letter" "landscape" "inch" "4" "6"
  validate_pdf "centimeter-a4-stretch" "stretch" "a4" "portrait" "centimeter" "10" "15"
  validate_pdf "millimeter-a4-stretch" "stretch" "a4" "portrait" "millimeter" "100" "150"
fi
