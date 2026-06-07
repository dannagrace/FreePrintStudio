#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_DIR="${ACCESSIBILITY_SCREENSHOT_DIR:-/tmp/freeprintstudio-accessibility-screenshots}"
SCREENSHOT_DELAY="${SCREENSHOT_DELAY:-3}"
IPAD_DEVICE_PATTERN="${FREEPRINTSTUDIO_IPAD_DEVICE_PATTERN:-iPad Pro 13-inch|iPad Air 13-inch}"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.jpg

check_screenshot_health() {
  local screenshot_path="$1"
  local label="$2"
  local accepted_dimensions="$3"
  local width
  local height
  local alpha
  local temp_dir
  local converted_png
  local result

  if [[ ! -s "$screenshot_path" ]]; then
    printf 'FAIL: %s screenshot missing: %s\n' "$label" "$screenshot_path"
    exit 1
  fi

  width="$(sips -g pixelWidth "$screenshot_path" | awk -F': ' '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$screenshot_path" | awk -F': ' '/pixelHeight/ { print $2 }')"
  alpha="$(sips -g hasAlpha "$screenshot_path" | awk -F': ' '/hasAlpha/ { print $2 }')"

  if ! grep -Eq "(^|,)$width x $height(,|$)" <<<"$accepted_dimensions"; then
    printf 'FAIL: %s screenshot has invalid size %s x %s. Accepted: %s\n' \
      "$label" "$width" "$height" "$accepted_dimensions"
    exit 1
  fi

  if [[ "$alpha" != "no" ]]; then
    printf 'FAIL: %s screenshot must not contain alpha; hasAlpha=%s\n' "$label" "${alpha:-missing}"
    exit 1
  fi

  temp_dir="$(mktemp -d -t freeprintstudio-accessibility-screenshot)"
  converted_png="$temp_dir/screenshot.png"
  sips -s format png "$screenshot_path" --out "$converted_png" >/dev/null

  result=0
  python3 - "$converted_png" "$label" <<'PY' || result=$?
import struct
import sys
import zlib

path = sys.argv[1]
label = sys.argv[2]
data = open(path, "rb").read()
if not data.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit(f"FAIL: {label} screenshot conversion did not produce a PNG")

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
    raise SystemExit(f"FAIL: {label} screenshot uses unsupported PNG format")

channels = 4 if color_type == 6 else 3
stride = width * channels
raw = zlib.decompress(bytes(compressed))
previous = [0] * stride
offset = 0
interesting = 0
red_pixels = 0
bottom_blue_pixels = 0
bottom_pixels = 0
total = width * height

for y in range(height):
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
            raise SystemExit(f"FAIL: {label} screenshot uses unsupported PNG filter")

    for i in range(0, stride, channels):
        red, green, blue = scanline[i], scanline[i + 1], scanline[i + 2]
        if red < 245 or green < 245 or blue < 245:
            interesting += 1
        if red > 180 and green < 130 and blue < 150 and red - green > 60 and red - blue > 50:
            red_pixels += 1
        if label == "iPhone Larger Text" and y >= height * 0.75:
            bottom_pixels += 1
            if blue > 150 and green > 90 and red < 80 and blue - red > 100:
                bottom_blue_pixels += 1
    previous = scanline

non_white_ratio = interesting / total
print(f"OK: {label} screenshot visual content ratio {non_white_ratio:.4f}; validationErrorRedPixels={red_pixels}")
if non_white_ratio < 0.02:
    raise SystemExit(f"FAIL: {label} screenshot looks blank or under-rendered")
if red_pixels > 1000:
    raise SystemExit(f"FAIL: {label} screenshot appears to contain a validation error message")
if label == "iPhone Larger Text":
    bottom_blue_ratio = bottom_blue_pixels / max(1, bottom_pixels)
    print(f"OK: {label} bottom action blue ratio {bottom_blue_ratio:.4f}")
    if bottom_blue_ratio > 0.05:
        raise SystemExit(f"FAIL: {label} screenshot has a fixed action bar covering the bottom viewport")
PY

  rm -rf "$temp_dir"
  return "$result"
}

printf '== Dark mode iPhone screenshot ==\n'
FREEPRINTSTUDIO_APPEARANCE=dark \
  SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
  SCREENSHOT_PATH="$OUTPUT_DIR/iphone-dark.jpg" \
  Scripts/capture_app_store_screenshots.sh
check_screenshot_health "$OUTPUT_DIR/iphone-dark.jpg" "iPhone dark mode" "1260 x 2736,1290 x 2796,1320 x 2868"

printf '\n== Larger Text iPhone screenshot ==\n'
FREEPRINTSTUDIO_CONTENT_SIZE=accessibility-extra-extra-large \
  SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
  SCREENSHOT_PATH="$OUTPUT_DIR/iphone-larger-text.jpg" \
  Scripts/capture_app_store_screenshots.sh
check_screenshot_health "$OUTPUT_DIR/iphone-larger-text.jpg" "iPhone Larger Text" "1260 x 2736,1290 x 2796,1320 x 2868"

printf '\n== Larger Text iPad screenshot ==\n'
FREEPRINTSTUDIO_DEVICE_PATTERN="$IPAD_DEVICE_PATTERN" \
  FREEPRINTSTUDIO_DEVICE_FALLBACK_NAME=iPad \
  FREEPRINTSTUDIO_CONTENT_SIZE=accessibility-extra-extra-large \
  SCREENSHOT_DELAY="$SCREENSHOT_DELAY" \
  SCREENSHOT_PATH="$OUTPUT_DIR/ipad-larger-text.jpg" \
  Scripts/capture_app_store_screenshots.sh
check_screenshot_health "$OUTPUT_DIR/ipad-larger-text.jpg" "iPad Larger Text" "2048 x 2732,2064 x 2752"

printf '\nAccessibility screenshot validation passed. Screenshots written to %s\n' "$OUTPUT_DIR"
