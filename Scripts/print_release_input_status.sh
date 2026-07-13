#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

release_env_path="${RELEASE_ENV_PATH:-$ROOT_DIR/Config/release.env}"
manual_evidence_path="${MANUAL_RELEASE_VERIFICATION_PATH:-$ROOT_DIR/Config/manual-release-verification.env}"
DEFAULT_AIRPRINT_RULER_TARGET_INCHES="${MANUAL_AIRPRINT_RULER_TARGET_DEFAULT_INCHES:-6}"
strict=0
scope="all"
owner="all"
missing_count=0
missing_fields=()

usage() {
  cat <<'EOF'
Usage: Scripts/print_release_input_status.sh [--strict] [--scope SCOPE] [--owner OWNER]

Prints a redacted App Store release input status summary. It does not print private values.

Options:
  --strict  exit nonzero when required private inputs or signing assets are missing
  --scope   limit strict missing fields to a release phase (all, metadata-upload, app-privacy-upload, app-store-archive, testflight-upload, app-review-submission)
  --owner   limit strict missing fields to a handoff owner (all, release-owner, qa-release-owner, apple-developer-account-holder, app-store-connect-account-holder)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      strict=1
      ;;
    --scope)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --scope\n\n' >&2
        usage >&2
        exit 1
      fi
      scope="$2"
      shift
      ;;
    --owner)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --owner\n\n' >&2
        usage >&2
        exit 1
      fi
      owner="$2"
      shift
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

case "$scope" in
  all|metadata-upload|app-privacy-upload|app-store-archive|testflight-upload|app-review-submission)
    ;;
  *)
    printf 'Unknown --scope value: %s\n\n' "$scope" >&2
    usage >&2
    exit 1
    ;;
esac

case "$owner" in
  all|release-owner|qa-release-owner|apple-developer-account-holder|app-store-connect-account-holder)
    ;;
  *)
    printf 'Unknown --owner value: %s\n\n' "$owner" >&2
    usage >&2
    exit 1
    ;;
esac

phase_requires() {
  local section="$1"

  case "$scope" in
    all)
      return 0
      ;;
    metadata-upload)
      case "$section" in
        private-release-env|app-review-contact|app-store-connect)
          return 0
          ;;
      esac
      ;;
    app-store-archive)
      case "$section" in
        private-release-env|signing)
          return 0
          ;;
      esac
      ;;
	    app-review-submission)
	      case "$section" in
	        private-release-env|app-review-contact|app-store-connect|app-privacy-connect-confirmation|commercial-configuration-confirmation|final-submission|manual-release-evidence)
	          return 0
	          ;;
      esac
      ;;
    testflight-upload)
      case "$section" in
        private-release-env|app-store-connect)
          return 0
          ;;
      esac
      ;;
    app-privacy-upload)
      case "$section" in
        private-release-env|app-privacy-upload)
          return 0
          ;;
      esac
      ;;
  esac

  return 1
}

owner_requires() {
  local section="$1"

  case "$owner" in
    all)
      return 0
      ;;
    release-owner)
      case "$section" in
        private-release-env|app-review-contact|final-submission)
          return 0
          ;;
      esac
      ;;
    qa-release-owner)
      case "$section" in
        manual-release-evidence)
          return 0
          ;;
      esac
      ;;
    apple-developer-account-holder)
      case "$section" in
        private-release-env|signing)
          return 0
          ;;
      esac
      ;;
    app-store-connect-account-holder)
      case "$section" in
        private-release-env|app-store-connect|app-privacy-upload|app-privacy-connect-confirmation|commercial-configuration-confirmation)
          return 0
          ;;
      esac
      ;;
  esac

  return 1
}

scope_requires() {
  local section="$1"

  phase_requires "$section" && owner_requires "$section"
}

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

manual_evidence_permissions_ok() {
  local path="$1"

  python3 - "$path" <<'PY'
from pathlib import Path
import stat
import sys

path = Path(sys.argv[1]).expanduser()

try:
    mode = path.stat().st_mode
except Exception:
    print("Manual release verification evidence permissions could not be checked")
    raise SystemExit(1)

if stat.S_IMODE(mode) & 0o077:
    print("Manual release verification evidence permissions are too broad; run chmod 600 Config/manual-release-verification.env")
    raise SystemExit(1)
PY
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

record_missing_field() {
  local field="$1"
  local target="$2"
  local validation_command="$3"
  missing_fields+=("$field|$target|$validation_command")
}

print_missing_fields() {
  local entry
  local field
  local target
  local validation_command

  printf '\n== Missing Release Input Fields ==\n'
  if ((${#missing_fields[@]} == 0)); then
    printf 'None.\n'
    return
  fi

  for entry in "${missing_fields[@]}"; do
    field="${entry%%|*}"
    entry="${entry#*|}"
    target="${entry%%|*}"
    validation_command="${entry#*|}"
    printf 'MISSING_FIELD: %s | file: %s | validate: %s\n' "$field" "$target" "$validation_command"
  done
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

file_is_outside_repo() {
  local path="$1"
  [[ "$path" != "$ROOT_DIR/"* ]]
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

private_template_install_command="Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config"

printf '\n== Private Files ==\n'
release_env_exists=0
if [[ -f "$release_env_path" ]]; then
  release_env_exists=1
  mark_ok "Config/release.env exists"
else
  mark_missing "Config/release.env is missing; run $private_template_install_command"
  record_missing_field "RELEASE_ENV_PATH" "Config/release.env" "$private_template_install_command && Scripts/validate_release_env.sh"
fi
if file_is_ignored "$release_env_path"; then
  mark_ok "Config/release.env is git-ignored"
elif file_is_outside_repo "$release_env_path"; then
  mark_ok "Configured release.env path is outside this repository"
else
  mark_missing "Config/release.env is not git-ignored"
fi

if scope_requires "manual-release-evidence"; then
  if [[ -f "$manual_evidence_path" ]]; then
    mark_ok "Config/manual-release-verification.env exists"
  else
    mark_missing "Config/manual-release-verification.env is missing; run $private_template_install_command"
  fi
  if file_is_ignored "$manual_evidence_path"; then
    mark_ok "Config/manual-release-verification.env is git-ignored"
  elif file_is_outside_repo "$manual_evidence_path"; then
    mark_ok "Configured manual release verification path is outside this repository"
  else
    mark_missing "Config/manual-release-verification.env is not git-ignored"
  fi
else
  mark_optional "Config/manual-release-verification.env is deferred for this release input status scope"
fi

set +e
source Scripts/load_release_env.sh >/tmp/freeprintstudio-release-input-status-env.log 2>&1
release_source_status="$?"
set -e
if [[ "$release_source_status" -ne 0 ]]; then
  if grep -q 'Release environment permissions are too broad' /tmp/freeprintstudio-release-input-status-env.log; then
    mark_missing "Config/release.env permissions are too broad; run chmod 600 Config/release.env"
    record_missing_field "RELEASE_ENV_PATH permissions" "Config/release.env" "chmod 600 Config/release.env && Scripts/validate_release_env.sh"
  elif grep -q 'Release environment permissions could not be checked' /tmp/freeprintstudio-release-input-status-env.log; then
    mark_missing "Config/release.env permissions could not be checked"
    record_missing_field "RELEASE_ENV_PATH permissions" "Config/release.env" "chmod 600 Config/release.env && Scripts/validate_release_env.sh"
  else
    mark_missing "Config/release.env is not a valid shell env file"
    sed 's/^/  /' /tmp/freeprintstudio-release-input-status-env.log
  fi
elif [[ "$release_env_exists" -ne 1 ]]; then
  mark_missing "Release environment validation is blocked until Config/release.env exists"
elif Scripts/validate_release_env.sh >/tmp/freeprintstudio-release-input-status-release-env.log 2>&1; then
  mark_ok "Release environment validation passes"
else
  mark_missing "Release environment validation fails"
  sed 's/^/  /' /tmp/freeprintstudio-release-input-status-release-env.log
fi

printf '\n== App Review Contact ==\n'
if scope_requires "app-review-contact"; then
  contact_ready=0
  for name in \
    APP_REVIEW_CONTACT_FIRST_NAME \
    APP_REVIEW_CONTACT_LAST_NAME \
    APP_REVIEW_CONTACT_PHONE \
    APP_REVIEW_CONTACT_EMAIL
  do
    if is_set "${!name:-}"; then
      contact_ready=$((contact_ready + 1))
    else
      record_missing_field "$name" "Config/release.env" "Scripts/validate_app_review_contact.sh"
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
else
  mark_optional "App Review contact fields are deferred for this release input status scope"
fi

printf '\n== Signing Inputs ==\n'
if scope_requires "signing"; then
  project_team_id="$(setting_value DEVELOPMENT_TEAM)"
  team_ready=0
  if is_set "${DEVELOPMENT_TEAM_ID:-}"; then
    if matches_format "$DEVELOPMENT_TEAM_ID" '^[A-Z0-9]{10}$'; then
      team_ready=1
    fi
  elif is_set "$project_team_id" && matches_format "$project_team_id" '^[A-Z0-9]{10}$'; then
    team_ready=1
  fi
  status_count "DEVELOPMENT_TEAM_ID or Xcode DEVELOPMENT_TEAM configured" "$team_ready" 1
  if (( team_ready == 0 )); then
    record_missing_field "DEVELOPMENT_TEAM_ID" "Config/release.env or Xcode project settings" "Scripts/check_code_signing_assets.sh"
  fi

  identity_log="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if grep -q "Apple Distribution" <<<"$identity_log"; then
    mark_ok "Apple Distribution signing identity is installed"
  else
    mark_missing "Apple Distribution signing identity is missing"
    record_missing_field "Apple Distribution certificate" "login keychain" "Scripts/check_code_signing_assets.sh"
  fi

  provisioning_profile_ready=0
  for profiles_dir in \
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
    "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    if [[ -d "$profiles_dir" ]] \
      && find "$profiles_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print -quit 2>/dev/null | grep -q .; then
      provisioning_profile_ready=1
      break
    fi
  done

  if (( provisioning_profile_ready == 1 )); then
    mark_ok "Provisioning profile files are installed"
  else
    mark_missing "Provisioning profile files are missing"
    record_missing_field "App Store provisioning profile" "Xcode UserData or ~/Library/MobileDevice/Provisioning Profiles" "Scripts/check_code_signing_assets.sh"
  fi
else
  mark_optional "Signing inputs are deferred for this release input status scope"
fi

printf '\n== App Store Connect Inputs ==\n'
if scope_requires "app-store-connect"; then
  asc_credentials_ready_for_validation=0
  if is_set "${APP_STORE_CONNECT_API_KEY_JSON:-}"; then
    if [[ -f "${APP_STORE_CONNECT_API_KEY_JSON:-}" ]]; then
      mark_ok "APP_STORE_CONNECT_API_KEY_JSON is configured"
      asc_credentials_ready_for_validation=1
    else
      mark_missing "APP_STORE_CONNECT_API_KEY_JSON is set but the file is missing"
      record_missing_field "APP_STORE_CONNECT_API_KEY_JSON" "Config/release.env" "Scripts/check_app_store_connect_credentials.sh"
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
      record_missing_field "APP_STORE_CONNECT_API_KEY_JSON or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH" "Config/release.env" "Scripts/check_app_store_connect_credentials.sh"
    fi
  fi

  if (( asc_credentials_ready_for_validation == 1 )); then
    if Scripts/check_app_store_connect_credentials.sh >/tmp/freeprintstudio-release-input-status-asc.log 2>&1; then
      mark_ok "App Store Connect API credential validation passes"
    else
      mark_missing "App Store Connect API credential validation fails"
    fi
  fi
else
  mark_optional "App Store Connect API credentials are deferred for this release input status scope"
fi

if scope_requires "app-privacy-upload"; then
  if is_set "${FASTLANE_USER:-}"; then
    mark_ok "FASTLANE_USER is configured for App Privacy Details upload automation"
  else
    mark_missing "FASTLANE_USER is missing; set it to the Apple ID used for App Store Connect before App Privacy Details upload"
    record_missing_field "FASTLANE_USER" "Config/release.env" "FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh"
  fi

  confirm_upload_app_privacy="$(trimmed_value "${CONFIRM_UPLOAD_APP_PRIVACY:-}")"
  if [[ "$confirm_upload_app_privacy" == "1" ]]; then
    mark_ok "CONFIRM_UPLOAD_APP_PRIVACY is set after App Privacy Details review"
  else
    mark_missing "CONFIRM_UPLOAD_APP_PRIVACY is not set to 1; set only after reviewing AppStore/app_privacy_details.json against AppStore/app-privacy.md"
    record_missing_field "CONFIRM_UPLOAD_APP_PRIVACY" "Config/release.env" "FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh"
  fi
elif is_set "${FASTLANE_USER:-}"; then
  mark_ok "FASTLANE_USER is configured for App Privacy Details upload automation"
else
  mark_optional "FASTLANE_USER is not configured; manual App Privacy Details confirmation is allowed"
fi

if scope_requires "app-privacy-connect-confirmation"; then
  app_privacy_connect_confirmation="$(trimmed_value "${APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT:-}")"
  if [[ "$app_privacy_connect_confirmation" == "1" ]]; then
    mark_ok "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT is set after App Store Connect verification"
  elif is_set "$app_privacy_connect_confirmation"; then
    mark_missing "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT must be 1 after App Store Connect matches AppStore/app_privacy_details.json"
    record_missing_field "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT" "Config/release.env" "Scripts/validate_app_privacy_connect_entry.sh"
  else
    mark_missing "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT is missing; confirm App Privacy Details in App Store Connect before final App Review submission"
    record_missing_field "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT" "Config/release.env" "Scripts/validate_app_privacy_connect_entry.sh"
  fi
else
  mark_optional "App Privacy Details App Store Connect confirmation is deferred for this release input status scope"
fi

printf '\n== Commercial Configuration ==\n'
if scope_requires "commercial-configuration-confirmation"; then
  commercial_configuration_confirmation="$(trimmed_value "${APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT:-}")"
  if [[ "$commercial_configuration_confirmation" == "1" ]]; then
    mark_ok "APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT is set after App Store Connect commercial configuration verification"
  elif is_set "$commercial_configuration_confirmation"; then
    mark_missing "APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT must be 1 after App Store Connect matches AppStore/commercial-configuration.md"
    record_missing_field "APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT" "Config/release.env" "Scripts/validate_commercial_configuration_connect_entry.sh"
  else
    mark_missing "APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT is missing; confirm Pricing, Availability, monetization, release option, and phased release in App Store Connect before final App Review submission"
    record_missing_field "APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT" "Config/release.env" "Scripts/validate_commercial_configuration_connect_entry.sh"
  fi
else
  mark_optional "Commercial configuration App Store Connect confirmation is deferred for this release input status scope"
fi

printf '\n== Final Submission Guards ==\n'
if scope_requires "final-submission"; then
  if is_set "${APP_STORE_BUILD_NUMBER:-}"; then
    if looks_like_placeholder "${APP_STORE_BUILD_NUMBER:-}"; then
      mark_missing "APP_STORE_BUILD_NUMBER still uses a placeholder value; replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build before final App Review submission"
      record_missing_field "APP_STORE_BUILD_NUMBER" "Config/release.env" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh"
    else
      mark_ok "APP_STORE_BUILD_NUMBER is configured for final App Review submission"
    fi
  else
    mark_missing "APP_STORE_BUILD_NUMBER is missing; set it to the processed App Store Connect build before final App Review submission"
    record_missing_field "APP_STORE_BUILD_NUMBER" "Config/release.env" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh"
  fi

  confirm_submit_for_review="$(trimmed_value "${CONFIRM_SUBMIT_FOR_REVIEW:-}")"
  if [[ "$confirm_submit_for_review" == "1" ]]; then
    mark_ok "CONFIRM_SUBMIT_FOR_REVIEW is set to 1 for guarded final App Review submission"
  else
    mark_missing "CONFIRM_SUBMIT_FOR_REVIEW is not set to 1; set only after final preflight passes"
    record_missing_field "CONFIRM_SUBMIT_FOR_REVIEW" "Config/release.env" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh"
  fi
else
  mark_optional "Final submission guards are deferred for this release input status scope"
fi

printf '\n== Manual Release Evidence ==\n'
manual_source_status=1
if ! scope_requires "manual-release-evidence"; then
  mark_optional "Manual release evidence is deferred for this release input status scope"
elif [[ -f "$manual_evidence_path" ]]; then
  if manual_permission_message="$(manual_evidence_permissions_ok "$manual_evidence_path" 2>&1)"; then
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
  else
    mark_missing "$manual_permission_message"
    record_missing_field "MANUAL_RELEASE_VERIFICATION_PATH permissions" "Config/manual-release-verification.env" "chmod 600 Config/manual-release-verification.env && APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh"
  fi
else
  record_missing_field "MANUAL_RELEASE_VERIFICATION_PATH" "Config/manual-release-verification.env" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh"
fi

manual_ready=0
manual_validation_ran=0
manual_validation_passed=0
if scope_requires "manual-release-evidence" && [[ "$manual_source_status" -eq 0 ]]; then
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
    MANUAL_TESTFLIGHT_TEST_DATE \
    MANUAL_IPAD_TESTFLIGHT_DEVICE \
    MANUAL_IPAD_TESTFLIGHT_TEST_DATE
  do
    if is_set "${!name:-}"; then
      manual_ready=$((manual_ready + 1))
    elif [[ "$name" == "MANUAL_AIRPRINT_RULER_TARGET_INCHES" ]] && is_set "$DEFAULT_AIRPRINT_RULER_TARGET_INCHES"; then
      manual_ready=$((manual_ready + 1))
    else
      record_missing_field "$name" "Config/manual-release-verification.env" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh"
    fi
  done
  for name in \
    MANUAL_REAL_IPHONE_PHOTOS_IMPORT \
    MANUAL_REAL_IPHONE_PDF_EXPORT \
    MANUAL_REAL_IPHONE_PRINT_SHEET \
    MANUAL_AIRPRINT_EXACT_SIZE \
    MANUAL_TESTFLIGHT_INSTALL \
    MANUAL_TESTFLIGHT_PRINT_WORKFLOW \
    MANUAL_IPAD_TESTFLIGHT_INSTALL \
    MANUAL_IPAD_TESTFLIGHT_LAYOUT \
    MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW
  do
    lower_value="$(printf '%s' "${!name:-}" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower_value" == "pass" ]]; then
      manual_ready=$((manual_ready + 1))
    else
      record_missing_field "$name" "Config/manual-release-verification.env" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh"
    fi
  done

  if [[ -f "$manual_evidence_path" ]]; then
    manual_validation_ran=1
    if Scripts/validate_manual_release_verification.sh >/tmp/freeprintstudio-release-input-status-manual-validation.log 2>&1; then
      manual_validation_passed=1
    fi
  fi
fi
if scope_requires "manual-release-evidence"; then
  if (( manual_ready == 22 )); then
    if (( manual_validation_passed == 1 )); then
      mark_ok "Manual real-device, AirPrint, iPad, and TestFlight evidence ready: 22/22"
      mark_ok "Manual release evidence validation passes"
    elif (( manual_validation_ran == 1 )); then
      mark_missing "Manual release evidence validation fails"
    else
      mark_missing "Manual real-device, AirPrint, iPad, and TestFlight evidence ready: 22/22"
    fi
  else
    status_count "Manual real-device, AirPrint, iPad, and TestFlight evidence ready" "$manual_ready" 22
  fi

  if is_set "${APP_STORE_BUILD_NUMBER:-}" && is_set "${MANUAL_TESTFLIGHT_BUILD_NUMBER:-}"; then
    if looks_like_placeholder "${APP_STORE_BUILD_NUMBER:-}" || looks_like_placeholder "${MANUAL_TESTFLIGHT_BUILD_NUMBER:-}"; then
      mark_missing "APP_STORE_BUILD_NUMBER or MANUAL_TESTFLIGHT_BUILD_NUMBER still uses a placeholder value"
    elif [[ "$APP_STORE_BUILD_NUMBER" == "$MANUAL_TESTFLIGHT_BUILD_NUMBER" ]]; then
      mark_ok "MANUAL_TESTFLIGHT_BUILD_NUMBER matches selected APP_STORE_BUILD_NUMBER"
    else
      mark_missing "MANUAL_TESTFLIGHT_BUILD_NUMBER does not match selected APP_STORE_BUILD_NUMBER"
      record_missing_field "MANUAL_TESTFLIGHT_BUILD_NUMBER" "Config/manual-release-verification.env" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh"
    fi
  fi
fi

print_missing_fields

print_private_setup_commands() {
  printf '%s\n' "$private_template_install_command"
  printf 'Scripts/print_release_input_status.sh --strict'
  if [[ "$scope" != "all" ]]; then
    printf ' --scope %s' "$scope"
  fi
  if [[ "$owner" != "all" ]]; then
    printf ' --owner %s' "$owner"
  fi
  printf '\n'
  printf 'Scripts/validate_release_env.sh\n'
}

print_metadata_commands() {
  print_private_setup_commands
  printf 'Scripts/preflight_metadata_upload.sh\n'
  printf 'ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios metadata\n'
}

print_privacy_commands() {
  print_private_setup_commands
  printf 'FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh\n'
  printf 'FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details\n'
  printf 'Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.\n'
  printf 'APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh\n'
}

print_archive_commands() {
  print_private_setup_commands
  printf 'Scripts/preflight_app_store_archive.sh\n'
  printf 'DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh\n'
  printf 'Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands.\n'
}

print_testflight_commands() {
  print_private_setup_commands
  printf 'Scripts/verify_release.sh testflight-dependencies-preflight\n'
  printf 'Scripts/preflight_testflight_upload.sh\n'
  printf 'ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight\n'
}

print_review_submission_commands() {
  local selected_app_store_build="$1"
  print_private_setup_commands
  printf 'APP_STORE_BUILD_NUMBER=%s Scripts/validate_manual_release_verification.sh\n' "$selected_app_store_build"
  printf 'APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh\n'
  printf 'APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_commercial_configuration_connect_entry.sh\n'
  printf 'APP_STORE_BUILD_NUMBER=%s Scripts/run_fastlane.sh ios app_store_connect_state\n' "$selected_app_store_build"
  printf 'APP_STORE_BUILD_NUMBER=%s Scripts/preflight_app_review_submission.sh\n' "$selected_app_store_build"
  printf 'APP_STORE_BUILD_NUMBER=%s CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review\n' "$selected_app_store_build"
}

print_owner_commands() {
  local selected_app_store_build="$1"

  case "$owner" in
    release-owner)
      print_private_setup_commands
      printf 'Scripts/validate_app_review_contact.sh\n'
      printf 'APP_STORE_BUILD_NUMBER=%s Scripts/preflight_app_review_submission.sh\n' "$selected_app_store_build"
      printf 'APP_STORE_BUILD_NUMBER=%s CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review\n' "$selected_app_store_build"
      ;;
    qa-release-owner)
      print_private_setup_commands
      printf 'APP_STORE_BUILD_NUMBER=%s Scripts/validate_manual_release_verification.sh\n' "$selected_app_store_build"
      ;;
    apple-developer-account-holder)
      print_archive_commands
      ;;
    app-store-connect-account-holder)
      print_private_setup_commands
      printf 'Scripts/check_app_store_connect_credentials.sh\n'
      printf 'FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh\n'
      printf 'FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details\n'
      printf 'Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.\n'
      printf 'APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh\n'
      printf 'APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_commercial_configuration_connect_entry.sh\n'
      ;;
  esac
}

printf '\n== Next Commands ==\n'
selected_app_store_build="${APP_STORE_BUILD_NUMBER:-PROCESSED_BUILD_NUMBER}"
if [[ "$owner" != "all" ]]; then
  print_owner_commands "$selected_app_store_build"
else
  case "$scope" in
  all)
    print_private_setup_commands
    printf 'APP_STORE_BUILD_NUMBER=%s Scripts/validate_manual_release_verification.sh\n' "$selected_app_store_build"
    printf 'Scripts/check_app_store_readiness.sh\n'
    printf 'Scripts/preflight_metadata_upload.sh\n'
    printf 'ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios metadata\n'
    printf 'FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh\n'
    printf 'FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details\n'
    printf 'Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.\n'
    printf 'APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh\n'
    printf 'APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_commercial_configuration_connect_entry.sh\n'
    printf 'Scripts/verify_release.sh testflight-dependencies-preflight\n'
    printf 'Scripts/preflight_app_store_archive.sh\n'
    printf 'DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh\n'
    printf 'Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands.\n'
    printf 'Scripts/preflight_testflight_upload.sh\n'
    printf 'ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight\n'
    printf 'APP_STORE_BUILD_NUMBER=%s Scripts/run_fastlane.sh ios app_store_connect_state\n' "$selected_app_store_build"
    printf 'APP_STORE_BUILD_NUMBER=%s Scripts/preflight_app_review_submission.sh\n' "$selected_app_store_build"
    printf 'APP_STORE_BUILD_NUMBER=%s CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review\n' "$selected_app_store_build"
    ;;
  metadata-upload)
    print_metadata_commands
    ;;
  app-privacy-upload)
    print_privacy_commands
    ;;
  app-store-archive)
    print_archive_commands
    ;;
  testflight-upload)
    print_testflight_commands
    ;;
  app-review-submission)
    print_review_submission_commands "$selected_app_store_build"
    ;;
  esac
fi

missing_field_count="${#missing_fields[@]}"
printf '\nSummary: %d missing required release input check(s), %d missing field/action item(s).\n' \
  "$missing_count" "$missing_field_count"
if (( strict == 1 && (missing_count > 0 || missing_field_count > 0) )); then
  exit 1
fi
