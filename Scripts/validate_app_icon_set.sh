#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 <<'PY'
import json
import re
import struct
import sys
from pathlib import Path

ICON_DIR = Path("FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset")
CONTENTS_PATH = ICON_DIR / "Contents.json"

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def parse_size_points(value: str) -> float | None:
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)x\1", value)
    if not match:
        return None
    return float(match.group(1))


def parse_scale(value: str) -> int | None:
    match = re.fullmatch(r"([123])x", value)
    if not match:
        return None
    return int(match.group(1))


def png_header(path: Path) -> tuple[int, int, int] | None:
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        return None

    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        fail(f"{path} must be a PNG")
        return None

    pos = 8
    while pos + 24 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        chunk_type = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", payload)
            if bit_depth != 8:
                fail(f"{path} must use 8-bit PNG channels, found bit depth {bit_depth}")
            if color_type in (4, 6):
                fail(f"{path} hasAlpha true; app icons must not contain an alpha channel")
            elif color_type not in (0, 2, 3):
                fail(f"{path} uses unsupported PNG color type {color_type}")
            return width, height, color_type

    fail(f"{path} is missing a PNG IHDR chunk")
    return None


try:
    contents = json.loads(CONTENTS_PATH.read_text(encoding="utf-8"))
except FileNotFoundError:
    fail(f"missing app icon catalog: {CONTENTS_PATH}")
    contents = {}
except json.JSONDecodeError as exc:
    fail(f"{CONTENTS_PATH} is not valid JSON: {exc}")
    contents = {}

images = contents.get("images")
if not isinstance(images, list):
    fail("AppIcon Contents.json must contain an images array")
    images = []

expected_entries = {
    ("iphone", "20x20", "2x"),
    ("iphone", "20x20", "3x"),
    ("iphone", "29x29", "2x"),
    ("iphone", "29x29", "3x"),
    ("iphone", "40x40", "2x"),
    ("iphone", "40x40", "3x"),
    ("iphone", "60x60", "2x"),
    ("iphone", "60x60", "3x"),
    ("ipad", "20x20", "1x"),
    ("ipad", "20x20", "2x"),
    ("ipad", "29x29", "1x"),
    ("ipad", "29x29", "2x"),
    ("ipad", "40x40", "1x"),
    ("ipad", "40x40", "2x"),
    ("ipad", "76x76", "2x"),
    ("ipad", "83.5x83.5", "2x"),
    ("ios-marketing", "1024x1024", "1x"),
}

seen_entries: set[tuple[str, str, str]] = set()
referenced_files: set[str] = set()

for index, image in enumerate(images):
    if not isinstance(image, dict):
        fail(f"AppIcon entry {index} must be an object")
        continue

    idiom = image.get("idiom")
    size = image.get("size")
    scale = image.get("scale")
    filename = image.get("filename")

    if not all(isinstance(value, str) and value for value in (idiom, size, scale, filename)):
        fail(f"AppIcon entry {index} must include idiom, size, scale, and filename")
        continue

    entry = (idiom, size, scale)
    if entry in seen_entries:
        fail(f"Duplicate AppIcon entry for idiom={idiom} size={size} scale={scale}")
    seen_entries.add(entry)

    size_points = parse_size_points(size)
    scale_factor = parse_scale(scale)
    if size_points is None:
        fail(f"AppIcon entry {filename} has invalid square size: {size}")
        continue
    if scale_factor is None:
        fail(f"AppIcon entry {filename} has invalid scale: {scale}")
        continue

    icon_path = ICON_DIR / filename
    referenced_files.add(filename)
    header = png_header(icon_path)
    if header is None:
        fail(f"Missing referenced app icon PNG: {icon_path}")
        continue

    width, height, _ = header
    expected_pixels = int(round(size_points * scale_factor))
    if width != expected_pixels or height != expected_pixels:
        fail(
            f"{icon_path} is {width}x{height}px; expected "
            f"{expected_pixels}x{expected_pixels}px for {idiom} {size} @{scale}"
        )

missing_entries = expected_entries - seen_entries
for idiom, size, scale in sorted(missing_entries):
    fail(f"Missing required AppIcon entry: idiom={idiom} size={size} scale={scale}")

unexpected_entries = seen_entries - expected_entries
for idiom, size, scale in sorted(unexpected_entries):
    fail(f"Unexpected AppIcon entry: idiom={idiom} size={size} scale={scale}")

for png_path in sorted(ICON_DIR.glob("*.png")):
    if png_path.name not in referenced_files:
        fail(f"Unreferenced app icon PNG: {png_path}")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}")
    sys.exit(1)

print("App icon set validation passed.")
PY
