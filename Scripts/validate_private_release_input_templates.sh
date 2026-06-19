#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <private-release-input-templates-dir>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
template_dir="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

STANDARD_RELEASE_ENV_NAMES="DEVELOPMENT_TEAM_ID ALLOW_PROVISIONING_UPDATES APP_STORE_CONNECT_API_KEY_JSON ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH APP_REVIEW_CONTACT_FIRST_NAME APP_REVIEW_CONTACT_LAST_NAME APP_REVIEW_CONTACT_PHONE APP_REVIEW_CONTACT_EMAIL FASTLANE_USER FASTLANE_ITC_TEAM_ID FASTLANE_ITC_TEAM_NAME CONFIRM_UPLOAD_APP_PRIVACY APP_PRIVACY_SKIP_PUBLISH APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT IPA_PATH TESTFLIGHT_CHANGELOG APP_STORE_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW"

STANDARD_MANUAL_ENV_NAMES="MANUAL_VERIFIER_NAME MANUAL_REAL_IPHONE_MODEL MANUAL_REAL_IPHONE_IOS_VERSION MANUAL_REAL_IPHONE_TEST_DATE MANUAL_REAL_IPHONE_PHOTOS_IMPORT MANUAL_REAL_IPHONE_PDF_EXPORT MANUAL_REAL_IPHONE_PRINT_SHEET MANUAL_AIRPRINT_TEST_DATE MANUAL_AIRPRINT_PRINTER MANUAL_AIRPRINT_EXACT_SIZE MANUAL_AIRPRINT_RULER_TARGET_INCHES MANUAL_AIRPRINT_RULER_MEASURED_INCHES MANUAL_TESTFLIGHT_BUILD_NUMBER MANUAL_TESTFLIGHT_DEVICE MANUAL_TESTFLIGHT_TEST_DATE MANUAL_TESTFLIGHT_INSTALL MANUAL_TESTFLIGHT_PRINT_WORKFLOW MANUAL_IPAD_TESTFLIGHT_DEVICE MANUAL_IPAD_TESTFLIGHT_TEST_DATE MANUAL_IPAD_TESTFLIGHT_INSTALL MANUAL_IPAD_TESTFLIGHT_LAYOUT MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

require_file() {
  local path="$1"
  local description="$2"
  if [[ ! -s "$path" ]]; then
    fail "$description is missing or empty: $path"
  fi
}

require_contains() {
  local path="$1"
  local pattern="$2"
  local description="$3"
  if [[ ! -f "$path" ]]; then
    fail "$description is missing because file is missing: $path"
    return
  fi
  if ! grep -qF "$pattern" "$path"; then
    fail "$description is missing from $path"
  fi
}

require_not_contains() {
  local path="$1"
  local pattern="$2"
  local description="$3"
  if [[ ! -f "$path" ]]; then
    fail "$description could not be checked because file is missing: $path"
    return
  fi
  if grep -qF "$pattern" "$path"; then
    fail "$description is present in $path"
  fi
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

expected_assignments="$temp_dir/expected-assignments.tsv"
expected_counts="$temp_dir/expected-counts.tsv"

awk -F '\t' \
  -v standard_release_env_names="$STANDARD_RELEASE_ENV_NAMES" \
  -v standard_manual_env_names="$STANDARD_MANUAL_ENV_NAMES" '
  function fail(message) {
    print "FAIL: " message >"/dev/stderr"
    exit 1
  }

  function add_assignment(template_name, env_name) {
    if (env_name ~ /^[A-Z0-9_]+$/ && !(template_name SUBSEP env_name in seen)) {
      seen[template_name, env_name] = 1
      counts[template_name] += 1
      if (env_name == "MANUAL_AIRPRINT_RULER_TARGET_INCHES") {
        printf "%s\t%s\t%s\n", template_name, env_name, "MANUAL_AIRPRINT_RULER_TARGET_INCHES=\"6\""
      } else {
        printf "%s\t%s\t%s\n", template_name, env_name, env_name "=\"\""
      }
    }
  }

  function add_manual_assignment(env_name) {
    if (env_name == "MANUAL_AIRPRINT_RULER_MEASURED_INCHES" && !("manual-release-verification.env" SUBSEP "MANUAL_AIRPRINT_RULER_TARGET_INCHES" in seen)) {
      add_assignment("manual-release-verification.env", "MANUAL_AIRPRINT_RULER_TARGET_INCHES")
    }
    add_assignment("manual-release-verification.env", env_name)
  }

  function add_field_assignments(field_name, target,   parts, part_count, part_index, candidate) {
    if (field_name ~ /^[A-Z0-9_]+$/) {
      if (target ~ /^Config\/release\.env/) {
        add_assignment("release.env", field_name)
      } else if (target == "Config/manual-release-verification.env") {
        add_manual_assignment(field_name)
      }
      return
    }

    if (field_name ~ / or / || field_name ~ /\//) {
      part_count = split(field_name, parts, / or |\/+/)
      for (part_index = 1; part_index <= part_count; part_index += 1) {
        candidate = parts[part_index]
        gsub(/^ +| +$/, "", candidate)
        if (target ~ /^Config\/release\.env/) {
          add_assignment("release.env", candidate)
        } else if (target == "Config/manual-release-verification.env") {
          add_manual_assignment(candidate)
        }
      }
    }
  }

  function is_manual_file_setup(field_name, target, item) {
    return target == "Config/manual-release-verification.env" && \
      (field_name == "manual-release-verification.env file" || \
       field_name == "MANUAL_RELEASE_VERIFICATION_PATH" || \
       item ~ /Manual release verification evidence file/)
  }

  function add_standard_assignments(names, template_name,   parts, part_count, part_index, candidate) {
    part_count = split(names, parts, /[[:space:]]+/)
    for (part_index = 1; part_index <= part_count; part_index += 1) {
      candidate = parts[part_index]
      gsub(/^ +| +$/, "", candidate)
      if (candidate == "") {
        continue
      }
      if (template_name == "release.env") {
        add_assignment("release.env", candidate)
      } else if (template_name == "manual-release-verification.env") {
        add_manual_assignment(candidate)
      }
    }
  }

  BEGIN {
    add_standard_assignments(standard_release_env_names, "release.env")
    add_standard_assignments(standard_manual_env_names, "manual-release-verification.env")
  }

  NR == 1 {
    for (i = 1; i <= NF; i += 1) {
      columns[$i] = i
    }
    required[1] = "field"
    required[2] = "target"
    required[3] = "item"
    for (i = 1; i <= 3; i += 1) {
      if (!(required[i] in columns)) {
        fail("external readiness actions file is missing required column: " required[i])
      }
    }
    next
  }

  $1 != "" {
    total += 1
    field_name = $(columns["field"])
    target = $(columns["target"])
    item = $(columns["item"])
    if (is_manual_file_setup(field_name, target, item)) {
      next
    }
    add_field_assignments(field_name, target)
  }

  END {
    if (total == 0) {
      fail("external readiness actions file has no action rows")
    }
    printf "release.env\t%d\n", counts["release.env"] + 0 >"/dev/stderr"
    printf "manual-release-verification.env\t%d\n", counts["manual-release-verification.env"] + 0 >"/dev/stderr"
  }
' "$actions_path" >"$expected_assignments" 2>"$expected_counts" || {
  cat "$expected_counts" 2>/dev/null || true
  exit 1
}

index_path="$template_dir/index.md"
release_env_path="$template_dir/release.env"
manual_env_path="$template_dir/manual-release-verification.env"
safe_installer_command="Scripts/install_private_release_input_templates.sh --source-dir $template_dir --target-dir Config"
packet_origin_template_dir=""
case "$template_dir" in
  *build/CISubmissionPacket/private-release-input-templates)
    packet_origin_template_dir="${template_dir%build/CISubmissionPacket/private-release-input-templates}build/AppStoreSubmissionPacket/private-release-input-templates"
    ;;
esac
packet_origin_installer_command=""
if [[ -n "$packet_origin_template_dir" ]]; then
  packet_origin_installer_command="Scripts/install_private_release_input_templates.sh --source-dir $packet_origin_template_dir --target-dir Config"
fi

require_file "$index_path" "private release input template index"
require_file "$release_env_path" "release.env private input template"
require_file "$manual_env_path" "manual-release-verification.env private input template"

require_contains "$index_path" "# FreePrint Studio Private Release Input Templates" "private release input template index title"
require_contains "$index_path" "private-release-input-templates/" "private release input template output directory reference"
if [[ -n "$packet_origin_installer_command" ]]; then
  if ! grep -qF "$safe_installer_command" "$index_path" && ! grep -qF "$packet_origin_installer_command" "$index_path"; then
    fail "safe installer command is missing from $index_path"
  fi
else
  require_contains "$index_path" "$safe_installer_command" "safe installer command"
fi
require_contains "$index_path" "Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands" "selected-build placeholder replacement guidance"
require_not_contains "$index_path" "cp private-release-input-templates/" "unsafe manual copy instructions"
require_contains "$manual_env_path" "# Required: physical iPhone model, not Simulator." "manual evidence field guidance"
require_contains "$manual_env_path" "# Required: YYYY-MM-DD." "manual evidence field guidance"
require_contains "$manual_env_path" "# Required: pass." "manual evidence field guidance"
require_contains "$manual_env_path" "# Required: decimal inches within 0.0625 of MANUAL_AIRPRINT_RULER_TARGET_INCHES." "manual evidence field guidance"
require_contains "$manual_env_path" "# Required: same as APP_STORE_BUILD_NUMBER." "manual evidence field guidance"
require_contains "$manual_env_path" "# Required: physical iPad model, not Simulator." "manual evidence field guidance"

while IFS=$'\t' read -r template_name expected_count; do
  [[ -z "$template_name" ]] && continue
  if ! grep -Fq "| \`$template_name\` | [$template_name]($template_name) | $expected_count |" "$index_path"; then
    fail "Private release input template count mismatch for $template_name"
  fi
done <"$expected_counts"

while IFS=$'\t' read -r template_name env_name expected_line; do
  [[ -z "$template_name" ]] && continue
  template_path="$template_dir/$template_name"
  if ! grep -qxF "$expected_line" "$template_path"; then
    fail "template assignment is missing or mismatched in $template_name: $env_name"
  fi
done <"$expected_assignments"

if grep -q '^manual-release-verification\.env file=' "$manual_env_path"; then
  fail "manual release evidence file setup action must not be emitted as an env assignment"
fi

if (( failures > 0 )); then
  printf '\nPrivate release input template validation failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'Private release input templates match external readiness actions.\n'
