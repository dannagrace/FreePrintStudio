#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PACKET_DIR="${FREEPRINTSTUDIO_SUBMISSION_PACKET_DIR:-build/AppStoreSubmissionPacket}"
failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

require_file() {
  local relative_path="$1"
  local description="$2"
  if [[ ! -s "$PACKET_DIR/$relative_path" ]]; then
    fail "$description is missing or empty: $PACKET_DIR/$relative_path"
  fi
}

require_contains() {
  local relative_path="$1"
  local pattern="$2"
  local description="$3"
  if [[ ! -s "$PACKET_DIR/$relative_path" ]]; then
    fail "$description cannot be checked because $PACKET_DIR/$relative_path is missing"
    return
  fi
  if ! grep -qF "$pattern" "$PACKET_DIR/$relative_path"; then
    fail "$description is missing from $PACKET_DIR/$relative_path"
  fi
}

require_tsv_header() {
  local relative_path="$1"
  local expected_header="$2"
  local description="$3"
  local actual_header
  if [[ ! -s "$PACKET_DIR/$relative_path" ]]; then
    fail "$description is missing or empty: $PACKET_DIR/$relative_path"
    return
  fi
  actual_header="$(sed -n '1p' "$PACKET_DIR/$relative_path")"
  if [[ "$actual_header" != "$expected_header" ]]; then
    fail "$description has unexpected header: $actual_header"
  fi
}

require_tsv_column_populated() {
  local relative_path="$1"
  local column_index="$2"
  local description="$3"
  if [[ ! -s "$PACKET_DIR/$relative_path" ]]; then
    fail "$description cannot be checked because $PACKET_DIR/$relative_path is missing"
    return
  fi
  if ! awk -F '\t' -v column_index="$column_index" 'NR > 1 && $column_index == "" { exit 1 }' "$PACKET_DIR/$relative_path"; then
    fail "$description has empty values in column $column_index"
  fi
}

require_manifest_entry() {
  local manifest="$1"
  local expected_path="$2"
  local description="$3"
  if [[ ! -s "$PACKET_DIR/$manifest" ]]; then
    fail "$description cannot be checked because $PACKET_DIR/$manifest is missing"
    return
  fi
  if ! awk -F '\t' -v path="$expected_path" 'NR > 1 && $1 == path { found = 1 } END { exit(found ? 0 : 1) }' "$PACKET_DIR/$manifest"; then
    fail "$description is missing manifest entry: $expected_path"
  fi
}

require_manifest_files_exist() {
  local manifest="$PACKET_DIR/file-manifest.tsv"
  local relative_path
  if [[ ! -s "$manifest" ]]; then
    fail "file-manifest.tsv cannot be checked because it is missing"
    return
  fi

  while IFS=$'\t' read -r relative_path _; do
    [[ "$relative_path" == "path" ]] && continue
    if [[ ! -s "$PACKET_DIR/$relative_path" ]]; then
      fail "file-manifest.tsv references a missing or empty file: $relative_path"
    fi
  done <"$manifest"
}

require_no_local_path_leaks() {
  local leaked_paths
  leaked_paths="$(
    find "$PACKET_DIR" -type f \
      ! -path "$PACKET_DIR/files/AppStore/Screenshots/*" \
      ! -path "$PACKET_DIR/files/fastlane/screenshots/en-US/*" \
      -print0 \
      | xargs -0 grep -nE '/Users/|/private/var/folders/|/tmp/freeprintstudio|/var/folders/' 2>/dev/null \
      || true
  )"
  if [[ -n "$leaked_paths" ]]; then
    printf '%s\n' "$leaked_paths"
    fail "Submission packet contains leaked absolute local paths"
  fi
}

require_no_forbidden_private_artifacts() {
  local file_path
  local relative_path
  local forbidden_paths=""

  while IFS= read -r -d '' file_path; do
    relative_path="${file_path#"$PACKET_DIR/"}"
    # Block private inputs such as Config/release.env, AuthKey_*.p8, and fastlane-api-key.json.
    case "$relative_path" in
      release.env|*/release.env|manual-release-verification.env|*/manual-release-verification.env|\
      AuthKey_*.p8|*/AuthKey_*.p8|*.p8|*.p12|*.mobileprovision|*.provisionprofile|*.ipa|*.xcarchive|*.xcarchive/*|\
      fastlane-api-key.json|*/fastlane-api-key.json)
        forbidden_paths+="$relative_path"$'\n'
        ;;
    esac
  done < <(find "$PACKET_DIR" -type f -print0)

  if [[ -n "$forbidden_paths" ]]; then
    printf '%s' "$forbidden_paths"
    fail "Submission packet contains forbidden private release artifacts"
  fi
}

require_no_private_key_material() {
  local leaked_keys
  leaked_keys="$(
    find "$PACKET_DIR" -type f -print0 \
      | xargs -0 grep -nE -- 'BEGIN .*PRIVATE KEY' 2>/dev/null \
      || true
  )"
  if [[ -n "$leaked_keys" ]]; then
    printf '%s\n' "$leaked_keys"
    fail "Submission packet contains embedded private key material"
  fi
}

require_no_symlinks() {
  local link_path
  local relative_path
  local symlinks=""

  while IFS= read -r -d '' link_path; do
    relative_path="${link_path#"$PACKET_DIR/"}"
    symlinks+="$relative_path"$'\n'
  done < <(find "$PACKET_DIR" -type l -print0)

  if [[ -n "$symlinks" ]]; then
    printf '%s' "$symlinks"
    fail "Submission packet contains symlinks"
  fi
}

if [[ ! -d "$PACKET_DIR" ]]; then
  printf 'FAIL: App Store submission packet directory is missing: %s\n' "$PACKET_DIR"
  exit 1
fi

required_files=(
  "SUMMARY.md"
  "ACTION_ITEMS.md"
  "release-input-status.txt"
  "readiness.txt"
  "screenshots.tsv"
  "pdf-export-validation.tsv"
  "file-manifest.tsv"
  "external-readiness-actions.tsv"
  "manual-release-evidence-form.md"
  "manual-release-readiness-report.md"
  "app-review-contact-readiness-report.md"
  "signing-readiness-report.md"
  "app-store-connect-readiness-report.md"
  "app-store-connect-state-report.md"
  "app-review-submission-readiness-report.md"
)

for relative_path in "${required_files[@]}"; do
  require_file "$relative_path" "$relative_path"
done

require_tsv_header "screenshots.tsv" $'path\twidth\theight\thasAlpha\tsha256' "screenshots.tsv"
require_tsv_header "pdf-export-validation.tsv" $'label\tcontent\tmode\tpaper\torientation\tunit\ttargetWidth\ttargetHeight\tpdfPath\tmediaBoxWidthPt\tmediaBoxHeightPt\tclipWidthPt\tclipHeightPt\tdrawWidthPt\tdrawHeightPt\tsha256' "pdf-export-validation.tsv"
require_tsv_header "file-manifest.tsv" $'path\tbytes\tsha256' "file-manifest.tsv"
require_tsv_header "external-readiness-actions.tsv" $'category	severity	owner	field	target	item	next_action	validation_command' "external-readiness-actions.tsv"
require_tsv_column_populated "external-readiness-actions.tsv" 4 "external-readiness-actions.tsv affected field tracking"
require_tsv_column_populated "external-readiness-actions.tsv" 5 "external-readiness-actions.tsv target tracking"

require_contains "pdf-export-validation.tsv" "test-ruler-stretch" "Test Ruler PDF validation evidence"
require_contains "ACTION_ITEMS.md" "## External Values To Provide" "external values checklist"
require_contains "ACTION_ITEMS.md" "## Command Order" "release command order"
require_contains "SUMMARY.md" "ACTION_ITEMS.md" "summary action item reference"
require_contains "SUMMARY.md" "release-input-status.txt" "summary redacted release input status reference"
require_contains "release-input-status.txt" "== Release Input Status ==" "redacted release input status header"
require_contains "release-input-status.txt" "== Missing Release Input Fields ==" "release input missing field checklist"
require_contains "release-input-status.txt" "MISSING_FIELD:" "release input field-level missing item output"
require_contains "SUMMARY.md" "external-readiness-actions.tsv" "summary external readiness manifest reference"
require_contains "SUMMARY.md" "app-store-connect-state-report.md" "summary App Store Connect state report reference"
require_contains "app-store-connect-state-report.md" "Scripts/check_app_store_connect_state.sh" "selected-build state report command tracking"
require_contains "app-store-connect-state-report.md" "Exit Code:" "selected-build state report exit code"
require_contains "app-store-connect-state-report.md" "Redacted Output" "selected-build state report redacted output"
require_contains "readiness.txt" "Summary:" "readiness audit summary"

if grep -qE 'Manual release verification evidence failed|Manual verifier|Real iPhone|AirPrint|TestFlight|MANUAL_' "$PACKET_DIR/readiness.txt"; then
  require_contains "external-readiness-actions.tsv" "Manual Verification" "manual verification external action tracking"
  require_contains "external-readiness-actions.tsv" "Scripts/validate_manual_release_verification.sh" "manual verification validation command tracking"
fi

if grep -q 'APP_REVIEW_CONTACT_' "$PACKET_DIR/readiness.txt"; then
  require_contains "external-readiness-actions.tsv" "App Review Contact" "App Review contact external action tracking"
  require_contains "external-readiness-actions.tsv" "Scripts/validate_app_review_contact.sh" "App Review contact validation command tracking"
fi

if grep -qE 'Apple Developer Team ID|Apple Distribution|provisioning profile' "$PACKET_DIR/readiness.txt"; then
  require_contains "external-readiness-actions.tsv" "Signing" "signing external action tracking"
  require_contains "external-readiness-actions.tsv" "Scripts/check_code_signing_assets.sh" "signing validation command tracking"
fi

if grep -qE 'FASTLANE_USER|App Store Connect|ASC_' "$PACKET_DIR/readiness.txt"; then
  require_contains "external-readiness-actions.tsv" "App Store Connect" "App Store Connect external action tracking"
  require_contains "external-readiness-actions.tsv" "Scripts/check_app_store_connect_credentials.sh" "App Store Connect validation command tracking"
fi

required_screenshot_entries=(
  "AppStore/Screenshots/iphone-main.jpg"
  "AppStore/Screenshots/iphone-test-ruler.jpg"
  "AppStore/Screenshots/iphone-fit.jpg"
  "AppStore/Screenshots/iphone-fill.jpg"
  "AppStore/Screenshots/iphone-stretch.jpg"
  "AppStore/Screenshots/iphone-metric-landscape.jpg"
  "AppStore/Screenshots/ipad-main.jpg"
  "fastlane/screenshots/en-US/iphone-main.jpg"
  "fastlane/screenshots/en-US/iphone-test-ruler.jpg"
  "fastlane/screenshots/en-US/iphone-fit.jpg"
  "fastlane/screenshots/en-US/iphone-fill.jpg"
  "fastlane/screenshots/en-US/iphone-stretch.jpg"
  "fastlane/screenshots/en-US/iphone-metric-landscape.jpg"
  "fastlane/screenshots/en-US/ipad-main.jpg"
)

for entry in "${required_screenshot_entries[@]}"; do
  require_manifest_entry "screenshots.tsv" "$entry" "screenshot evidence"
done

required_file_manifest_entries=(
  "ACTION_ITEMS.md"
  "SUMMARY.md"
  "external-readiness-actions.tsv"
  "pdf-export-validation.tsv"
  "readiness.txt"
  "screenshots.tsv"
  "files/AppStore/metadata.md"
  "files/AppStore/release-checklist.md"
  "files/Config/ExportOptions-AppStore.plist"
  "files/FreePrintStudio/Resources/Info.plist"
  "files/FreePrintStudio/Resources/PrivacyInfo.xcprivacy"
  "files/fastlane/Fastfile"
  "files/fastlane/metadata/en-US/name.txt"
  "files/docs/privacy-policy.html"
  "files/docs/support.html"
)

for entry in "${required_file_manifest_entries[@]}"; do
  require_manifest_entry "file-manifest.tsv" "$entry" "submission packet file manifest"
done

require_manifest_files_exist
require_no_local_path_leaks
require_no_forbidden_private_artifacts
require_no_private_key_material
require_no_symlinks

if [[ "$failures" -gt 0 ]]; then
  printf '\nApp Store submission packet validation failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'App Store submission packet validation passed.\n'
