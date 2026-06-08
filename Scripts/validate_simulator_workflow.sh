#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WORKFLOW_DIR="${FREEPRINTSTUDIO_SIMULATOR_WORKFLOW_DIR:-/tmp/freeprintstudio-simulator-workflow}"
SCREENSHOT_PATH="$WORKFLOW_DIR/workflow.jpg"
PDF_PATH="$WORKFLOW_DIR/workflow.pdf"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-5}"

rm -rf "$WORKFLOW_DIR"
mkdir -p "$WORKFLOW_DIR"

validate_workflow_screenshot() {
  local screenshot_path="$1"
  local temp_dir
  local converted_png
  local result

  if [[ ! -s "$screenshot_path" ]]; then
    printf 'Simulator workflow screenshot was not created: %s\n' "$screenshot_path"
    exit 1
  fi

  temp_dir="$(mktemp -d -t freeprintstudio-workflow-screenshot)"
  converted_png="$temp_dir/workflow.png"
  sips -s format png "$screenshot_path" --out "$converted_png" >/dev/null

  result=0
  python3 - "$converted_png" <<'PY' || result=$?
import struct
import sys
import zlib

path = sys.argv[1]
data = open(path, "rb").read()
if not data.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit("Converted workflow screenshot is not a PNG")

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
non_white = 0
red_pixels = 0
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
            non_white += 1
        if red > 180 and green < 130 and blue < 150 and red - green > 60 and red - blue > 50:
            red_pixels += 1
    previous = scanline

non_white_ratio = non_white / total
print(f"  nonWhiteRatio: {non_white_ratio:.4f}")
print(f"  validationErrorRedPixels: {red_pixels}")

if non_white_ratio < 0.05:
    raise SystemExit("Workflow screenshot looks blank or under-rendered")
if red_pixels > 1000:
    raise SystemExit("Workflow screenshot appears to contain a target-size validation error")
PY

  rm -rf "$temp_dir"
  return "$result"
}

printf '== Simulator workflow screenshot ==\n'
FREEPRINTSTUDIO_PAPER=a4 \
FREEPRINTSTUDIO_ORIENTATION=landscape \
FREEPRINTSTUDIO_UNIT=centimeter \
FREEPRINTSTUDIO_FIT_MODE=stretch \
FREEPRINTSTUDIO_TARGET_WIDTH=10 \
FREEPRINTSTUDIO_TARGET_HEIGHT=15 \
FREEPRINTSTUDIO_APPEARANCE=light \
SCREENSHOT_PATH="$SCREENSHOT_PATH" \
SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
Scripts/capture_app_store_screenshots.sh

validate_workflow_screenshot "$SCREENSHOT_PATH"

printf '\n== Simulator workflow PDF export ==\n'
FREEPRINTSTUDIO_PAPER=a4 \
FREEPRINTSTUDIO_ORIENTATION=landscape \
FREEPRINTSTUDIO_UNIT=centimeter \
FREEPRINTSTUDIO_FIT_MODE=stretch \
FREEPRINTSTUDIO_TARGET_WIDTH=10 \
FREEPRINTSTUDIO_TARGET_HEIGHT=15 \
PDF_EXPORT_PATH="$PDF_PATH" \
PDF_VALIDATION_MANIFEST_PATH="$WORKFLOW_DIR/pdf-export-validation.tsv" \
Scripts/validate_pdf_export.sh

if [[ ! -s "$PDF_PATH" ]]; then
  printf 'Simulator workflow PDF was not created: %s\n' "$PDF_PATH"
  exit 1
fi

printf '\nSimulator workflow validation passed.\n'
printf 'Screenshot: %s\n' "$SCREENSHOT_PATH"
printf 'PDF: %s\n' "$PDF_PATH"
