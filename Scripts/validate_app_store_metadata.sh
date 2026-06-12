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


def metadata_section(markdown: str, heading: str) -> str:
    match = re.search(rf"^## {re.escape(heading)}\n(.*?)(?=^## |\Z)", markdown, re.M | re.S)
    if not match:
        failures.append(f"AppStore/metadata.md is missing section: {heading}")
        return ""
    return match.group(1).strip()


def labeled_value(section: str, label: str) -> str:
    match = re.search(rf"^{re.escape(label)}:\s*(.+)$", section, re.M)
    if not match:
        failures.append(f"AppStore/metadata.md is missing value: {label}")
        return ""
    return match.group(1).strip()


def check_metadata_match(label: str, expected: str, actual: str) -> None:
    if expected and actual and expected != actual:
        failures.append(f"{label} must match the Fastlane upload source")


def check_review_notes_requirements(review_notes: str) -> None:
    lower_notes = review_notes.lower()
    required_phrases = [
        ("account requirement", "does not require an account"),
        ("local image processing", "locally on device"),
        ("Photos import test path", "Choose an image from Photos"),
        ("Test Ruler test path", "Test Ruler"),
        ("six inch calibration guide", "six inch"),
        ("PDF export test path", "Export PDF"),
        ("AirPrint test path", "AirPrint"),
        ("no image upload disclosure", "does not upload images"),
        ("no analytics disclosure", "analytics"),
        ("no ads disclosure", "ads"),
        ("no tracking disclosure", "track users"),
    ]

    for label, phrase in required_phrases:
        if phrase.lower() not in lower_notes:
            failures.append(f"Review notes must include {label}: {phrase}")

    numbered_steps = re.findall(r"^\d+\.\s+\S", review_notes, re.M)
    if len(numbered_steps) < 4:
        failures.append("Review notes must include at least four numbered reviewer test steps")

    if re.search(r"\b(TODO|TBD|PLACEHOLDER)\b", review_notes, re.I):
        failures.append("Review notes must not contain TODO, TBD, or PLACEHOLDER text")


check_char_limit("App name", "name.txt", 2, 30)
check_char_limit("Subtitle", "subtitle.txt", None, 30)
check_char_limit("Promotional text", "promotional_text.txt", None, 170)
check_char_limit("Description", "description.txt", None, 4000)
check_char_limit("Release notes", "release_notes.txt", None, 4000)
check_char_limit("Review notes", "notes.txt", None, 4000, REVIEW_METADATA)
review_notes_text = read_text(REVIEW_METADATA / "notes.txt")
check_review_notes_requirements(review_notes_text)

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
urls_section = metadata_section(metadata_draft, "URLs")

metadata_matches = [
    ("App name", read_text(METADATA / "name.txt"), metadata_section(metadata_draft, "App Name")),
    ("Subtitle", read_text(METADATA / "subtitle.txt"), metadata_section(metadata_draft, "Subtitle")),
    (
        "Promotional text",
        read_text(METADATA / "promotional_text.txt"),
        metadata_section(metadata_draft, "Promotional Text"),
    ),
    ("Description", read_text(METADATA / "description.txt"), metadata_section(metadata_draft, "Description")),
    ("Keywords", keywords_text, metadata_section(metadata_draft, "Keywords")),
    ("Copyright", copyright_text, metadata_section(metadata_draft, "Copyright")),
    ("Release notes", read_text(METADATA / "release_notes.txt"), metadata_section(metadata_draft, "Version Release Notes")),
    ("Review notes", review_notes_text, metadata_section(metadata_draft, "Review Notes")),
    (
        "Privacy URL",
        read_text(METADATA / "privacy_url.txt"),
        labeled_value(urls_section, "Privacy Policy URL"),
    ),
    (
        "Support URL",
        read_text(METADATA / "support_url.txt"),
        labeled_value(urls_section, "Support URL"),
    ),
]

for label, expected, actual in metadata_matches:
    check_metadata_match(label, expected, actual)

if failures:
    for failure in failures:
        print(f"FAIL: {failure}")
    sys.exit(1)

print("App Store metadata limits passed.")
PY
