#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path
import plistlib
import re
import subprocess
import sys

EXPECTED_APP_NAME = "FreePrint Studio"
EXPECTED_BUNDLE_ID = "com.dannagrace.FreePrintStudio"
EXPECTED_MARKETING_VERSION = "1.0"
EXPECTED_BUILD_NUMBER = "2"
EXPECTED_DEVICE_FAMILIES = {"1", "2"}

failures = []


def fail(message: str) -> None:
    failures.append(message)


def read_text(path: Path) -> str:
    if not path.is_file():
        fail(f"Missing required file: {path}")
        return ""
    return path.read_text(encoding="utf-8").strip()


def metadata_section(markdown: str, heading: str) -> str:
    match = re.search(rf"^## {re.escape(heading)}\n(.*?)(?=^## |\Z)", markdown, re.M | re.S)
    if not match:
        fail(f"AppStore/metadata.md is missing section: {heading}")
        return ""
    return match.group(1).strip()


def check_equal(label: str, actual: str, expected: str) -> None:
    if actual != expected:
        fail(f"{label} is {actual or 'missing'}, expected {expected}")


def xcode_build_settings() -> dict[str, str]:
    result = subprocess.run(
        [
            "xcodebuild",
            "-project",
            "FreePrintStudio.xcodeproj",
            "-scheme",
            "FreePrintStudio",
            "-configuration",
            "Release",
            "-destination",
            "generic/platform=iOS",
            "-showBuildSettings",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode != 0:
        fail("xcodebuild -showBuildSettings failed")
        print(result.stdout)
        return {}

    settings: dict[str, str] = {}
    for line in result.stdout.splitlines():
        match = re.match(r"\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$", line)
        if match:
            settings[match.group(1)] = match.group(2).strip()
    return settings


def ruby_constant(source: str, name: str) -> str:
    match = re.search(rf"^{re.escape(name)}\s*=\s*[\"']([^\"']+)[\"']", source, re.M)
    if not match:
        fail(f"fastlane/Fastfile is missing {name}")
        return ""
    return match.group(1)


def deliver_value(source: str, function_name: str) -> str:
    match = re.search(rf"^{re.escape(function_name)}\([\"']([^\"']+)[\"']\)", source, re.M)
    if not match:
        fail(f"fastlane/Deliverfile is missing {function_name}")
        return ""
    return match.group(1)


settings = xcode_build_settings()
check_equal("PRODUCT_BUNDLE_IDENTIFIER", settings.get("PRODUCT_BUNDLE_IDENTIFIER", ""), EXPECTED_BUNDLE_ID)
check_equal("MARKETING_VERSION", settings.get("MARKETING_VERSION", ""), EXPECTED_MARKETING_VERSION)
check_equal("CURRENT_PROJECT_VERSION", settings.get("CURRENT_PROJECT_VERSION", ""), EXPECTED_BUILD_NUMBER)

targeted_device_family = settings.get("TARGETED_DEVICE_FAMILY", "")
actual_families = {family.strip() for family in targeted_device_family.split(",") if family.strip()}
if actual_families != EXPECTED_DEVICE_FAMILIES:
    fail(f"TARGETED_DEVICE_FAMILY is {targeted_device_family or 'missing'}, expected 1,2")

if Path("AppStore/Screenshots/ipad-main.jpg").is_file() and "2" not in actual_families:
    fail("iPad screenshot exists, but TARGETED_DEVICE_FAMILY does not include iPad family 2")
if Path("AppStore/Screenshots/iphone-main.jpg").is_file() and "1" not in actual_families:
    fail("iPhone screenshot exists, but TARGETED_DEVICE_FAMILY does not include iPhone family 1")

info_path = Path("FreePrintStudio/Resources/Info.plist")
if info_path.is_file():
    with info_path.open("rb") as plist_file:
        info = plistlib.load(plist_file)
    check_equal("CFBundleDisplayName", str(info.get("CFBundleDisplayName", "")), EXPECTED_APP_NAME)
    check_equal("CFBundleIdentifier", str(info.get("CFBundleIdentifier", "")), "$(PRODUCT_BUNDLE_IDENTIFIER)")
    check_equal("CFBundleShortVersionString", str(info.get("CFBundleShortVersionString", "")), "$(MARKETING_VERSION)")
    check_equal("CFBundleVersion", str(info.get("CFBundleVersion", "")), "$(CURRENT_PROJECT_VERSION)")
else:
    fail("Missing required file: FreePrintStudio/Resources/Info.plist")

fastfile = read_text(Path("fastlane/Fastfile"))
if fastfile:
    check_equal("fastlane/Fastfile APP_IDENTIFIER", ruby_constant(fastfile, "APP_IDENTIFIER"), EXPECTED_BUNDLE_ID)
    check_equal("fastlane/Fastfile APP_VERSION", ruby_constant(fastfile, "APP_VERSION"), EXPECTED_MARKETING_VERSION)

deliverfile = read_text(Path("fastlane/Deliverfile"))
if deliverfile:
    check_equal("fastlane/Deliverfile app_identifier", deliver_value(deliverfile, "app_identifier"), EXPECTED_BUNDLE_ID)
    check_equal("fastlane/Deliverfile app_version", deliver_value(deliverfile, "app_version"), EXPECTED_MARKETING_VERSION)

metadata_name = read_text(Path("fastlane/metadata/en-US/name.txt"))
if metadata_name:
    check_equal("fastlane metadata app name", metadata_name, EXPECTED_APP_NAME)

metadata_draft = read_text(Path("AppStore/metadata.md"))
if metadata_draft:
    check_equal("AppStore metadata app name", metadata_section(metadata_draft, "App Name"), EXPECTED_APP_NAME)

if failures:
    for failure in failures:
        print(f"FAIL: {failure}")
    sys.exit(1)

print("App identity validation passed.")
PY
