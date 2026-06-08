#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOG_PATH="/tmp/freeprintstudio-release-build.log"
SCREENSHOT_PATHS=(
  "AppStore/Screenshots/iphone-main.jpg"
  "AppStore/Screenshots/iphone-test-ruler.jpg"
  "AppStore/Screenshots/iphone-fit.jpg"
  "AppStore/Screenshots/iphone-fill.jpg"
  "AppStore/Screenshots/iphone-stretch.jpg"
  "AppStore/Screenshots/iphone-metric-landscape.jpg"
  "AppStore/Screenshots/ipad-main.jpg"
)

check_screenshot_not_blank() {
  local screenshot_path="$1"
  local temp_dir
  local converted_png
  local result
  temp_dir="$(mktemp -d -t freeprintstudio-screenshot)"
  converted_png="$temp_dir/screenshot.png"
  sips -s format png "$screenshot_path" --out "$converted_png" >/dev/null

  result=0
  python3 - "$converted_png" <<'PY' || result=$?
import struct
import sys
import zlib

path = sys.argv[1]
data = open(path, "rb").read()
if not data.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit("Converted screenshot is not a PNG")

pos = 8
width = height = bit_depth = color_type = None
compressed = bytearray()

while pos < len(data):
    length = struct.unpack(">I", data[pos:pos + 4])[0]
    chunk_type = data[pos + 4:pos + 8]
    payload = data[pos + 8:pos + 8 + length]
    pos += 12 + length

    if chunk_type == b"IHDR":
        width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", payload)
    elif chunk_type == b"IDAT":
        compressed.extend(payload)
    elif chunk_type == b"IEND":
        break

if bit_depth != 8 or color_type not in (2, 6):
    raise SystemExit(f"Unsupported PNG format: bit_depth={bit_depth}, color_type={color_type}")

channels = 4 if color_type == 6 else 3
stride = width * channels
raw = zlib.decompress(bytes(compressed))
previous = [0] * stride
interesting = 0
total = width * height
offset = 0

for _ in range(height):
    filter_type = raw[offset]
    offset += 1
    scanline = list(raw[offset:offset + stride])
    offset += stride

    for i, value in enumerate(scanline):
        left = scanline[i - channels] if i >= channels else 0
        up = previous[i]
        up_left = previous[i - channels] if i >= channels else 0
        if filter_type == 1:
            scanline[i] = (value + left) & 0xFF
        elif filter_type == 2:
            scanline[i] = (value + up) & 0xFF
        elif filter_type == 3:
            scanline[i] = (value + ((left + up) // 2)) & 0xFF
        elif filter_type == 4:
            p = left + up - up_left
            pa = abs(p - left)
            pb = abs(p - up)
            pc = abs(p - up_left)
            predictor = left if pa <= pb and pa <= pc else up if pb <= pc else up_left
            scanline[i] = (value + predictor) & 0xFF
        elif filter_type != 0:
            raise SystemExit(f"Unsupported PNG filter: {filter_type}")

    for i in range(0, stride, channels):
        red, green, blue = scanline[i], scanline[i + 1], scanline[i + 2]
        if red < 245 or green < 245 or blue < 245:
            interesting += 1
    previous = scanline

ratio = interesting / total
print(f"  nonWhiteRatio: {ratio:.4f}")
if ratio < 0.02:
    raise SystemExit("Screenshot looks blank or under-rendered")
PY

  rm -rf "$temp_dir"
  return "$result"
}

check_screenshot_dimensions() {
  local screenshot_path="$1"
  local accepted_dimensions="$2"
  local width
  local height
  width="$(sips -g pixelWidth "$screenshot_path" | awk -F': ' '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$screenshot_path" | awk -F': ' '/pixelHeight/ { print $2 }')"

  if ! grep -Eq "(^|,)$width x $height(,|$)" <<<"$accepted_dimensions"; then
    printf 'Invalid screenshot size for %s: %s x %s. Accepted: %s\n' \
      "$screenshot_path" "$width" "$height" "$accepted_dimensions"
    exit 1
  fi
}

check_screenshot_has_no_validation_error_red() {
  local screenshot_path="$1"
  local temp_dir
  local converted_png
  local result
  temp_dir="$(mktemp -d -t freeprintstudio-screenshot)"
  converted_png="$temp_dir/screenshot.png"
  sips -s format png "$screenshot_path" --out "$converted_png" >/dev/null

  result=0
  python3 - "$converted_png" <<'PY' || result=$?
import struct
import sys
import zlib

path = sys.argv[1]
data = open(path, "rb").read()
if not data.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit("Converted screenshot is not a PNG")

pos = 8
width = height = bit_depth = color_type = None
compressed = bytearray()

while pos < len(data):
    length = struct.unpack(">I", data[pos:pos + 4])[0]
    chunk_type = data[pos + 4:pos + 8]
    payload = data[pos + 8:pos + 8 + length]
    pos += 12 + length

    if chunk_type == b"IHDR":
        width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", payload)
    elif chunk_type == b"IDAT":
        compressed.extend(payload)
    elif chunk_type == b"IEND":
        break

if bit_depth != 8 or color_type not in (2, 6):
    raise SystemExit(f"Unsupported PNG format: bit_depth={bit_depth}, color_type={color_type}")

channels = 4 if color_type == 6 else 3
stride = width * channels
raw = zlib.decompress(bytes(compressed))
previous = [0] * stride
offset = 0
red_pixels = 0

for _ in range(height):
    filter_type = raw[offset]
    offset += 1
    scanline = list(raw[offset:offset + stride])
    offset += stride

    for i, value in enumerate(scanline):
        left = scanline[i - channels] if i >= channels else 0
        up = previous[i]
        up_left = previous[i - channels] if i >= channels else 0
        if filter_type == 1:
            scanline[i] = (value + left) & 0xFF
        elif filter_type == 2:
            scanline[i] = (value + up) & 0xFF
        elif filter_type == 3:
            scanline[i] = (value + ((left + up) // 2)) & 0xFF
        elif filter_type == 4:
            p = left + up - up_left
            pa = abs(p - left)
            pb = abs(p - up)
            pc = abs(p - up_left)
            predictor = left if pa <= pb and pa <= pc else up if pb <= pc else up_left
            scanline[i] = (value + predictor) & 0xFF
        elif filter_type != 0:
            raise SystemExit(f"Unsupported PNG filter: {filter_type}")

    for i in range(0, stride, channels):
        red, green, blue = scanline[i], scanline[i + 1], scanline[i + 2]
        if red > 180 and green < 130 and blue < 150 and red - green > 60 and red - blue > 50:
            red_pixels += 1
    previous = scanline

print(f"  validationErrorRedPixels: {red_pixels}")
if red_pixels > 1000:
    raise SystemExit("Screenshot appears to contain a validation error message")
PY

  rm -rf "$temp_dir"
  return "$result"
}

run_static_checks() {
  printf '== Static release checks ==\n'
  Scripts/release_check.sh
}

run_core_checks() {
  printf '== Core checks ==\n'
  swift run FreePrintStudioCoreChecks
}

run_plist_lint() {
  printf '== Property list lint ==\n'
  plutil -lint \
    FreePrintStudio/Resources/Info.plist \
    FreePrintStudio/Resources/PrivacyInfo.xcprivacy
}

run_privacy_surface_validation() {
  printf '== Privacy surface validation ==\n'
  Scripts/validate_privacy_surface.sh
}

run_questionnaire_validation() {
  printf '== App Store questionnaire validation ==\n'
  Scripts/validate_app_store_questionnaires.sh
}

run_pdf_export_validation() {
  printf '== PDF export validation ==\n'
  Scripts/validate_pdf_export.sh
}

run_release_build() {
  printf '== Release iOS build ==\n'
  xcodebuild \
    -project FreePrintStudio.xcodeproj \
    -scheme FreePrintStudio \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO \
    build >"$LOG_PATH" 2>&1
  tail -n 20 "$LOG_PATH"

  unexpected_messages="$(
    grep -nE 'warning:|error:' "$LOG_PATH" \
      | grep -v 'warning: Metadata extraction skipped. No AppIntents.framework dependency found.' \
      || true
  )"
  if [[ -n "$unexpected_messages" ]]; then
    printf '%s\n' "$unexpected_messages"
    printf '\nRelease build emitted warnings or errors. See %s\n' "$LOG_PATH"
    exit 1
  fi
}

run_screenshot_checks() {
  printf '== Screenshot asset ==\n'
  for screenshot_path in "${SCREENSHOT_PATHS[@]}"; do
    if [[ ! -s "$screenshot_path" ]]; then
      printf 'Missing screenshot: %s\n' "$screenshot_path"
      exit 1
    fi
    sips -g pixelWidth -g pixelHeight -g hasAlpha "$screenshot_path"
    case "$screenshot_path" in
      *iphone-main.jpg)
        check_screenshot_dimensions "$screenshot_path" "1260 x 2736,1290 x 2796,1320 x 2868"
        ;;
      *iphone-*.jpg)
        check_screenshot_dimensions "$screenshot_path" "1260 x 2736,1290 x 2796,1320 x 2868"
        ;;
      *ipad-main.jpg)
        check_screenshot_dimensions "$screenshot_path" "2048 x 2732,2064 x 2752"
        ;;
    esac
    check_screenshot_not_blank "$screenshot_path"
    case "$screenshot_path" in
      *iphone-metric-landscape.jpg)
        check_screenshot_has_no_validation_error_red "$screenshot_path"
        ;;
    esac
  done
  Scripts/validate_screenshot_sync.sh
}

run_accessibility_screenshot_validation() {
  printf '== Accessibility screenshot validation ==\n'
  Scripts/validate_accessibility_screenshots.sh
}

run_simulator_workflow_validation() {
  printf '== Simulator workflow validation ==\n'
  Scripts/validate_simulator_workflow.sh
}

run_photo_import_validation() {
  printf '== Photo import validation ==\n'
  Scripts/validate_photo_import.sh
}

run_print_sheet_validation() {
  printf '== Print sheet validation ==\n'
  Scripts/validate_print_sheet.sh
}

run_submission_packet_generation() {
  printf '== App Store submission packet ==\n'
  Scripts/prepare_app_store_submission_packet.sh
}

run_archive_preflight_validation() {
  printf '== App Store archive preflight ==\n'
  Scripts/preflight_app_store_archive.sh
}

run_testflight_preflight_validation() {
  printf '== TestFlight upload preflight ==\n'
  Scripts/preflight_testflight_upload.sh
}

run_review_preflight_validation() {
  printf '== App Review submission preflight ==\n'
  Scripts/preflight_app_review_submission.sh
}

run_manual_verification_validation() {
  printf '== Manual release verification evidence ==\n'
  Scripts/validate_manual_release_verification.sh
}

run_all() {
  run_static_checks
  printf '\n'
  run_core_checks
  printf '\n'
  run_plist_lint
  printf '\n'
  run_privacy_surface_validation
  printf '\n'
  run_questionnaire_validation
  printf '\n'
  run_pdf_export_validation
  printf '\n'
  run_release_build
  printf '\n'
  run_screenshot_checks
  printf '\nRelease verification passed.\n'
}

run_store_ready_validation() {
  run_all
  printf '\n'
  run_simulator_workflow_validation
  printf '\n'
  run_photo_import_validation
  printf '\n'
  run_accessibility_screenshot_validation
  printf '\n'
  run_print_sheet_validation
  printf '\n'
  run_submission_packet_generation
  printf '\nLocal store-ready verification passed.\n'
}

case "${1:-all}" in
  all)
    run_all
    ;;
  store-ready)
    run_store_ready_validation
    ;;
  static)
    run_static_checks
    ;;
  core)
    run_core_checks
    ;;
  plist)
    run_plist_lint
    ;;
  privacy)
    run_privacy_surface_validation
    ;;
  questionnaires)
    run_questionnaire_validation
    ;;
  pdf)
    run_pdf_export_validation
    ;;
  build)
    run_release_build
    ;;
  screenshots)
    run_screenshot_checks
    ;;
  accessibility)
    run_accessibility_screenshot_validation
    ;;
  simulator-workflow)
    run_simulator_workflow_validation
    ;;
  photo-import)
    run_photo_import_validation
    ;;
  print-sheet)
    run_print_sheet_validation
    ;;
  submission-packet)
    run_submission_packet_generation
    ;;
  archive-preflight)
    run_archive_preflight_validation
    ;;
  testflight-preflight)
    run_testflight_preflight_validation
    ;;
  review-preflight)
    run_review_preflight_validation
    ;;
  manual-verification)
    run_manual_verification_validation
    ;;
  *)
    printf 'Usage: %s [all|store-ready|static|core|plist|privacy|questionnaires|pdf|build|screenshots|accessibility|simulator-workflow|photo-import|print-sheet|submission-packet|archive-preflight|testflight-preflight|review-preflight|manual-verification]\n' "$0"
    exit 1
    ;;
esac
