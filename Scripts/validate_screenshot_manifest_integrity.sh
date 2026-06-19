#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: %s <submission-packet-dir>\n' "$0" >&2
  exit 2
fi

PACKET_DIR="$1"
SCREENSHOT_MANIFEST="$PACKET_DIR/screenshots.tsv"

if [[ ! -d "$PACKET_DIR" ]]; then
  printf 'FAIL: Submission packet directory is missing: %s\n' "$PACKET_DIR" >&2
  exit 1
fi

if [[ ! -s "$SCREENSHOT_MANIFEST" ]]; then
  printf 'FAIL: screenshots.tsv is missing or empty: %s\n' "$SCREENSHOT_MANIFEST" >&2
  exit 1
fi

python3 - "$PACKET_DIR" "$SCREENSHOT_MANIFEST" <<'PY'
import csv
import hashlib
import re
import subprocess
import sys
from pathlib import Path

packet_dir = Path(sys.argv[1]).resolve()
manifest_path = Path(sys.argv[2]).resolve()
expected_header = ["path", "width", "height", "hasAlpha", "sha256"]
sha_pattern = re.compile(r"^[0-9a-f]{64}$")
failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def sha256_for_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def image_property(path: Path, property_name: str) -> str:
    completed = subprocess.run(
        ["sips", "-g", property_name, str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        fail(f"{path.relative_to(packet_dir).as_posix()}: sips failed for {property_name}")
        return ""
    for line in completed.stdout.splitlines():
        stripped = line.strip()
        prefix = f"{property_name}: "
        if stripped.startswith(prefix):
            return stripped[len(prefix):]
    fail(f"{path.relative_to(packet_dir).as_posix()}: sips output is missing {property_name}")
    return ""


with manifest_path.open(newline="", encoding="utf-8") as manifest_file:
    reader = csv.DictReader(manifest_file, delimiter="\t")
    if reader.fieldnames != expected_header:
        fail(
            "screenshots.tsv has unexpected header: "
            + "\t".join(reader.fieldnames or [])
        )
        rows = []
    else:
        rows = list(reader)

seen_paths: set[str] = set()

for row_number, row in enumerate(rows, start=2):
    screenshot_path = row.get("path", "")
    manifest_width = row.get("width", "")
    manifest_height = row.get("height", "")
    manifest_alpha = row.get("hasAlpha", "")
    manifest_sha = row.get("sha256", "")

    if not screenshot_path:
        fail(f"row {row_number} has an empty path")
        continue
    if Path(screenshot_path).is_absolute() or ".." in Path(screenshot_path).parts:
        fail(f"{screenshot_path}: path must be relative to the repository screenshot roots")
        continue
    if screenshot_path in seen_paths:
        fail(f"{screenshot_path}: duplicate screenshot manifest entry")
        continue
    seen_paths.add(screenshot_path)

    if not manifest_width.isdigit():
        fail(f"{screenshot_path}: width is not a positive integer")
    if not manifest_height.isdigit():
        fail(f"{screenshot_path}: height is not a positive integer")
    if manifest_alpha not in {"yes", "no"}:
        fail(f"{screenshot_path}: hasAlpha must be yes or no")
    if not sha_pattern.fullmatch(manifest_sha):
        fail(f"{screenshot_path}: sha256 value is not a 64-character lowercase hex digest")

    file_path = packet_dir / "files" / screenshot_path
    if not file_path.is_file():
        fail(f"{screenshot_path}: screenshot file is missing from packet files")
        continue
    if file_path.is_symlink():
        fail(f"{screenshot_path}: screenshot file is a symlink")
        continue

    actual_width = image_property(file_path, "pixelWidth")
    actual_height = image_property(file_path, "pixelHeight")
    actual_alpha = image_property(file_path, "hasAlpha")
    actual_sha = sha256_for_file(file_path)

    if manifest_width.isdigit() and actual_width != manifest_width:
        fail(f"{screenshot_path}: width mismatch ({actual_width} != {manifest_width})")
    if manifest_height.isdigit() and actual_height != manifest_height:
        fail(f"{screenshot_path}: height mismatch ({actual_height} != {manifest_height})")
    if manifest_alpha in {"yes", "no"} and actual_alpha != manifest_alpha:
        fail(f"{screenshot_path}: hasAlpha mismatch ({actual_alpha} != {manifest_alpha})")
    if sha_pattern.fullmatch(manifest_sha) and actual_sha != manifest_sha:
        fail(f"{screenshot_path}: sha256 mismatch ({actual_sha} != {manifest_sha})")

if not rows:
    fail("screenshots.tsv does not contain any screenshot entries")

expected_roots = [
    packet_dir / "files" / "AppStore" / "Screenshots",
    packet_dir / "files" / "fastlane" / "screenshots" / "en-US",
]
packet_screenshots: set[str] = set()
for root in expected_roots:
    if not root.exists():
        continue
    for path in root.glob("*.jpg"):
        packet_screenshots.add(path.relative_to(packet_dir / "files").as_posix())

missing_from_manifest = sorted(packet_screenshots - seen_paths)
for path in missing_from_manifest:
    fail(f"{path}: screenshot file is missing from screenshots.tsv")

missing_from_packet = sorted(seen_paths - packet_screenshots)
for path in missing_from_packet:
    fail(f"{path}: screenshots.tsv entry is missing from packet screenshot files")

if failures:
    for message in failures:
        print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

print("Screenshot manifest integrity validation passed.")
PY
