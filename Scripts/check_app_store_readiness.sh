#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0
warnings=0

ok() {
  printf 'OK: %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1"
  warnings=$((warnings + 1))
}

block() {
  printf 'BLOCKED: %s\n' "$1"
  failures=$((failures + 1))
}

setting_value() {
  local key="$1"
  xcodebuild \
    -project FreePrintStudio.xcodeproj \
    -scheme FreePrintStudio \
    -configuration Release \
    -showBuildSettings 2>/dev/null \
    | awk -F'= ' -v key="$key" '{
        lhs = $1
        gsub(/^[ \t]+|[ \t]+$/, "", lhs)
        if (lhs == key) {
          gsub(/^[ \t]+|[ \t]+$/, "", $2)
          print $2
          exit
        }
      }'
}

check_public_page() {
  local label="$1"
  local url="$2"
  local expected="$3"
  local body_path
  local safe_label
  local status
  local attempt
  safe_label="$(tr -cd '[:alnum:]_-' <<<"$label")"
  body_path="$(mktemp "/tmp/freeprintstudio-${safe_label}.XXXXXX")"
  status="000"
  for attempt in 1 2 3; do
    status="$(curl -L -s --connect-timeout 10 --max-time 20 -o "$body_path" -w '%{http_code}' "$url" || true)"
    [[ "$status" == "200" ]] && break
    sleep 2
  done
  if [[ "$status" != "200" ]]; then
    block "$label URL is not publicly reachable: $url returned $status"
  elif ! grep -q "$expected" "$body_path"; then
    block "$label URL did not contain expected text: $expected"
  else
    ok "$label URL is public: $url"
  fi
  rm -f "$body_path"
}

check_screenshot_size() {
  local path="$1"
  local label="$2"
  local accepted="$3"
  local width
  local height

  if [[ ! -s "$path" ]]; then
    block "$label screenshot missing: $path"
    return
  fi

  width="$(sips -g pixelWidth "$path" | awk -F': ' '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$path" | awk -F': ' '/pixelHeight/ { print $2 }')"
  if grep -Eq "(^|,)$width x $height(,|$)" <<<"$accepted"; then
    ok "$label screenshot size accepted: $width x $height"
  else
    block "$label screenshot size invalid: $width x $height; accepted: $accepted"
  fi
}

bundle_check() {
  local log_path="$1"
  python3 - "$log_path" <<'PY'
import subprocess
import sys

log_path = sys.argv[1]
with open(log_path, "w") as log:
    try:
        result = subprocess.run(
            ["bundle", "check"],
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=15,
        )
    except FileNotFoundError:
        sys.exit(127)
    except subprocess.TimeoutExpired:
        log.write("bundle check timed out after 15 seconds\n")
        sys.exit(124)
sys.exit(result.returncode)
PY
}

printf '== Project ==\n'
bundle_id="$(setting_value PRODUCT_BUNDLE_IDENTIFIER)"
marketing_version="$(setting_value MARKETING_VERSION)"
build_number="$(setting_value CURRENT_PROJECT_VERSION)"
project_team_id="$(setting_value DEVELOPMENT_TEAM)"
team_id="${DEVELOPMENT_TEAM_ID:-$project_team_id}"

[[ "$bundle_id" == "com.dannagrace.FreePrintStudio" ]] && ok "Bundle ID: $bundle_id" || block "Unexpected bundle ID: ${bundle_id:-missing}"
[[ "$marketing_version" == "1.0" ]] && ok "Marketing version: $marketing_version" || block "Unexpected marketing version: ${marketing_version:-missing}"
[[ "$build_number" == "1" ]] && ok "Build number: $build_number" || block "Unexpected build number: ${build_number:-missing}"

printf '\n== Static Assets ==\n'
Scripts/release_check.sh >/tmp/freeprintstudio-release-check.log 2>&1 && ok "Static release assets pass Scripts/release_check.sh" || {
  block "Static release assets failed Scripts/release_check.sh"
  cat /tmp/freeprintstudio-release-check.log
}

check_screenshot_size "AppStore/Screenshots/iphone-main.jpg" "iPhone 6.9-inch" "1260 x 2736,1290 x 2796,1320 x 2868"
check_screenshot_size "AppStore/Screenshots/iphone-fit.jpg" "iPhone Fit mode" "1260 x 2736,1290 x 2796,1320 x 2868"
check_screenshot_size "AppStore/Screenshots/iphone-fill.jpg" "iPhone Fill mode" "1260 x 2736,1290 x 2796,1320 x 2868"
check_screenshot_size "AppStore/Screenshots/iphone-stretch.jpg" "iPhone Stretch mode" "1260 x 2736,1290 x 2796,1320 x 2868"
check_screenshot_size "AppStore/Screenshots/ipad-main.jpg" "iPad 13-inch" "2048 x 2732,2064 x 2752"
check_screenshot_size "fastlane/screenshots/en-US/iphone-main.jpg" "Fastlane iPhone" "1260 x 2736,1290 x 2796,1320 x 2868"
check_screenshot_size "fastlane/screenshots/en-US/iphone-fit.jpg" "Fastlane iPhone Fit" "1260 x 2736,1290 x 2796,1320 x 2868"
check_screenshot_size "fastlane/screenshots/en-US/iphone-fill.jpg" "Fastlane iPhone Fill" "1260 x 2736,1290 x 2796,1320 x 2868"
check_screenshot_size "fastlane/screenshots/en-US/iphone-stretch.jpg" "Fastlane iPhone Stretch" "1260 x 2736,1290 x 2796,1320 x 2868"
check_screenshot_size "fastlane/screenshots/en-US/ipad-main.jpg" "Fastlane iPad" "2048 x 2732,2064 x 2752"

printf '\n== App Store Questionnaires ==\n'
if grep -q "No, we do not collect data from this app" AppStore/app-privacy.md \
  && grep -q "Tracking: No" AppStore/app-privacy.md; then
  ok "App privacy answers prepared: no data collection, no tracking"
else
  block "App privacy answers are incomplete"
fi

if grep -q "Expected global age rating: 4+" AppStore/age-rating.md \
  && grep -q "User-generated content: None" AppStore/age-rating.md; then
  ok "Age rating answers prepared: expected 4+"
else
  block "Age rating answers are incomplete"
fi

if grep -q "VoiceOver: Supported" AppStore/accessibility-labels.md \
  && grep -q "Larger Text: Supported" AppStore/accessibility-labels.md; then
  ok "Accessibility Nutrition Label draft prepared"
else
  block "Accessibility Nutrition Label draft is incomplete"
fi

export_compliance_value="$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - FreePrintStudio/Resources/Info.plist 2>/dev/null || true)"
if grep -q "Uses non-exempt encryption: No" AppStore/export-compliance.md \
  && [[ "$export_compliance_value" == "false" ]]; then
  ok "Export compliance answers prepared: no non-exempt encryption"
else
  block "Export compliance answers or Info.plist encryption declaration are incomplete"
fi

printf '\n== Public Pages ==\n'
check_public_page "Privacy policy" "https://dannagrace.github.io/FreePrintStudio/privacy-policy.html" "FreePrint Studio Privacy Policy"
check_public_page "Support" "https://dannagrace.github.io/FreePrintStudio/support.html" "FreePrint Studio Support"

printf '\n== Tooling ==\n'
if xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ' ')"; then
  ok "Xcode available: $xcode_version"
else
  block "xcodebuild is not available"
fi

ruby_version="$(ruby -e 'print RUBY_VERSION' 2>/dev/null || true)"
if [[ -n "$ruby_version" ]]; then
  ok "Ruby available for Bundler/Fastlane: $ruby_version"
else
  block "Ruby is not available for Bundler/Fastlane"
fi

if [[ -f Gemfile.lock ]] && bundle_check /tmp/freeprintstudio-bundle-check.log; then
  ok "Bundler dependencies are installed"
  if bundle exec fastlane --version >/tmp/freeprintstudio-fastlane-version.log 2>&1; then
    fastlane_version="$(awk '/^fastlane [0-9]+/ { print; exit }' /tmp/freeprintstudio-fastlane-version.log)"
    ok "Fastlane available via Bundler: ${fastlane_version:-$(head -n 1 /tmp/freeprintstudio-fastlane-version.log)}"
  else
    warn "Bundler dependencies are installed, but bundle exec fastlane did not run"
  fi
elif command -v fastlane >/dev/null 2>&1; then
  fastlane_version="$(SKIP_SLOW_FASTLANE_WARNING=1 FASTLANE_SKIP_UPDATE_CHECK=1 fastlane --version | awk '/^fastlane [0-9]+/ { print; exit }')"
  ok "Fastlane available globally: ${fastlane_version:-$(command -v fastlane)}"
else
  warn "Bundler dependencies are not installed; run Scripts/install_release_dependencies.sh. Gemfile pins Fastlane below 2.232 for macOS system Ruby 2.6 compatibility."
  warn "Fastlane is not available yet; install Bundler dependencies or run brew install fastlane before metadata upload"
fi

printf '\n== Signing ==\n'
if [[ -n "$team_id" ]]; then
  ok "Apple Developer Team ID configured via DEVELOPMENT_TEAM_ID or project: $team_id"
else
  block "Apple Developer Team ID missing; set DEVELOPMENT_TEAM_ID or configure DEVELOPMENT_TEAM in Xcode"
fi

identity_count="$(
  security find-identity -v -p codesigning 2>/dev/null \
    | awk '/valid identities found/ { print $1 }'
)"
identity_count="${identity_count:-0}"
if [[ "$identity_count" =~ ^[0-9]+$ ]] && (( identity_count > 0 )); then
  ok "Code signing identities available: $identity_count"
else
  block "No valid code signing identities found in the keychain"
fi

profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
if [[ -d "$profiles_dir" ]]; then
  profile_count="$(
    find "$profiles_dir" -maxdepth 1 -type f 2>/dev/null \
      | wc -l \
      | tr -d ' '
  )"
else
  profile_count="0"
fi
profile_count="${profile_count:-0}"
if [[ "$profile_count" =~ ^[0-9]+$ ]] && (( profile_count > 0 )); then
  ok "Provisioning profiles available: $profile_count"
else
  block "No provisioning profiles found under ~/Library/MobileDevice/Provisioning Profiles"
fi

printf '\n== App Store Connect ==\n'
if Scripts/check_app_store_connect_credentials.sh >/tmp/freeprintstudio-asc-credentials.log 2>&1; then
  ok "Fastlane App Store Connect API credentials are configured"
else
  warn "Fastlane App Store Connect API credentials are not configured; automated metadata and TestFlight upload will be blocked"
  sed 's/^BLOCKED:/missing:/; s/^/  /' /tmp/freeprintstudio-asc-credentials.log
fi
warn "App Store Connect app record and TestFlight status require account-specific verification outside this local audit"

printf '\nSummary: %d blocker(s), %d warning(s).\n' "$failures" "$warnings"
if (( failures > 0 )); then
  printf '\nNext signed archive command after fixing blockers:\n'
  printf '  DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh\n'
  exit 1
fi

printf '\nReady to attempt a signed App Store archive:\n'
printf '  DEVELOPMENT_TEAM_ID=%s ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh\n' "$team_id"
