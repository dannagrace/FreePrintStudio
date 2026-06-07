#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

check_no_matches() {
  local label="$1"
  local pattern="$2"
  shift 2
  local matches

  matches="$(rg -n -i "$pattern" "$@" || true)"
  if [[ -n "$matches" ]]; then
    fail "$label"
    printf '%s\n' "$matches" | sed 's/^/  /'
  fi
}

check_plist_absent() {
  local path="$1"
  local key="$2"
  local message="$3"

  if plutil -extract "$key" raw -o - "$path" >/dev/null 2>&1; then
    fail "$message"
  fi
}

SOURCE_PATHS=(
  FreePrintStudio
  Sources
  Package.swift
  FreePrintStudio.xcodeproj/project.pbxproj
)

CONFIG_PATHS=(
  Package.swift
  FreePrintStudio.xcodeproj/project.pbxproj
  Gemfile
)
if [[ -f Gemfile.lock ]]; then
  CONFIG_PATHS+=(Gemfile.lock)
fi

check_no_matches \
  "Direct network API usage conflicts with the no-data-collection App Privacy label" \
  'URLSession|NSURLSession|URLRequest|NSURLConnection|NWConnection|NWPathMonitor|import[[:space:]]+Network|import[[:space:]]+WebKit|WKWebView|SFSafariViewController' \
  "${SOURCE_PATHS[@]}"

check_no_matches \
  "analytics, advertising, attribution, push, or tracking SDK references conflict with the App Privacy label" \
  '\b(analytics|Firebase|Crashlytics|GoogleAnalytics|Amplitude|Mixpanel|Segment|Sentry|AdMob|GAD[A-Za-z]*|Appsflyer|AppsFlyer|Adjust|Branch|Facebook|Meta|OneSignal|RevenueCat|SKAdNetwork|AdServices|AppTrackingTransparency|ATTrackingManager|IDFA|advertisingIdentifier)\b' \
  "${CONFIG_PATHS[@]}"

if rg -n '\.package[[:space:]]*\(' Package.swift >/tmp/freeprintstudio-package-dependencies.log 2>&1; then
  fail "Package.swift must not add third-party package dependencies without updating privacy disclosures"
  sed 's/^/  /' /tmp/freeprintstudio-package-dependencies.log
fi

check_plist_absent \
  "FreePrintStudio/Resources/Info.plist" \
  "NSAppTransportSecurity" \
  "Info.plist must not add App Transport Security exceptions while privacy label says local-only"

check_plist_absent \
  "FreePrintStudio/Resources/Info.plist" \
  "NSAdvertisingAttributionReportEndpoint" \
  "Info.plist must not declare advertising attribution endpoints"

check_plist_absent \
  "FreePrintStudio/Resources/Info.plist" \
  "SKAdNetworkItems" \
  "Info.plist must not declare advertising network identifiers"

plist_failures="$(python3 <<'PY'
import plistlib
from pathlib import Path

path = Path("FreePrintStudio/Resources/PrivacyInfo.xcprivacy")
try:
    manifest = plistlib.loads(path.read_bytes())
except Exception as exc:
    print(f"Privacy manifest must be readable as a plist: {exc}")
    raise SystemExit

if manifest.get("NSPrivacyTracking") is not False:
    print("Privacy manifest must declare NSPrivacyTracking as false")
if manifest.get("NSPrivacyCollectedDataTypes") != []:
    print("Privacy manifest must declare no collected data types")
if manifest.get("NSPrivacyTrackingDomains") != []:
    print("Privacy manifest must declare no tracking domains")
PY
)"
if [[ -n "$plist_failures" ]]; then
  while IFS= read -r message; do
    fail "$message"
  done <<<"$plist_failures"
fi

if [[ "$failures" -gt 0 ]]; then
  printf '\nPrivacy surface validation failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'Privacy surface validation passed.\n'
