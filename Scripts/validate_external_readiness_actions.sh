#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <readiness.txt> <external-readiness-actions.tsv>\n' "$0" >&2
  exit 2
fi

readiness_path="$1"
actions_path="$2"

if [[ ! -s "$readiness_path" ]]; then
  printf 'FAIL: readiness summary input is missing or empty: %s\n' "$readiness_path"
  exit 1
fi

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

summary_line="$(grep -E '^Summary: [0-9]+ blocker\(s\), [0-9]+ warning\(s\)\.$' "$readiness_path" | tail -n 1 || true)"
if [[ -z "$summary_line" ]]; then
  printf 'FAIL: readiness summary is missing or has an unexpected format in %s\n' "$readiness_path"
  exit 1
fi

expected_blockers="$(printf '%s\n' "$summary_line" | sed -E 's/^Summary: ([0-9]+) blocker\(s\), ([0-9]+) warning\(s\)\.$/\1/')"
expected_warnings="$(printf '%s\n' "$summary_line" | sed -E 's/^Summary: ([0-9]+) blocker\(s\), ([0-9]+) warning\(s\)\.$/\2/')"

actual_blockers="$(awk -F '\t' 'NR > 1 && $2 == "blocker" { count += 1 } END { print count + 0 }' "$actions_path")"
actual_warnings="$(awk -F '\t' 'NR > 1 && $2 == "warning" { count += 1 } END { print count + 0 }' "$actions_path")"

failures=0
expected_header=$'category\tseverity\towner\tfield\ttarget\titem\tnext_action\tvalidation_command'
actual_header="$(head -n 1 "$actions_path")"

expected_target_for_field() {
  local field="$1"
  case "$field" in
    APP_REVIEW_CONTACT_*|APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT|APP_STORE_CONNECT_API_KEY_JSON|\
    APP_STORE_CONNECT_API_KEY_JSON\ or\ ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH|ASC_*|FASTLANE_USER|\
    APP_STORE_BUILD_NUMBER|CONFIRM_SUBMIT_FOR_REVIEW)
      printf 'Config/release.env'
      ;;
    MANUAL_*|manual-release-verification.env\ file)
      printf 'Config/manual-release-verification.env'
      ;;
    DEVELOPMENT_TEAM_ID)
      printf 'Config/release.env or Xcode project settings'
      ;;
    Apple\ Distribution\ certificate)
      printf 'login keychain'
      ;;
    App\ Store\ provisioning\ profile)
      printf '~/Library/MobileDevice/Provisioning Profiles'
      ;;
    App\ Store\ Connect\ app\ record/TestFlight\ status)
      printf 'App Store Connect'
      ;;
    GitHub\ Pages\ build_type)
      printf 'GitHub repository Pages settings'
      ;;
  esac
}

expected_category_for_field() {
  local field="$1"
  case "$field" in
    APP_REVIEW_CONTACT_*)
      printf 'App Review Contact'
      ;;
    MANUAL_*|manual-release-verification.env\ file)
      printf 'Manual Verification'
      ;;
    DEVELOPMENT_TEAM_ID|Apple\ Distribution\ certificate|App\ Store\ provisioning\ profile)
      printf 'Signing'
      ;;
    APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT)
      printf 'App Privacy'
      ;;
    APP_STORE_CONNECT_API_KEY_JSON|APP_STORE_CONNECT_API_KEY_JSON\ or\ ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH|ASC_*|\
    App\ Store\ Connect\ app\ record/TestFlight\ status)
      printf 'App Store Connect'
      ;;
    FASTLANE_USER)
      printf 'App Privacy Upload'
      ;;
    GitHub\ Pages\ build_type)
      printf 'GitHub Pages Source'
      ;;
    APP_STORE_BUILD_NUMBER|CONFIRM_SUBMIT_FOR_REVIEW)
      printf 'App Review Submission'
      ;;
  esac
}

expected_owner_for_field() {
  local field="$1"
  case "$field" in
    APP_REVIEW_CONTACT_*|APP_STORE_BUILD_NUMBER|CONFIRM_SUBMIT_FOR_REVIEW)
      printf 'Release owner'
      ;;
    MANUAL_*|manual-release-verification.env\ file)
      printf 'QA/release owner'
      ;;
    DEVELOPMENT_TEAM_ID|Apple\ Distribution\ certificate|App\ Store\ provisioning\ profile)
      printf 'Apple Developer account holder'
      ;;
    APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT|APP_STORE_CONNECT_API_KEY_JSON|\
    APP_STORE_CONNECT_API_KEY_JSON\ or\ ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH|ASC_*|FASTLANE_USER|\
    App\ Store\ Connect\ app\ record/TestFlight\ status)
      printf 'App Store Connect account holder'
      ;;
    GitHub\ Pages\ build_type)
      printf 'Repository administrator'
      ;;
  esac
}

expected_validation_command_for_field() {
  local field="$1"
  case "$field" in
    APP_REVIEW_CONTACT_*)
      printf 'Scripts/validate_app_review_contact.sh'
      ;;
    MANUAL_*|manual-release-verification.env\ file)
      printf 'APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh'
      ;;
    DEVELOPMENT_TEAM_ID|Apple\ Distribution\ certificate|App\ Store\ provisioning\ profile)
      printf 'Scripts/check_code_signing_assets.sh'
      ;;
    APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT)
      printf 'Scripts/validate_app_privacy_connect_entry.sh'
      ;;
    APP_STORE_CONNECT_API_KEY_JSON|APP_STORE_CONNECT_API_KEY_JSON\ or\ ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH|ASC_*)
      printf 'Scripts/check_app_store_connect_credentials.sh'
      ;;
    FASTLANE_USER)
      printf 'Scripts/preflight_app_privacy_upload.sh'
      ;;
    App\ Store\ Connect\ app\ record/TestFlight\ status)
      printf 'APP_STORE_CONNECT_SKIP_BUILD_CHECK=1 Scripts/check_app_store_connect_state.sh'
      ;;
    GitHub\ Pages\ build_type)
      printf 'Scripts/check_github_pages_source.sh'
      ;;
    APP_STORE_BUILD_NUMBER|CONFIRM_SUBMIT_FOR_REVIEW)
      printf 'Scripts/preflight_app_review_submission.sh'
      ;;
  esac
}

check_required_column() {
  local row_number="$1"
  local column_name="$2"
  local value="$3"

  if [[ -z "$value" ]]; then
    printf 'FAIL: External readiness action row %s missing %s\n' "$row_number" "$column_name"
    failures=$((failures + 1))
  fi
}

if [[ "$actual_blockers" != "$expected_blockers" ]]; then
  printf 'FAIL: External readiness action count mismatch for blocker (readiness Summary: %s; external-readiness-actions.tsv: %s)\n' \
    "$expected_blockers" "$actual_blockers"
  failures=$((failures + 1))
fi

if [[ "$actual_warnings" != "$expected_warnings" ]]; then
  printf 'FAIL: External readiness action count mismatch for warning (readiness Summary: %s; external-readiness-actions.tsv: %s)\n' \
    "$expected_warnings" "$actual_warnings"
  failures=$((failures + 1))
fi

if [[ "$actual_header" != "$expected_header" ]]; then
  printf 'FAIL: external-readiness-actions.tsv header mismatch\n'
  failures=$((failures + 1))
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
expected_pairs="$temp_dir/expected.tsv"
actual_pairs="$temp_dir/actual.tsv"

awk '
  /^BLOCKED: / {
    item = $0
    sub(/^BLOCKED: /, "", item)
    print "blocker\t" item
  }
  /^WARN: / {
    item = $0
    sub(/^WARN: /, "", item)
    print "warning\t" item
  }
' "$readiness_path" | LC_ALL=C sort -u >"$expected_pairs"

awk -F '\t' '
  NR > 1 && ($2 == "blocker" || $2 == "warning") {
    print $2 "\t" $6
  }
' "$actions_path" | LC_ALL=C sort -u >"$actual_pairs"

while IFS=$'\t' read -r severity item; do
  [[ -z "${severity:-}" ]] && continue
  printf 'FAIL: Missing external readiness action for %s: %s\n' "$severity" "$item"
  failures=$((failures + 1))
done < <(comm -23 "$expected_pairs" "$actual_pairs")

while IFS=$'\t' read -r severity item; do
  [[ -z "${severity:-}" ]] && continue
  printf 'FAIL: Unexpected external readiness action for %s: %s\n' "$severity" "$item"
  failures=$((failures + 1))
done < <(comm -13 "$expected_pairs" "$actual_pairs")

row_number=1
while IFS=$'\t' read -r category severity owner field target item next_action validation_command extra; do
  row_number=$((row_number + 1))
  if [[ -z "${category}${severity}${owner}${field}${target}${item}${next_action}${validation_command}${extra:-}" ]]; then
    continue
  fi

  check_required_column "$row_number" "category" "$category"
  check_required_column "$row_number" "severity" "$severity"
  check_required_column "$row_number" "owner" "$owner"
  check_required_column "$row_number" "field" "$field"
  check_required_column "$row_number" "target" "$target"
  check_required_column "$row_number" "item" "$item"
  check_required_column "$row_number" "next_action" "$next_action"
  check_required_column "$row_number" "validation_command" "$validation_command"

  if [[ "$severity" != "blocker" && "$severity" != "warning" ]]; then
    printf 'FAIL: External readiness action row %s has invalid severity: %s\n' "$row_number" "$severity"
    failures=$((failures + 1))
  fi

  if [[ -n "${extra:-}" ]]; then
    printf 'FAIL: External readiness action row %s has extra TSV columns\n' "$row_number"
    failures=$((failures + 1))
  fi

  expected_target="$(expected_target_for_field "$field")"
  if [[ -n "$expected_target" && "$target" != "$expected_target" ]]; then
    printf 'FAIL: External readiness action target mismatch for %s (expected %s; got %s)\n' \
      "$field" "$expected_target" "$target"
    failures=$((failures + 1))
  fi

  expected_category="$(expected_category_for_field "$field")"
  if [[ -n "$expected_category" && "$category" != "$expected_category" ]]; then
    printf 'FAIL: External readiness action category mismatch for %s (expected %s; got %s)\n' \
      "$field" "$expected_category" "$category"
    failures=$((failures + 1))
  fi

  expected_owner="$(expected_owner_for_field "$field")"
  if [[ -n "$expected_owner" && "$owner" != "$expected_owner" ]]; then
    printf 'FAIL: External readiness action owner mismatch for %s (expected %s; got %s)\n' \
      "$field" "$expected_owner" "$owner"
    failures=$((failures + 1))
  fi

  expected_validation_command="$(expected_validation_command_for_field "$field")"
  if [[ -n "$expected_validation_command" && "$validation_command" != "$expected_validation_command" ]]; then
    printf 'FAIL: External readiness action validation command mismatch for %s (expected %s; got %s)\n' \
      "$field" "$expected_validation_command" "$validation_command"
    failures=$((failures + 1))
  fi
done < <(tail -n +2 "$actions_path")

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'External readiness actions match readiness summary.\n'
