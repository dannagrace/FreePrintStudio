#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PACKET_DIR="${FREEPRINTSTUDIO_SUBMISSION_PACKET_DIR:-build/AppStoreSubmissionPacket}"
READINESS_LOG="$PACKET_DIR/readiness.txt"
SCREENSHOT_MANIFEST="$PACKET_DIR/screenshots.tsv"
FILE_MANIFEST="$PACKET_DIR/file-manifest.tsv"
SUMMARY_PATH="$PACKET_DIR/SUMMARY.md"

expected_screenshots=(
  "iphone-main.jpg"
  "iphone-fit.jpg"
  "iphone-fill.jpg"
  "iphone-stretch.jpg"
  "iphone-metric-landscape.jpg"
  "ipad-main.jpg"
)

required_files=(
  "AppStore/metadata.md"
  "AppStore/app-privacy.md"
  "AppStore/app_privacy_details.json"
  "AppStore/age-rating.md"
  "AppStore/accessibility-labels.md"
  "AppStore/export-compliance.md"
  "AppStore/release-checklist.md"
  "FreePrintStudio/Resources/Info.plist"
  "FreePrintStudio/Resources/PrivacyInfo.xcprivacy"
  "FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
  "Config/ExportOptions-AppStore.plist"
  "fastlane/Deliverfile"
  "fastlane/Fastfile"
  "fastlane/metadata/en-US/name.txt"
  "fastlane/metadata/en-US/subtitle.txt"
  "fastlane/metadata/en-US/promotional_text.txt"
  "fastlane/metadata/en-US/description.txt"
  "fastlane/metadata/en-US/keywords.txt"
  "fastlane/metadata/en-US/release_notes.txt"
  "fastlane/metadata/en-US/privacy_url.txt"
  "fastlane/metadata/en-US/support_url.txt"
  "fastlane/metadata/en-US/copyright.txt"
  "fastlane/metadata/review_information/notes.txt"
  "docs/privacy-policy.html"
  "docs/support.html"
)

required_dirs=(
  "AppStore/Screenshots"
  "fastlane/screenshots/en-US"
)

failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

sha256_for_file() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

copy_required_file() {
  local source_path="$1"
  local target_path="$PACKET_DIR/files/$source_path"
  if [[ ! -s "$source_path" ]]; then
    fail "Required submission file is missing or empty: $source_path"
    return
  fi
  mkdir -p "$(dirname "$target_path")"
  cp "$source_path" "$target_path"
}

copy_required_dir() {
  local source_dir="$1"
  local target_dir="$PACKET_DIR/files/$source_dir"
  if [[ ! -d "$source_dir" ]]; then
    fail "Required submission directory is missing: $source_dir"
    return
  fi
  mkdir -p "$(dirname "$target_dir")"
  cp -R "$source_dir" "$target_dir"
}

write_screenshot_manifest() {
  local path
  local width
  local height
  local has_alpha

  printf 'path\twidth\theight\thasAlpha\tsha256\n' >"$SCREENSHOT_MANIFEST"
  for screenshot in "${expected_screenshots[@]}"; do
    for base_dir in "AppStore/Screenshots" "fastlane/screenshots/en-US"; do
      path="$base_dir/$screenshot"
      if [[ ! -s "$path" ]]; then
        fail "Required screenshot is missing or empty: $path"
        continue
      fi
      width="$(sips -g pixelWidth "$path" 2>/dev/null | awk -F': ' '/pixelWidth/ { print $2 }')"
      height="$(sips -g pixelHeight "$path" 2>/dev/null | awk -F': ' '/pixelHeight/ { print $2 }')"
      has_alpha="$(sips -g hasAlpha "$path" 2>/dev/null | awk -F': ' '/hasAlpha/ { print $2 }')"
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$path" "$width" "$height" "${has_alpha:-unknown}" "$(sha256_for_file "$path")" \
        >>"$SCREENSHOT_MANIFEST"
    done
  done
}

write_file_manifest() {
  local file_path
  local relative_path
  local byte_count

  printf 'path\tbytes\tsha256\n' >"$FILE_MANIFEST"
  while IFS= read -r file_path; do
    relative_path="${file_path#"$PACKET_DIR/"}"
    [[ "$relative_path" == "file-manifest.tsv" ]] && continue
    byte_count="$(wc -c <"$file_path" | tr -d '[:space:]')"
    printf '%s\t%s\t%s\n' "$relative_path" "$byte_count" "$(sha256_for_file "$file_path")" >>"$FILE_MANIFEST"
  done < <(find "$PACKET_DIR" -type f | sort)
}

rm -rf "$PACKET_DIR"
mkdir -p "$PACKET_DIR/files"

for path in "${required_files[@]}"; do
  copy_required_file "$path"
done

for path in "${required_dirs[@]}"; do
  copy_required_dir "$path"
done

write_screenshot_manifest

set +e
Scripts/check_app_store_readiness.sh >"$READINESS_LOG" 2>&1
readiness_status="$?"
set -e

blocker_count="$(grep -c '^BLOCKED:' "$READINESS_LOG" || true)"
warning_count="$(grep -c '^WARN:' "$READINESS_LOG" || true)"
ok_count="$(grep -c '^OK:' "$READINESS_LOG" || true)"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

cat >"$SUMMARY_PATH" <<EOF
# FreePrint Studio App Store Submission Packet

- Generated At: $generated_at
- Packet Directory: $PACKET_DIR
- Readiness Exit Code: $readiness_status
- Readiness OK Count: $ok_count
- Readiness Blockers: $blocker_count
- Readiness Warnings: $warning_count

## Included Materials

- App Store metadata drafts and Fastlane metadata.
- App Privacy, age rating, accessibility, and export compliance questionnaire drafts.
- Reviewed screenshots and Fastlane upload screenshots.
- Public privacy and support page source files.
- App icon, plist declarations, privacy manifest, Fastlane release files, and App Store export options.
- \`screenshots.tsv\` with screenshot dimensions and sha256 checksums.
- \`file-manifest.tsv\` with package file sizes and sha256 checksums.
- \`readiness.txt\` with the latest App Store readiness audit.

## Next Commands

\`\`\`sh
Scripts/check_app_store_readiness.sh
DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight
APP_STORE_BUILD_NUMBER=1 Scripts/run_fastlane.sh ios app_store_connect_state
APP_STORE_BUILD_NUMBER=1 CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review
\`\`\`

The readiness audit may contain blockers until Apple Developer signing assets, App Store Connect credentials, and the processed build are available.
EOF

write_file_manifest

if (( failures > 0 )); then
  printf '\nSubmission packet generation failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'App Store submission packet prepared: %s\n' "$PACKET_DIR"
printf 'Readiness blockers: %s; warnings: %s\n' "$blocker_count" "$warning_count"
