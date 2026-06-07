#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path
import re
import sys

ROOT = Path(".")
METADATA = ROOT / "fastlane" / "metadata" / "en-US"
NONLOCALIZED_METADATA = ROOT / "fastlane" / "metadata"
REVIEW_METADATA = ROOT / "fastlane" / "metadata" / "review_information"
APPSTORE_METADATA = ROOT / "AppStore" / "metadata.md"

failures = []


def read_text(path: Path) -> str:
    if not path.is_file():
        failures.append(f"missing required metadata file: {path}")
        return ""
    return path.read_text(encoding="utf-8").strip()


def char_count(text: str) -> int:
    return len(text)


def byte_count(text: str) -> int:
    return len(text.encode("utf-8"))


def check_char_limit(label: str, path: str, minimum: int | None, maximum: int, base: Path = METADATA) -> None:
    text = read_text(base / path)
    count = char_count(text)
    if minimum is not None and count < minimum:
        failures.append(f"{label} is {count} characters; minimum is {minimum}")
    if count > maximum:
        failures.append(f"{label} is {count} characters; maximum is {maximum}")


check_char_limit("App name", "name.txt", 2, 30)
check_char_limit("Subtitle", "subtitle.txt", None, 30)
check_char_limit("Promotional text", "promotional_text.txt", None, 170)
check_char_limit("Description", "description.txt", None, 4000)
check_char_limit("Release notes", "release_notes.txt", None, 4000)
check_char_limit("Review notes", "notes.txt", None, 4000, REVIEW_METADATA)

copyright_text = read_text(NONLOCALIZED_METADATA / "copyright.txt")
if copyright_text and not re.match(r"^(Copyright\s+|©\s*)?(19|20)\d{2}\s+\S", copyright_text):
    failures.append("Copyright must include a four-digit year and owner name")

keywords_text = read_text(METADATA / "keywords.txt")
if byte_count(keywords_text) > 100:
    failures.append(f"Keywords are {byte_count(keywords_text)} UTF-8 bytes; maximum is 100")

keywords = [keyword.strip() for keyword in keywords_text.split(",") if keyword.strip()]
if not keywords:
    failures.append("Keywords must not be empty")
if len(keywords) != len(set(keyword.lower() for keyword in keywords)):
    failures.append("Keywords must not contain duplicates")

for keyword in keywords:
    if len(keyword) <= 2:
        failures.append(f"Keyword '{keyword}' must be greater than 2 characters")
    if "," in keyword:
        failures.append(f"Keyword '{keyword}' must not contain a comma")

metadata_draft = read_text(APPSTORE_METADATA)
if keywords_text and keywords_text not in metadata_draft:
    failures.append("AppStore/metadata.md keywords must match fastlane keywords.txt")
if copyright_text and copyright_text not in metadata_draft:
    failures.append("AppStore/metadata.md must include the Fastlane copyright value")
if read_text(METADATA / "release_notes.txt") not in metadata_draft:
    failures.append("AppStore/metadata.md must include the Fastlane release notes")
if read_text(REVIEW_METADATA / "notes.txt") not in metadata_draft:
    failures.append("AppStore/metadata.md must include the Fastlane app review notes")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}")
    sys.exit(1)

print("App Store metadata limits passed.")
PY
