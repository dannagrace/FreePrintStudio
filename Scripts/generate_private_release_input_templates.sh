#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <private-release-input-templates-dir>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
output_dir="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions file is missing or empty: %s\n' "$actions_path" >&2
  exit 1
fi

STANDARD_RELEASE_ENV_NAMES="DEVELOPMENT_TEAM_ID ALLOW_PROVISIONING_UPDATES APP_STORE_CONNECT_API_KEY_JSON ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH APP_REVIEW_CONTACT_FIRST_NAME APP_REVIEW_CONTACT_LAST_NAME APP_REVIEW_CONTACT_PHONE APP_REVIEW_CONTACT_EMAIL FASTLANE_USER FASTLANE_ITC_TEAM_ID FASTLANE_ITC_TEAM_NAME CONFIRM_UPLOAD_APP_PRIVACY APP_PRIVACY_SKIP_PUBLISH APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT IPA_PATH TESTFLIGHT_CHANGELOG APP_STORE_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW"

STANDARD_MANUAL_ENV_NAMES="MANUAL_VERIFIER_NAME MANUAL_REAL_IPHONE_MODEL MANUAL_REAL_IPHONE_IOS_VERSION MANUAL_REAL_IPHONE_TEST_DATE MANUAL_REAL_IPHONE_PHOTOS_IMPORT MANUAL_REAL_IPHONE_PDF_EXPORT MANUAL_REAL_IPHONE_PRINT_SHEET MANUAL_AIRPRINT_TEST_DATE MANUAL_AIRPRINT_PRINTER MANUAL_AIRPRINT_EXACT_SIZE MANUAL_AIRPRINT_RULER_TARGET_INCHES MANUAL_AIRPRINT_RULER_MEASURED_INCHES MANUAL_TESTFLIGHT_BUILD_NUMBER MANUAL_TESTFLIGHT_DEVICE MANUAL_TESTFLIGHT_TEST_DATE MANUAL_TESTFLIGHT_INSTALL MANUAL_TESTFLIGHT_PRINT_WORKFLOW MANUAL_IPAD_TESTFLIGHT_DEVICE MANUAL_IPAD_TESTFLIGHT_TEST_DATE MANUAL_IPAD_TESTFLIGHT_INSTALL MANUAL_IPAD_TESTFLIGHT_LAYOUT MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW"

mkdir -p "$output_dir"
rm -f \
  "$output_dir/index.md" \
  "$output_dir/release.env" \
  "$output_dir/manual-release-verification.env"

# Emits MANUAL_AIRPRINT_RULER_TARGET_INCHES="6" when measured ruler evidence is required.
awk -F '\t' \
  -v output_dir="$output_dir" \
  -v actions_path="$actions_path" \
  -v generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  -v standard_release_env_names="$STANDARD_RELEASE_ENV_NAMES" \
  -v standard_manual_env_names="$STANDARD_MANUAL_ENV_NAMES" '
  function fail(message) {
    print "FAIL: " message >"/dev/stderr"
    exit 1
  }

  function add_release_env(name) {
    if (name ~ /^[A-Z0-9_]+$/ && !(name in release_seen)) {
      release_seen[name] = 1
      release_count += 1
      release_names[release_count] = name
    }
  }

  function add_manual_env(name) {
    if (name == "MANUAL_AIRPRINT_RULER_MEASURED_INCHES" && !("MANUAL_AIRPRINT_RULER_TARGET_INCHES" in manual_seen)) {
      manual_seen["MANUAL_AIRPRINT_RULER_TARGET_INCHES"] = 1
      manual_count += 1
      manual_names[manual_count] = "MANUAL_AIRPRINT_RULER_TARGET_INCHES"
    }
    if (name ~ /^[A-Z0-9_]+$/ && !(name in manual_seen)) {
      manual_seen[name] = 1
      manual_count += 1
      manual_names[manual_count] = name
    }
  }

  function add_field_assignments(field_name, target,   parts, part_count, part_index, candidate) {
    if (field_name ~ /^[A-Z0-9_]+$/) {
      if (target ~ /^Config\/release\.env/) {
        add_release_env(field_name)
      } else if (target == "Config/manual-release-verification.env") {
        add_manual_env(field_name)
      }
      return
    }

    if (field_name ~ / or / || field_name ~ /\//) {
      part_count = split(field_name, parts, / or |\/+/)
      for (part_index = 1; part_index <= part_count; part_index += 1) {
        candidate = parts[part_index]
        gsub(/^ +| +$/, "", candidate)
        if (target ~ /^Config\/release\.env/) {
          add_release_env(candidate)
        } else if (target == "Config/manual-release-verification.env") {
          add_manual_env(candidate)
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

  function add_standard_env_assignments(names, template_name,   parts, part_count, part_index, candidate) {
    part_count = split(names, parts, /[[:space:]]+/)
    for (part_index = 1; part_index <= part_count; part_index += 1) {
      candidate = parts[part_index]
      gsub(/^ +| +$/, "", candidate)
      if (candidate == "") {
        continue
      }
      if (template_name == "release.env") {
        add_release_env(candidate)
      } else if (template_name == "manual-release-verification.env") {
        add_manual_env(candidate)
      }
    }
  }

  function manual_env_hint(name) {
    if (name == "MANUAL_VERIFIER_NAME") {
      return "verifier name or team."
    }
    if (name == "MANUAL_REAL_IPHONE_MODEL") {
      return "physical iPhone model, not Simulator."
    }
    if (name == "MANUAL_REAL_IPHONE_IOS_VERSION") {
      return "numeric iOS version, e.g. 18.5 or iOS 18.5."
    }
    if (name ~ /_TEST_DATE$/) {
      return "YYYY-MM-DD."
    }
    if (name == "MANUAL_AIRPRINT_PRINTER") {
      return "printer or production-equivalent workflow name."
    }
    if (name == "MANUAL_AIRPRINT_RULER_TARGET_INCHES") {
      return "6."
    }
    if (name == "MANUAL_AIRPRINT_RULER_MEASURED_INCHES") {
      return "decimal inches within 0.0625 of MANUAL_AIRPRINT_RULER_TARGET_INCHES."
    }
    if (name == "MANUAL_TESTFLIGHT_BUILD_NUMBER") {
      return "same as APP_STORE_BUILD_NUMBER."
    }
    if (name == "MANUAL_TESTFLIGHT_DEVICE") {
      return "physical device model."
    }
    if (name == "MANUAL_IPAD_TESTFLIGHT_DEVICE") {
      return "physical iPad model, not Simulator."
    }
    if (name ~ /_(PHOTOS_IMPORT|PDF_EXPORT|PRINT_SHEET|EXACT_SIZE|INSTALL|PRINT_WORKFLOW|LAYOUT)$/) {
      return "pass."
    }
    return ""
  }

  BEGIN {
    add_standard_env_assignments(standard_release_env_names, "release.env")
    add_standard_env_assignments(standard_manual_env_names, "manual-release-verification.env")
  }

  function write_env_file(path, label, count, names,   idx, name) {
    print "# FreePrint Studio " label "." >path
    print "# Generated At: " generated_at >>path
    print "# Source: " actions_path >>path
    print "# Install this complete starter with Scripts/install_private_release_input_templates.sh, then fill real private values locally." >>path
    print "# Keep filled values out of git." >>path
    print "" >>path

    if (count == 0) {
      print "# No current external readiness action maps to this private input file." >>path
      return
    }

    for (idx = 1; idx <= count; idx += 1) {
      name = names[idx]
      if (label == "manual-release-verification.env") {
        hint = manual_env_hint(name)
        if (hint != "") {
          print "# Required: " hint >>path
        }
      }
      if (name == "MANUAL_AIRPRINT_RULER_TARGET_INCHES") {
        print "MANUAL_AIRPRINT_RULER_TARGET_INCHES=\"6\"" >>path
      } else {
        printf "%s=\"\"\n", name >>path
      }
    }
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
    row_count += 1
    field_name = $(columns["field"])
    target = $(columns["target"])
    item = $(columns["item"])
    if (is_manual_file_setup(field_name, target, item)) {
      next
    }
    add_field_assignments(field_name, target)
  }

  END {
    if (row_count == 0) {
      fail("external readiness actions file has no action rows")
    }

    index_path = output_dir "/index.md"
    release_path = output_dir "/release.env"
    manual_path = output_dir "/manual-release-verification.env"

    write_env_file(release_path, "release.env", release_count, release_names)
    write_env_file(manual_path, "manual-release-verification.env", manual_count, manual_names)

    print "# FreePrint Studio Private Release Input Templates" >index_path
    print "" >>index_path
    print "- Generated At: `" generated_at "`" >>index_path
    print "- Source: `" actions_path "`" >>index_path
    print "- Output: `private-release-input-templates/`" >>index_path
    print "" >>index_path
    print "These files are complete blank private-input starters seeded with the full release input surface and the current external readiness actions. Install them with `Scripts/install_private_release_input_templates.sh` so existing private values are backed up, missing keys are appended, and installed files keep owner-only permissions. Fill real values locally and keep the filled files out of git." >>index_path
    print "" >>index_path
    print "## Templates" >>index_path
    print "" >>index_path
    print "| Template | File | Assignments |" >>index_path
    print "| --- | --- | ---: |" >>index_path
    printf "| `release.env` | [release.env](release.env) | %d |\n", release_count >>index_path
    printf "| `manual-release-verification.env` | [manual-release-verification.env](manual-release-verification.env) | %d |\n", manual_count >>index_path
    print "" >>index_path
    print "## Usage" >>index_path
    print "" >>index_path
    print "```sh" >>index_path
    print "Scripts/install_private_release_input_templates.sh --source-dir " output_dir " --target-dir Config" >>index_path
    print "Scripts/print_release_input_status.sh --strict" >>index_path
    print "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh" >>index_path
    print "```" >>index_path
    print "" >>index_path
    print "Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands." >>index_path
  }
' "$actions_path"

printf 'Private release input templates written: %s\n' "$output_dir"
