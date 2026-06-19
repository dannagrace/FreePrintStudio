#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: %s <submission-packet-dir>\n' "$0" >&2
  exit 2
fi

packet_dir="$1"
manifest_path="$packet_dir/file-manifest.tsv"

if [[ ! -d "$packet_dir" ]]; then
  printf 'FAIL: Submission packet directory is missing: %s\n' "$packet_dir" >&2
  exit 1
fi

if [[ ! -s "$manifest_path" ]]; then
  printf 'FAIL: file-manifest.tsv is missing or empty: %s\n' "$manifest_path" >&2
  exit 1
fi

python3 - "$packet_dir" "$manifest_path" <<'PY'
import csv
import hashlib
import re
import sys
from pathlib import Path

packet_dir = Path(sys.argv[1]).resolve()
manifest_path = Path(sys.argv[2]).resolve()
expected_header = ["path", "bytes", "sha256"]
sha_pattern = re.compile(r"^[0-9a-f]{64}$")
failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def relative_to_packet(path: Path) -> str:
    return path.relative_to(packet_dir).as_posix()


def sha256_for_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


with manifest_path.open(newline="", encoding="utf-8") as manifest_file:
    reader = csv.DictReader(manifest_file, delimiter="\t")
    if reader.fieldnames != expected_header:
        fail(
            "file-manifest.tsv has unexpected header: "
            + "\t".join(reader.fieldnames or [])
        )
        rows = []
    else:
        rows = list(reader)

seen_paths: set[str] = set()

for row_number, row in enumerate(rows, start=2):
    manifest_relative_path = row.get("path", "")
    manifest_bytes = row.get("bytes", "")
    manifest_sha = row.get("sha256", "")

    if not manifest_relative_path:
        fail(f"row {row_number} has an empty path")
        continue
    if manifest_relative_path == "file-manifest.tsv":
        fail("file-manifest.tsv must not include itself")
        continue
    if Path(manifest_relative_path).is_absolute() or ".." in Path(manifest_relative_path).parts:
        fail(f"{manifest_relative_path}: path must be relative to the submission packet")
        continue
    if manifest_relative_path in seen_paths:
        fail(f"{manifest_relative_path}: duplicate manifest entry")
        continue
    seen_paths.add(manifest_relative_path)

    if not manifest_bytes.isdigit():
        fail(f"{manifest_relative_path}: bytes value is not a non-negative integer")
        continue
    if not sha_pattern.fullmatch(manifest_sha):
        fail(f"{manifest_relative_path}: sha256 value is not a 64-character lowercase hex digest")
        continue

    file_path = packet_dir / manifest_relative_path
    if not file_path.is_file():
        fail(f"{manifest_relative_path}: manifest references a missing file")
        continue
    if file_path.is_symlink():
        fail(f"{manifest_relative_path}: manifest references a symlink")
        continue

    actual_bytes = file_path.stat().st_size
    expected_bytes = int(manifest_bytes)
    if actual_bytes != expected_bytes:
        fail(f"{manifest_relative_path}: byte count mismatch ({actual_bytes} != {expected_bytes})")

    actual_sha = sha256_for_file(file_path)
    if actual_sha != manifest_sha:
        fail(f"{manifest_relative_path}: sha256 mismatch ({actual_sha} != {manifest_sha})")

actual_files = {
    relative_to_packet(path)
    for path in packet_dir.rglob("*")
    if path.is_file() and relative_to_packet(path) != "file-manifest.tsv"
}

missing_from_manifest = sorted(actual_files - seen_paths)
for path in missing_from_manifest:
    fail(f"{path}: file is missing from file-manifest.tsv")

missing_from_packet = sorted(seen_paths - actual_files)
for path in missing_from_packet:
    fail(f"{path}: manifest entry is missing from packet files")

if failures:
    for message in failures:
        print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

print("File manifest integrity validation passed.")
PY
