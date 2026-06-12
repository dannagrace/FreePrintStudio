#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PACKET_DIR="${FREEPRINTSTUDIO_SUBMISSION_PACKET_DIR:-build/AppStoreSubmissionPacket}"
READINESS_LOG="$PACKET_DIR/readiness.txt"
SCREENSHOT_MANIFEST="$PACKET_DIR/screenshots.tsv"
PDF_VALIDATION_MANIFEST_SOURCE="${PDF_VALIDATION_MANIFEST_PATH:-/tmp/freeprintstudio-pdf-export-validation.tsv}"
PDF_VALIDATION_MANIFEST="$PACKET_DIR/pdf-export-validation.tsv"
MANUAL_EVIDENCE_FORM="$PACKET_DIR/manual-release-evidence-form.md"
MANUAL_READINESS_REPORT="$PACKET_DIR/manual-release-readiness-report.md"
CONTACT_READINESS_REPORT="$PACKET_DIR/app-review-contact-readiness-report.md"
SIGNING_READINESS_REPORT="$PACKET_DIR/signing-readiness-report.md"
APP_STORE_CONNECT_READINESS_REPORT="$PACKET_DIR/app-store-connect-readiness-report.md"
APP_STORE_CONNECT_STATE_REPORT="$PACKET_DIR/app-store-connect-state-report.md"
APP_REVIEW_SUBMISSION_READINESS_REPORT="$PACKET_DIR/app-review-submission-readiness-report.md"
PUBLIC_PAGES_READINESS_REPORT="$PACKET_DIR/public-pages-readiness-report.md"
RELEASE_INPUT_STATUS="$PACKET_DIR/release-input-status.txt"
RELEASE_PROVENANCE="$PACKET_DIR/release-provenance.tsv"
FILE_MANIFEST="$PACKET_DIR/file-manifest.tsv"
SUMMARY_PATH="$PACKET_DIR/SUMMARY.md"
ACTION_ITEMS_PATH="$PACKET_DIR/ACTION_ITEMS.md"
EXTERNAL_READINESS_ACTIONS="$PACKET_DIR/external-readiness-actions.tsv"

expected_screenshots=(
  "iphone-main.jpg"
  "iphone-test-ruler.jpg"
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
  "AppStore/commercial-configuration.md"
  "AppStore/review-guideline-audit.md"
  "AppStore/release-inputs-worksheet.md"
  "AppStore/release-checklist.md"
  "Config/release.env.example"
  "Config/manual-release-verification.env.example"
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

copy_pdf_validation_manifest() {
  if [[ ! -s "$PDF_VALIDATION_MANIFEST_SOURCE" ]]; then
    fail "PDF validation manifest is missing: $PDF_VALIDATION_MANIFEST_SOURCE. Run Scripts/verify_release.sh pdf first."
    return
  fi

  if ! grep -q $'^test-ruler-stretch\ttestRuler\tstretch\tletter\tportrait\tinch\t6\t1\t' "$PDF_VALIDATION_MANIFEST_SOURCE"; then
    fail "PDF validation manifest does not include Test Ruler exact-size evidence: test-ruler-stretch"
    return
  fi

  awk -F '\t' 'BEGIN { OFS = "\t" } NR == 1 { print; next } { $9 = "[generated-pdf]"; print }' \
    "$PDF_VALIDATION_MANIFEST_SOURCE" >"$PDF_VALIDATION_MANIFEST"
}

write_manual_evidence_form() {
  Scripts/generate_manual_release_evidence_form.sh "$MANUAL_EVIDENCE_FORM" >/dev/null
}

write_manual_readiness_report() {
  Scripts/generate_manual_release_readiness_report.sh "$MANUAL_READINESS_REPORT" >/dev/null
}

write_contact_readiness_report() {
  Scripts/generate_app_review_contact_readiness_report.sh "$CONTACT_READINESS_REPORT" >/dev/null
}

write_signing_readiness_report() {
  Scripts/generate_signing_readiness_report.sh "$SIGNING_READINESS_REPORT" >/dev/null
}

write_app_store_connect_readiness_report() {
  Scripts/generate_app_store_connect_readiness_report.sh "$APP_STORE_CONNECT_READINESS_REPORT" >/dev/null
}

write_app_store_connect_state_report() {
  Scripts/generate_app_store_connect_state_report.sh "$APP_STORE_CONNECT_STATE_REPORT" >/dev/null
}

write_app_review_submission_readiness_report() {
  Scripts/generate_app_review_submission_readiness_report.sh "$APP_REVIEW_SUBMISSION_READINESS_REPORT" >/dev/null
}

write_public_pages_readiness_report() {
  Scripts/generate_public_pages_readiness_report.sh "$PUBLIC_PAGES_READINESS_REPORT" >/dev/null
}

write_release_input_status() {
  set +e
  Scripts/print_release_input_status.sh --strict >"$RELEASE_INPUT_STATUS" 2>&1
  set -e
}

redact_remote_url() {
  local value="$1"
  if [[ "$value" == /* || "$value" == file:* ]]; then
    printf '[local-remote]'
    return
  fi

  printf '%s' "$value" \
    | sed -E 's#(https?://)[^/@]+@#\1[redacted]@#; s#(https?://)[^/:]+:[^/@]+@#\1[redacted]@#'
}

write_release_provenance() {
  local commit
  local branch
  local remote_origin
  local dirty_count
  local git_status
  local github_run_url="not available"
  local github_ref="${GITHUB_REF_NAME:-${GITHUB_REF:-not available}}"
  local github_sha="${GITHUB_SHA:-not available}"

  commit="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
  branch="${GITHUB_REF_NAME:-$(git branch --show-current 2>/dev/null || true)}"
  if [[ -z "$branch" ]]; then
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
  fi
  remote_origin="$(redact_remote_url "$(git config --get remote.origin.url 2>/dev/null || printf 'unknown')")"
  dirty_count="$(git status --short 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [[ "$dirty_count" == "0" ]]; then
    git_status="clean"
  else
    git_status="dirty (${dirty_count} tracked/untracked item(s))"
  fi

  if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
    github_run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
  fi

  {
    printf 'key\tvalue\n'
    printf 'generated_at\t%s\n' "$generated_at"
    printf 'git_commit\t%s\n' "$commit"
    printf 'git_branch\t%s\n' "$branch"
    printf 'git_remote_origin\t%s\n' "$remote_origin"
    printf 'git_status\t%s\n' "$git_status"
    printf 'git_dirty_count\t%s\n' "$dirty_count"
    printf 'github_run_url\t%s\n' "$github_run_url"
    printf 'github_ref\t%s\n' "$github_ref"
    printf 'github_sha\t%s\n' "$github_sha"
  } >"$RELEASE_PROVENANCE"
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

write_action_items() {
  local blockers_path
  local warnings_path
  blockers_path="$(mktemp)"
  warnings_path="$(mktemp)"

  grep '^BLOCKED:' "$READINESS_LOG" >"$blockers_path" || true
  grep '^WARN:' "$READINESS_LOG" >"$warnings_path" || true

  cat >"$ACTION_ITEMS_PATH" <<EOF
# FreePrint Studio Release Action Items

- Generated At: $generated_at
- Readiness Exit Code: $readiness_status
- Readiness Blockers: $blocker_count
- Readiness Warnings: $warning_count

## Readiness Blockers

EOF

  if [[ -s "$blockers_path" ]]; then
    while IFS= read -r line; do
      printf -- '- %s\n' "$(redact_external_action_item "${line#BLOCKED: }")" >>"$ACTION_ITEMS_PATH"
    done <"$blockers_path"
  else
    printf -- '- None. The local readiness audit has no blockers.\n' >>"$ACTION_ITEMS_PATH"
  fi

  cat >>"$ACTION_ITEMS_PATH" <<EOF

## Readiness Warnings

EOF

  if [[ -s "$warnings_path" ]]; then
    while IFS= read -r line; do
      printf -- '- %s\n' "$(redact_external_action_item "${line#WARN: }")" >>"$ACTION_ITEMS_PATH"
    done <"$warnings_path"
  else
    printf -- '- None. The local readiness audit has no warnings.\n' >>"$ACTION_ITEMS_PATH"
  fi

  cat >>"$ACTION_ITEMS_PATH" <<'EOF'

## External Values To Provide

- `APP_REVIEW_CONTACT_FIRST_NAME`, `APP_REVIEW_CONTACT_LAST_NAME`, `APP_REVIEW_CONTACT_PHONE`, and `APP_REVIEW_CONTACT_EMAIL` in an untracked `Config/release.env` or shell environment.
- `DEVELOPMENT_TEAM_ID`, an installed `Apple Distribution` certificate, and an App Store Connect provisioning profile for `com.dannagrace.FreePrintStudio`.
- App Store Connect credentials through either `APP_STORE_CONNECT_API_KEY_JSON` or the `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH` triplet.
- `FASTLANE_USER` if uploading App Privacy Details through the Fastlane Apple ID flow.
- Manual commercial configuration in App Store Connect from `AppStore/commercial-configuration.md`.
- App Review self-audit evidence from `AppStore/review-guideline-audit.md`.
- Manual release verification evidence in untracked `Config/manual-release-verification.env` after real iPhone, AirPrint, and TestFlight checks.
- Follow `AppStore/release-inputs-worksheet.md` while filling private values; do not commit secrets or real contact details.

## Command Order

Replace `PROCESSED_BUILD_NUMBER` with the processed App Store Connect build number before running the selected-build commands below. The local release validators intentionally reject `PROCESSED_BUILD_NUMBER` so the placeholder cannot reach App Store Connect.

```sh
Scripts/verify_release.sh store-ready
Scripts/bootstrap_release_inputs.sh
Scripts/print_release_input_status.sh --strict
Scripts/verify_release.sh contact-report
Scripts/verify_release.sh manual-evidence-form
Scripts/verify_release.sh manual-report
Scripts/verify_release.sh signing-report
Scripts/verify_release.sh asc-report
Scripts/verify_release.sh asc-state-report
Scripts/verify_release.sh review-report
Scripts/verify_release.sh public-pages-report
Scripts/bootstrap_release_env.sh
Scripts/check_app_store_readiness.sh
Scripts/preflight_testflight_upload_dependencies.sh
Scripts/preflight_app_store_archive.sh
DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh
Scripts/preflight_testflight_upload.sh
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review
```

Keep `Config/release.env` and App Store Connect private keys out of git.
EOF

  rm -f "$blockers_path" "$warnings_path"
}

tsv_escape() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

redact_external_action_item() {
  local value="$1"
  local release_env_path="${RELEASE_ENV_PATH:-$ROOT_DIR/Config/release.env}"
  local manual_evidence_path="${MANUAL_RELEASE_VERIFICATION_PATH:-$ROOT_DIR/Config/manual-release-verification.env}"
  value="${value//$manual_evidence_path/[manual-evidence-env]}"
  value="${value//$release_env_path/[release-env]}"
  value="${value//$ROOT_DIR\//[repo]/}"
  value="${value//$ROOT_DIR/[repo]}"
  value="${value//$HOME\//[home]/}"
  value="${value//$HOME/[home]}"
  printf '%s' "$value"
}

redact_readiness_log() {
  local source_path="$1"
  local temp_path
  local line
  temp_path="$(mktemp)"
  while IFS= read -r line; do
    printf '%s\n' "$(redact_external_action_item "$line")"
  done <"$source_path" >"$temp_path"
  mv "$temp_path" "$source_path"
}

external_action_fields() {
  local item="$1"
  local category="General"
  local owner="Release owner"
  local next_action="Review readiness.txt and resolve this item before App Review submission."
  local validation_command="Scripts/check_app_store_readiness.sh"

  case "$item" in
    *APP_REVIEW_CONTACT*|*"App Review contact"*)
      category="App Review Contact"
      owner="Release owner"
      next_action="Fill App Review contact fields in untracked Config/release.env, then run Scripts/validate_app_review_contact.sh."
      validation_command="Scripts/validate_app_review_contact.sh"
      ;;
    *FASTLANE_USER*|*ASC_*|*"App Store Connect"*|*"Fastlane App Store Connect"*|*"API credentials"*)
      category="App Store Connect"
      owner="App Store Connect account holder"
      next_action="Configure App Store Connect credentials in untracked Config/release.env, then run Scripts/print_release_input_status.sh --strict and Scripts/check_app_store_readiness.sh."
      validation_command="Scripts/check_app_store_connect_credentials.sh"
      ;;
    *MANUAL_*|*"Manual "*|*"Real iPhone"*|*"AirPrint"*|*"TestFlight"*)
      category="Manual Verification"
      owner="QA/release owner"
      next_action="Record real iPhone, AirPrint, and TestFlight evidence in untracked Config/manual-release-verification.env, then run APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh."
      validation_command="APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh"
      ;;
    *"Developer Team"*|*"Apple Distribution"*|*"provisioning profile"*|*"provisioning profiles"*|*"signing identity"*|*"signing assets"*)
      category="Signing"
      owner="Apple Developer account holder"
      next_action="Install Apple Distribution signing assets and set DEVELOPMENT_TEAM_ID, then run Scripts/check_code_signing_assets.sh and Scripts/preflight_app_store_archive.sh."
      validation_command="Scripts/check_code_signing_assets.sh"
      ;;
  esac

  printf '%s\t%s\t%s\t%s\n' "$category" "$owner" "$next_action" "$validation_command"
}

external_action_field_for_item() {
  local item="$1"
  local field=""
  local parenthesized_field_pattern='\(([A-Z0-9_]+)(=[^)]*)?\)'

  if [[ "$item" =~ $parenthesized_field_pattern ]]; then
    field="${BASH_REMATCH[1]}"
  elif [[ "$item" =~ (APP_REVIEW_CONTACT_[A-Z_]+) ]]; then
    field="${BASH_REMATCH[1]}"
  elif [[ "$item" =~ (APP_STORE_CONNECT_API_KEY_JSON|ASC_[A-Z0-9_]+|FASTLANE_USER) ]]; then
    field="${BASH_REMATCH[1]}"
  elif [[ "$item" == *"Manual release verification evidence file"* ]]; then
    field="MANUAL_RELEASE_VERIFICATION_PATH"
  elif [[ "$item" == *"Developer Team"* ]]; then
    field="DEVELOPMENT_TEAM_ID"
  elif [[ "$item" == *"Apple Distribution"* || "$item" == *"signing identity"* ]]; then
    field="Apple Distribution certificate"
  elif [[ "$item" == *"provisioning profile"* || "$item" == *"provisioning profiles"* ]]; then
    field="App Store provisioning profile"
  elif [[ "$item" == *"API credentials"* || "$item" == *"App Store Connect API credentials"* ]]; then
    field="APP_STORE_CONNECT_API_KEY_JSON or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH"
  elif [[ "$item" == *"app record"* || "$item" == *"TestFlight status"* ]]; then
    field="App Store Connect app record/TestFlight status"
  fi

  printf '%s' "$field"
}

external_action_target_for_item() {
  local item="$1"
  local field="$2"
  local target="Release owner follow-up"

  case "$field" in
    MANUAL_*|MANUAL_RELEASE_VERIFICATION_PATH)
      target="Config/manual-release-verification.env"
      ;;
    APP_REVIEW_CONTACT_*|DEVELOPMENT_TEAM_ID|APP_STORE_BUILD_NUMBER|CONFIRM_SUBMIT_FOR_REVIEW|\
    APP_STORE_CONNECT_API_KEY_JSON|FASTLANE_USER|APP_STORE_CONNECT_API_KEY_JSON\ or\ ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH)
      target="Config/release.env"
      ;;
    Apple\ Distribution\ certificate)
      target="login keychain"
      ;;
    App\ Store\ provisioning\ profile)
      target="~/Library/MobileDevice/Provisioning Profiles"
      ;;
    App\ Store\ Connect\ app\ record/TestFlight\ status)
      target="App Store Connect"
      ;;
  esac

  case "$item" in
    *APP_REVIEW_CONTACT*|*"App Review contact"*)
      target="Config/release.env"
      ;;
    *ASC_*|*"App Store Connect API credentials"*|*"API credentials"*|*FASTLANE_USER*)
      target="Config/release.env"
      ;;
    *"app record"*|*"TestFlight status"*)
      target="App Store Connect"
      ;;
    *MANUAL_*|*"Manual "*|*"Real iPhone"*|*"AirPrint"*|*"TestFlight"*)
      target="Config/manual-release-verification.env"
      ;;
    *"Developer Team"*)
      target="Config/release.env or Xcode project settings"
      ;;
    *"Apple Distribution"*|*"signing identity"*)
      target="login keychain"
      ;;
    *"provisioning profile"*|*"provisioning profiles"*)
      target="~/Library/MobileDevice/Provisioning Profiles"
      ;;
  esac

  printf '%s' "$target"
}

write_external_readiness_actions() {
  local line
  local severity
  local item
  local redacted_item
  local category
  local owner
  local field
  local target
  local next_action
  local validation_command

  printf 'category	severity	owner	field	target	item	next_action	validation_command\n' >"$EXTERNAL_READINESS_ACTIONS"
  while IFS= read -r line; do
    case "$line" in
      BLOCKED:*)
        severity="blocker"
        item="${line#BLOCKED: }"
        ;;
      WARN:*)
        severity="warning"
        item="${line#WARN: }"
        ;;
      *)
        continue
        ;;
    esac

    redacted_item="$(redact_external_action_item "$item")"
    field="$(external_action_field_for_item "$item")"
    target="$(external_action_target_for_item "$item" "$field")"
    IFS=$'\t' read -r category owner next_action validation_command < <(external_action_fields "$item")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(tsv_escape "$category")" \
      "$(tsv_escape "$severity")" \
      "$(tsv_escape "$owner")" \
      "$(tsv_escape "$field")" \
      "$(tsv_escape "$target")" \
      "$(tsv_escape "$redacted_item")" \
      "$(tsv_escape "$next_action")" \
      "$(tsv_escape "$validation_command")" \
      >>"$EXTERNAL_READINESS_ACTIONS"
  done <"$READINESS_LOG"
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
copy_pdf_validation_manifest
write_manual_evidence_form
write_manual_readiness_report
write_contact_readiness_report
write_signing_readiness_report
write_app_store_connect_readiness_report
write_app_store_connect_state_report
write_app_review_submission_readiness_report
write_public_pages_readiness_report
write_release_input_status

set +e
Scripts/check_app_store_readiness.sh >"$READINESS_LOG" 2>&1
readiness_status="$?"
set -e
redact_readiness_log "$READINESS_LOG"

blocker_count="$(grep -c '^BLOCKED:' "$READINESS_LOG" || true)"
warning_count="$(grep -c '^WARN:' "$READINESS_LOG" || true)"
ok_count="$(grep -c '^OK:' "$READINESS_LOG" || true)"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
write_release_provenance
write_action_items
write_external_readiness_actions

cat >"$SUMMARY_PATH" <<EOF
# FreePrint Studio App Store Submission Packet

- Generated At: $generated_at
- Packet Directory: $PACKET_DIR
- Readiness Exit Code: $readiness_status
- Readiness OK Count: $ok_count
- Readiness Blockers: $blocker_count
- Readiness Warnings: $warning_count
- Release Provenance: \`release-provenance.tsv\`

## Included Materials

- App Store metadata drafts and Fastlane metadata.
- App Privacy, age rating, accessibility, and export compliance questionnaire drafts.
- Commercial configuration draft for pricing, availability, monetization, and release behavior.
- App Review guideline self-audit with evidence and open blockers.
- Release input worksheet for private Apple account, signing, and real-device evidence collection.
- Release environment template for private Apple signing, App Review contact, App Store Connect, and final submission guard inputs.
- Manual release evidence form for recording real iPhone, AirPrint, and TestFlight checks.
- Redacted App Review contact readiness report for required reviewer contact fields.
- Redacted manual release readiness report for real iPhone, AirPrint, TestFlight, and selected-build evidence.
- Redacted signing readiness report for Apple Developer Team, certificate, and provisioning profile state.
- Redacted App Store Connect readiness report for credential mode, upload guards, build selection, and account-dependent checks.
- Redacted App Store Connect state report for selected-build remote state check output and exit code.
- Redacted App Review submission readiness report for final metadata, policy, evidence, credential, and selected-build checks.
- Public pages readiness report for privacy policy and support URL source files, deployed HTTP status, and expected App Store review text.
- Redacted release input status with field-level missing private input tracking.
- Reviewed screenshots and Fastlane upload screenshots.
- PDF export validation manifest, including Test Ruler exact-size evidence.
- Public privacy and support page source files.
- Manual release verification evidence template.
- App icon, plist declarations, privacy manifest, Fastlane release files, and App Store export options.
- \`screenshots.tsv\` with screenshot dimensions and sha256 checksums.
- \`pdf-export-validation.tsv\` with PDF page, target, draw matrix, and sha256 evidence.
- \`Config/release.env.example\` with commented private release environment variables for local handoff.
- \`manual-release-evidence-form.md\` with the blank manual verification record and env-field mapping.
- \`app-review-contact-readiness-report.md\` with redacted reviewer contact status, blocker counts, and next actions.
- \`manual-release-readiness-report.md\` with redacted manual evidence status, blocker counts, and next actions.
- \`signing-readiness-report.md\` with redacted signing status, profile counts, and next actions.
- \`app-store-connect-readiness-report.md\` with redacted App Store Connect credential status, upload guard state, and next actions.
- \`app-store-connect-state-report.md\` with redacted selected-build App Store Connect state check output and exit code.
- \`app-review-submission-readiness-report.md\` with redacted final App Review submission gate status and next actions.
- \`public-pages-readiness-report.md\` with public privacy/support page status, URLs, expected text, and next actions.
- \`release-provenance.tsv\` with source commit, branch, sanitized remote, worktree status, and GitHub Actions run context when available.
- \`release-input-status.txt\` with redacted private input readiness and missing field checklist.
- \`external-readiness-actions.tsv\` with categorized external blockers, affected fields, target locations, validation commands, and warnings for release tracking.
- \`file-manifest.tsv\` with package file sizes and sha256 checksums.
- \`readiness.txt\` with the latest App Store readiness audit.
- \`ACTION_ITEMS.md\` with external account, signing, and App Store Connect follow-up work.

## Next Commands

Replace \`PROCESSED_BUILD_NUMBER\` with the processed App Store Connect build number before running the selected-build commands below. The local release validators intentionally reject \`PROCESSED_BUILD_NUMBER\` so the placeholder cannot reach App Store Connect.

\`\`\`sh
Scripts/verify_release.sh store-ready
Scripts/bootstrap_release_inputs.sh
Scripts/print_release_input_status.sh --strict
Scripts/verify_release.sh contact-report
Scripts/verify_release.sh manual-evidence-form
Scripts/verify_release.sh manual-report
Scripts/verify_release.sh signing-report
Scripts/verify_release.sh asc-report
Scripts/verify_release.sh asc-state-report
Scripts/verify_release.sh review-report
Scripts/verify_release.sh public-pages-report
Scripts/bootstrap_release_env.sh
Scripts/check_app_store_readiness.sh
Scripts/preflight_testflight_upload_dependencies.sh
Scripts/preflight_app_store_archive.sh
DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh
Scripts/preflight_testflight_upload.sh
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review
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
