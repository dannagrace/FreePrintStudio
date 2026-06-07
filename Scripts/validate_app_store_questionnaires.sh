#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

failures = []

AGE_RATING = Path("AppStore/age-rating.md")
APP_PRIVACY = Path("AppStore/app-privacy.md")
ACCESSIBILITY = Path("AppStore/accessibility-labels.md")
EXPORT_COMPLIANCE = Path("AppStore/export-compliance.md")
PRIVACY_DETAILS = Path("AppStore/app_privacy_details.json")
PRIVACY_MANIFEST = Path("FreePrintStudio/Resources/PrivacyInfo.xcprivacy")
INFO_PLIST = Path("FreePrintStudio/Resources/Info.plist")
CONTENT_VIEW = Path("FreePrintStudio/ContentView.swift")
FASTLANE_PRIVACY_URL = Path("fastlane/metadata/en-US/privacy_url.txt")
FASTLANE_SUPPORT_URL = Path("fastlane/metadata/en-US/support_url.txt")


def read_text(path):
    if not path.is_file():
        failures.append(f"missing required file: {path}")
        return ""
    return path.read_text(encoding="utf-8")


def require_text(path, text, message):
    content = read_text(path)
    if text not in content:
        failures.append(f"{message} ({path} missing {text})")
    return content


def require_regex(path, pattern, message):
    content = read_text(path)
    if not re.search(pattern, content, re.M):
        failures.append(f"{message} ({path} missing pattern {pattern})")
    return content


def load_json(path):
    try:
        return json.loads(read_text(path))
    except Exception as exc:
        failures.append(f"{path} is not valid JSON: {exc}")
        return None


def plist_raw(path, key):
    result = subprocess.run(
        ["plutil", "-extract", key, "raw", "-o", "-", str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        failures.append(f"{path} is missing plist key {key}")
        return ""
    return result.stdout.strip()


def plist_json(path):
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        failures.append(f"{path} could not be parsed as JSON plist: {result.stderr.strip()}")
        return {}
    return json.loads(result.stdout)


def require_all_none(path, labels, section_name):
    content = read_text(path)
    for label in labels:
        expected = f"- {label}: None"
        if expected not in content:
            failures.append(f"{section_name} must answer None for {label}")


privacy_url = read_text(FASTLANE_PRIVACY_URL).strip()
support_url = read_text(FASTLANE_SUPPORT_URL).strip()

app_privacy = require_text(
    APP_PRIVACY,
    "Answer: No, we do not collect data from this app.",
    "App Privacy questionnaire must declare no data collection",
)
for required in (
    "Tracking: No",
    "Third-party SDKs: None",
    "Data Types: None",
    "User Privacy Choices URL\n\nNot applicable.",
):
    if required not in app_privacy:
        failures.append(f"App Privacy questionnaire is missing: {required}")
if privacy_url and privacy_url not in app_privacy:
    failures.append("App Privacy questionnaire must use the Fastlane privacy URL")

privacy_details = load_json(PRIVACY_DETAILS)
if privacy_details != [{"data_protections": ["DATA_NOT_COLLECTED"]}]:
    failures.append("App Privacy Details JSON must declare only DATA_NOT_COLLECTED")

privacy_manifest = plist_json(PRIVACY_MANIFEST)
if privacy_manifest.get("NSPrivacyTracking") is not False:
    failures.append("Privacy manifest must declare NSPrivacyTracking as false")
if privacy_manifest.get("NSPrivacyCollectedDataTypes") != []:
    failures.append("Privacy manifest must declare no collected data types")
if privacy_manifest.get("NSPrivacyTrackingDomains") != []:
    failures.append("Privacy manifest must declare no tracking domains")
if privacy_manifest.get("NSPrivacyAccessedAPITypes") != []:
    failures.append("Privacy manifest must declare no accessed API types")

photo_usage = plist_raw(INFO_PLIST, "NSPhotoLibraryUsageDescription")
if "selected image locally" not in photo_usage:
    failures.append("Photo library usage description must say selected images are processed locally")

age_rating = require_text(AGE_RATING, "Expected global age rating: 4+", "Age rating questionnaire must target 4+")
require_all_none(
    AGE_RATING,
    (
        "Profanity or crude humor",
        "Mature or suggestive themes",
        "Horror or fear themes",
        "Medical or treatment information",
        "Alcohol, tobacco, drug use, or references",
        "Simulated gambling",
        "Sexual content or nudity",
        "Cartoon or fantasy violence",
        "Realistic violence",
        "Realistic violence with blood or gore",
    ),
    "Age rating content descriptors",
)
for required in (
    "User-generated content: None",
    "Messaging and chat: None",
    "Advertising: None",
    "Unrestricted web access: No",
    "Gambling or contests: None",
    "In-app purchases: None",
    "Web links: Limited to the app privacy policy and support page from the About screen",
):
    if required not in age_rating:
        failures.append(f"Age rating questionnaire is missing: {required}")

source = read_text(CONTENT_VIEW)
source_urls = set(re.findall(r'https?://[^"\s)]+', source))
expected_urls = set(url for url in (privacy_url, support_url) if url)
if source_urls != expected_urls:
    failures.append(
        "App source URLs must match the age-rating limited-web-links answer "
        f"(found {sorted(source_urls)}, expected {sorted(expected_urls)})"
    )

for prohibited in (
    "WKWebView",
    "SFSafariViewController",
    "ASWebAuthenticationSession",
    "SKPayment",
    "Product(",
):
    if prohibited in source:
        failures.append(f"Age rating answers must be re-reviewed because app source references {prohibited}")

for required in (
    "iPhone: Indicate support",
    "iPad: Indicate support",
    "VoiceOver: Supported",
    "Larger Text: Supported",
    "Dark Interface: Supported",
    "Sufficient Contrast: Supported",
    "Differentiate Without Color Alone: Supported",
    "Reduced Motion: Supported",
):
    require_text(ACCESSIBILITY, required, "Accessibility Nutrition Label draft is incomplete")

export_compliance = require_regex(
    EXPORT_COMPLIANCE,
    r"^- Uses non-exempt encryption: No$",
    "Export compliance questionnaire must declare no non-exempt encryption",
)
if "Info.plist key: `ITSAppUsesNonExemptEncryption`" not in export_compliance:
    failures.append("Export compliance questionnaire must name ITSAppUsesNonExemptEncryption")

encryption_value = plist_raw(INFO_PLIST, "ITSAppUsesNonExemptEncryption")
if encryption_value != "false":
    failures.append("Info.plist ITSAppUsesNonExemptEncryption must be false")
if "upload selected images" not in export_compliance or "custom cryptography" not in export_compliance:
    failures.append("Export compliance rationale must cover no upload and no custom cryptography")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}")
    sys.exit(1)

print("App Store questionnaire validation passed.")
PY
