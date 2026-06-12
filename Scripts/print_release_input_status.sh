#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

release_env_path="${RELEASE_ENV_PATH:-$ROOT_DIR/Config/release.env}"
manual_evidence_path="${MANUAL_RELEASE_VERIFICATION_PATH:-$ROOT_DIR/Config/manual-release-verification.env}"
strict=0
missing_count=0

usage() {
  cat <<'EOF'
Usage: Scripts/print_release_input_status.sh [--strict]

Prints a redacted App Store release input status summary. It does not print private values.

Options:
  --strict  exit nonzero when required private inputs or signing assets are missing
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      strict=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

trimmed_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_set() {
  local value
  value="$(trimmed_value "${1:-}")"
  [[ -n "$value" ]]
}

matches_format() {
  local value="$1"
  local pattern="$2"
  [[ "$value" =~ $pattern ]]
}

looks_like_placeholder() {
  local value
  local lower_value
  value="$(trimmed_value "${1:-}")"

  [[ -z "$value" ]] && return 1
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    YOURTEAMID|YOUR_FIRST_NAME|YOUR_LAST_NAME|+1-555-0100|review-contact@example.com|\
    apple-id@example.com|XXXXXXXXXX|00000000-0000-0000-0000-000000000000|\
    /absolute/path/to/AuthKey_XXXXXXXXXX.p8|/absolute/path/to/fastlane-api-key.json|\
    /absolute/path/to/FreePrintStudio.ipa|/secure/AuthKey_XXXXXXXXXX.p8|\
    123456789|"Your Team Name"|PROCESSED_BUILD_NUMBER|TODO|TBD|PLACEHOLDER)
      return 0
      ;;
  esac

  [[ "$value" == *"YOUR_"* ]] && return 0
  [[ "$value" == *"XXXXXXXXXX"* ]] && return 0
  [[ "$lower_value" == *"example.com"* ]] && return 0
  [[ "$lower_value" == *@example.* ]] && return 0
  [[ "$lower_value" == *"todo"* ]] && return 0
  [[ "$lower_value" == *"tbd"* ]] && return 0
  [[ "$lower_value" == *"placeholder"* ]] && return 0
  [[ "$value" == /absolute/path/* ]] && return 0

  return 1
}

mark_missing() {
  printf 'MISSING: %s\n' "$1"
  missing_count=$((missing_count + 1))
}

mark_ok() {
  printf 'OK: %s\n' "$1"
}

mark_optional() {
  printf 'OPTIONAL: %s\n' "$1"
}

status_count() {
  local label="$1"
  local ready="$2"
  local total="$3"
  if (( ready == total )); then
    mark_ok "$label: $ready/$total"
  else
    mark_missing "$label: $ready/$total"
  fi
}

relative_repo_path() {
  local path="$1"
  if [[ "$path" == "$ROOT_DIR/"* ]]; then
    printf '%s' "${path#"$ROOT_DIR/"}"
  else
    printf '%s' "$path"
  fi
}

file_is_ignored() {
  local path="$1"
  local relative_path
  if [[ "$path" != "$ROOT_DIR/"* ]]; then
    return 1
  fi
  relative_path="$(relative_repo_path "$path")"
  git check-ignore -q "$relative_path" 2>/dev/null
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

printf '== Release Input Status ==\n'
printf 'This redacted status intentionally does not print private values.\n'

printf '\n== Private Files ==\n'
if [[ -f "$release_env_path" ]]; then
  mark_ok "Config/release.env exists"
else
  mark_missing "Config/release.env is missing; run Scripts/bootstrap_release_inputs.sh"
fi
if file_is_ignored "$release_env_path"; then
  mark_ok "Config/release.env is git-ignored"
else
  mark_missing "Config/release.env is not git-ignored"
fi

if [[ -f "$manual_evidence_path" ]]; then
  mark_ok "Config/manual-release-verification.env exists"
else
  mark_missing "Config/manual-release-verification.env is missing; run Scripts/bootstrap_release_inputs.sh"
fi
if file_is_ignored "$manual_evidence_path"; then
  mark_ok "Config/manual-release-verification.env is git-ignored"
else
  mark_missing "Config/manual-release-verification.env is not git-ignored"
fi

set +e
source Scripts/load_release_env.sh >/tmp/freeprintstudio-release-input-status-env.log 2>&1
release_source_status="$?"
set -e
if [[ "$release_source_status" -ne 0 ]]; then
  mark_missing "Config/release.env is not a valid shell env file"
  sed 's/^/  /' /tmp/freeprintstudio-release-input-status-env.log
elif Scripts/validate_release_env.sh >/tmp/freeprintstudio-release-input-status-release-env.log 2>&1; then
  mark_ok "Release environment validation passes"
else
  mark_missing "Release environment validation fails"
  sed 's/^/  /' /tmp/freeprintstudio-release-input-status-release-env.log
fi

printf '\n== App Review Contact ==\n'
contact_ready=0
for name in \
  APP_REVIEW_CONTACT_FIRST_NAME \
  APP_REVIEW_CONTACT_LAST_NAME \
  APP_REVIEW_CONTACT_PHONE \
  APP_REVIEW_CONTACT_EMAIL
do
  if is_set "${!name:-}"; then
    contact_ready=$((contact_ready + 1))
  fi
done
status_count "App Review contact fields configured" "$contact_ready" 4
if (( contact_ready == 4 )); then
  if Scripts/validate_app_review_contact.sh >/tmp/freeprintstudio-release-input-status-contact.log 2>&1; then
    mark_ok "App Review contact format validation passes"
  else
    mark_missing "App Review contact format validation fails"
    sed 's/^/  /' /tmp/freeprintstudio-release-input-status-contact.log
  fi
fi

printf '\n== Signing Inputs ==\n'
project_team_id="$(setting_value DEVELOPMENT_TEAM)"
team_ready=0
if { is_set "${DEVELOPMENT_TEAM_ID:-}" && matches_format "$DEVELOPMENT_TEAM_ID" '^[A-Z0-9]{10}$'; } \
  || { is_set "$project_team_id" && matches_format "$project_team_id" '^[A-Z0-9]{10}$'; }; then
  team_ready=1
fi
status_count "DEVELOPMENT_TEAM_ID or Xcode DEVELOPMENT_TEAM configured" "$team_ready" 1

identity_log="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if grep -q "Apple Distribution" <<<"$identity_log"; then
  mark_ok "Apple Distribution signing identity is installed"
else
  mark_missing "Apple Distribution signing identity is missing"
fi

profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
if [[ -d "$profiles_dir" ]] \
  && find "$profiles_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print -quit 2>/dev/null | grep -q .; then
  mark_ok "Provisioning profile files are installed"
else
  mark_missing "Provisioning profile files are missing"
fi

printf '\n== App Store Connect Inputs ==\n'
asc_credentials_ready_for_validation=0
if is_set "${APP_STORE_CONNECT_API_KEY_JSON:-}"; then
  if [[ -f "${APP_STORE_CONNECT_API_KEY_JSON:-}" ]]; then
    mark_ok "APP_STORE_CONNECT_API_KEY_JSON is configured"
    asc_credentials_ready_for_validation=1
  else
    mark_missing "APP_STORE_CONNECT_API_KEY_JSON is set but the file is missing"
  fi
else
  asc_triplet_ready=0
  for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
    if is_set "${!name:-}"; then
      asc_triplet_ready=$((asc_triplet_ready + 1))
    fi
  done
  if (( asc_triplet_ready == 3 )) && [[ -f "${ASC_KEY_PATH:-}" ]]; then
    mark_ok "ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH are configured"
    asc_credentials_ready_for_validation=1
  else
    mark_missing "App Store Connect API credentials configured: $asc_triplet_ready/3"
  fi
fi

if (( asc_credentials_ready_for_validation == 1 )); then
  if Scripts/check_app_store_connect_credentials.sh >/tmp/freeprintstudio-release-input-status-asc.log 2>&1; then
    mark_ok "App Store Connect API credential validation passes"
  else
    mark_missing "App Store Connect API credential validation fails"
  fi
fi

if is_set "${FASTLANE_USER:-}"; then
  mark_ok "FASTLANE_USER is configured for App Privacy Details upload"
else
  mark_optional "FASTLANE_USER is not configured; App Privacy Details upload may need manual entry"
fi

printf '\n== Final Submission Guards ==\n'
if is_set "${APP_STORE_BUILD_NUMBER:-}"; then
  if looks_like_placeholder "${APP_STORE_BUILD_NUMBER:-}"; then
    mark_missing "APP_STORE_BUILD_NUMBER still uses a placeholder value; replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build before final App Review submission"
  else
    mark_ok "APP_STORE_BUILD_NUMBER is configured for final App Review submission"
  fi
else
  mark_missing "APP_STORE_BUILD_NUMBER is missing; set it to the processed App Store Connect build before final App Review submission"
fi

confirm_submit_for_review="$(trimmed_value "${CONFIRM_SUBMIT_FOR_REVIEW:-}")"
if [[ "$confirm_submit_for_review" == "1" ]]; then
  mark_ok "CONFIRM_SUBMIT_FOR_REVIEW is set to 1 for guarded final App Review submission"
else
  mark_missing "CONFIRM_SUBMIT_FOR_REVIEW is not set to 1; set only after final preflight passes"
fi

printf '\n== Manual Release Evidence ==\n'
manual_source_status=1
if [[ -f "$manual_evidence_path" ]]; then
  set +e
  set -a
  # shellcheck source=/dev/null
  source "$manual_evidence_path" >/tmp/freeprintstudio-release-input-status-manual.log 2>&1
  manual_source_status="$?"
  set +a
  set -e
  if [[ "$manual_source_status" -ne 0 ]]; then
    mark_missing "Manual release verification evidence is not a valid shell env file"
    sed 's/^/  /' /tmp/freeprintstudio-release-input-status-manual.log
  fi
fi

manual_ready=0
manual_validation_ran=0
manual_validation_passed=0
if [[ "$manual_source_status" -eq 0 ]]; then
  for name in \
    MANUAL_VERIFIER_NAME \
    MANUAL_REAL_IPHONE_MODEL \
    MANUAL_REAL_IPHONE_IOS_VERSION \
    MANUAL_REAL_IPHONE_TEST_DATE \
    MANUAL_AIRPRINT_TEST_DATE \
    MANUAL_AIRPRINT_PRINTER \
    MANUAL_AIRPRINT_RULER_TARGET_INCHES \
    MANUAL_AIRPRINT_RULER_MEASURED_INCHES \
    MANUAL_TESTFLIGHT_BUILD_NUMBER \
    MANUAL_TESTFLIGHT_DEVICE \
    MANUAL_TESTFLIGHT_TEST_DATE
  do
    if is_set "${!name:-}"; then
      manual_ready=$((manual_ready + 1))
    fi
  done
  for name in \
    MANUAL_REAL_IPHONE_PHOTOS_IMPORT \
    MANUAL_REAL_IPHONE_PDF_EXPORT \
    MANUAL_REAL_IPHONE_PRINT_SHEET \
    MANUAL_AIRPRINT_EXACT_SIZE \
    MANUAL_TESTFLIGHT_INSTALL \
    MANUAL_TESTFLIGHT_PRINT_WORKFLOW
  do
    lower_value="$(printf '%s' "${!name:-}" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower_value" == "pass" ]]; then
      manual_ready=$((manual_ready + 1))
    fi
  done

  if [[ -f "$manual_evidence_path" ]]; then
    manual_validation_ran=1
    if Scripts/validate_manual_release_verification.sh >/tmp/freeprintstudio-release-input-status-manual-validation.log 2>&1; then
      manual_validation_passed=1
    fi
  fi
fi
if (( manual_ready == 17 )); then
  if (( manual_validation_passed == 1 )); then
    mark_ok "Manual real-device, AirPrint, and TestFlight evidence ready: 17/17"
    mark_ok "Manual release evidence validation passes"
  elif (( manual_validation_ran == 1 )); then
    mark_missing "Manual release evidence validation fails"
  else
    mark_missing "Manual real-device, AirPrint, and TestFlight evidence ready: 17/17"
  fi
else
  status_count "Manual real-device, AirPrint, and TestFlight evidence ready" "$manual_ready" 17
fi

if is_set "${APP_STORE_BUILD_NUMBER:-}" && is_set "${MANUAL_TESTFLIGHT_BUILD_NUMBER:-}"; then
  if looks_like_placeholder "${APP_STORE_BUILD_NUMBER:-}" || looks_like_placeholder "${MANUAL_TESTFLIGHT_BUILD_NUMBER:-}"; then
    mark_missing "APP_STORE_BUILD_NUMBER or MANUAL_TESTFLIGHT_BUILD_NUMBER still uses a placeholder value"
  elif [[ "$APP_STORE_BUILD_NUMBER" == "$MANUAL_TESTFLIGHT_BUILD_NUMBER" ]]; then
    mark_ok "MANUAL_TESTFLIGHT_BUILD_NUMBER matches selected APP_STORE_BUILD_NUMBER"
  else
    mark_missing "MANUAL_TESTFLIGHT_BUILD_NUMBER does not match selected APP_STORE_BUILD_NUMBER"
  fi
fi

printf '\n== Next Commands ==\n'
selected_app_store_build="${APP_STORE_BUILD_NUMBER:-PROCESSED_BUILD_NUMBER}"
printf 'Scripts/bootstrap_release_inputs.sh\n'
printf 'Scripts/validate_release_env.sh\n'
printf 'APP_STORE_BUILD_NUMBER=%s Scripts/validate_manual_release_verification.sh\n' "$selected_app_store_build"
printf 'Scripts/check_app_store_readiness.sh\n'
printf 'Scripts/verify_release.sh testflight-dependencies-preflight\n'

printf '\nSummary: %d missing required release input item(s).\n' "$missing_count"
if (( strict == 1 && missing_count > 0 )); then
  exit 1
fi
