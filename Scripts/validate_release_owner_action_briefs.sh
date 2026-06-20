#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <owner-action-briefs-dir>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
owner_dir="$2"
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

require_contains_file() {
  local path="$1"
  local pattern="$2"
  local description="$3"
  if [[ ! -s "$path" ]]; then
    fail "$description cannot be checked because file is missing: $path"
    return
  fi
  if ! grep -qF -- "$pattern" "$path"; then
    fail "$description is missing from $path"
  fi
}

require_file "$actions_path" "external readiness actions input"
if [[ ! -d "$owner_dir" ]]; then
  fail "owner action brief directory is missing: $owner_dir"
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

expected_owners="$temp_dir/expected-owners.tsv"
expected_details="$temp_dir/expected-details.tsv"
selected_build_placeholder_guidance="Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands."
team_id_placeholder_guidance="Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands."
fastlane_apple_id_placeholder_guidance="Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands."
private_input_installer_command="Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config"
private_input_status_command="Scripts/print_release_input_status.sh --strict"

awk -F '\t' -v expected_owners="$expected_owners" -v expected_details="$expected_details" '
  function fail(message) {
    print "FAIL: " message >"/dev/stderr"
    exit 1
  }

  function markdown_cell(value) {
    gsub(/\|/, "\\|", value)
    gsub(/`/, "\\`", value)
    return value
  }

  function code_text(value) {
    gsub(/`/, "\\`", value)
    return "`" value "`"
  }

  function owner_slug(value, slug) {
    slug = tolower(value)
    gsub(/[^a-z0-9]+/, "-", slug)
    gsub(/^-+|-+$/, "", slug)
    if (slug == "") {
      slug = "owner"
    }
    return slug
  }

  function owner_file(owner_name) {
    return owner_slug(owner_name) ".md"
  }

  function add_expected_action(action_category, action_severity, action_owner, action_field, action_target, action_item, action_next_action, action_validation_command, placeholder_source, expected_row) {
    placeholder_source = action_next_action " " action_validation_command
    file_name = owner_file(action_owner)
    owner_counts[action_owner] += 1
    if (placeholder_source ~ /PROCESSED_BUILD_NUMBER/) {
      owner_selected_build_placeholder[action_owner] = 1
    }
    if (placeholder_source ~ /YOURTEAMID/) {
      owner_team_id_placeholder[action_owner] = 1
    }
    if (placeholder_source ~ /apple-id@example\.com/) {
      owner_fastlane_apple_id_placeholder[action_owner] = 1
    }
    if (action_target ~ /(^| )Config\//) {
      owner_private_input_setup[action_owner] = 1
    }
    if (!(action_owner in owner_seen)) {
      owner_seen[action_owner] = 1
      owner_order_count += 1
      owner_order[owner_order_count] = action_owner
    }
    if (action_severity == "blocker") {
      owner_blocker_counts[action_owner] += 1
    } else if (action_severity == "warning") {
      owner_warning_counts[action_owner] += 1
    }
    expected_row = "| " \
      markdown_cell(action_category) " | " \
      markdown_cell(action_severity) " | " \
      code_text(markdown_cell(action_field)) " | " \
      code_text(markdown_cell(action_target)) " | " \
      markdown_cell(action_item) " | " \
      markdown_cell(action_next_action) " | " \
      code_text(markdown_cell(action_validation_command)) " |"
    print file_name "\t" action_field "\t" action_item "\t" expected_row >expected_details
  }

  NR == 1 {
    for (i = 1; i <= NF; i += 1) {
      columns[$i] = i
    }
    required[1] = "category"
    required[2] = "severity"
    required[3] = "owner"
    required[4] = "field"
    required[5] = "target"
    required[6] = "item"
    required[7] = "next_action"
    required[8] = "validation_command"
    for (i = 1; i <= 8; i += 1) {
      if (!(required[i] in columns)) {
        fail("external readiness actions file is missing required column: " required[i])
      }
    }
    next
  }

  $1 != "" {
    total += 1
    add_expected_action( \
      $(columns["category"]), \
      $(columns["severity"]), \
      $(columns["owner"]), \
      $(columns["field"]), \
      $(columns["target"]), \
      $(columns["item"]), \
      $(columns["next_action"]), \
      $(columns["validation_command"]))
  }

  END {
    if (total == 0) {
      fail("external readiness actions file has no action rows")
    }
    add_expected_action( \
      "Final Submission Guard", \
      "blocker", \
      "Release owner", \
      "APP_STORE_BUILD_NUMBER", \
      "Config/release.env", \
      "Processed App Store Connect build selected for App Review.", \
      "Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands.", \
      "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh")
    add_expected_action( \
      "Final Submission Guard", \
      "blocker", \
      "Release owner", \
      "CONFIRM_SUBMIT_FOR_REVIEW", \
      "Config/release.env", \
      "Explicit final confirmation before Fastlane submits the selected build for review.", \
      "Set CONFIRM_SUBMIT_FOR_REVIEW=1 only for the final deliberate App Review submission.", \
      "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review")
    for (owner_index = 1; owner_index <= owner_order_count; owner_index += 1) {
      owner_name = owner_order[owner_index]
      print owner_name "\t" owner_file(owner_name) "\t" owner_counts[owner_name] "\t" owner_blocker_counts[owner_name] + 0 "\t" owner_warning_counts[owner_name] + 0 "\t" owner_selected_build_placeholder[owner_name] + 0 "\t" owner_team_id_placeholder[owner_name] + 0 "\t" owner_fastlane_apple_id_placeholder[owner_name] + 0 "\t" owner_private_input_setup[owner_name] + 0 >expected_owners
    }
  }
' "$actions_path" || {
  exit 1
}

index_path="$owner_dir/index.md"
require_file "$index_path" "owner action brief index"
require_contains_file "$index_path" "# FreePrint Studio Release Owner Action Briefs" "owner action brief index title"

while IFS=$'\t' read -r owner_name file_name actions blockers warnings selected_build_placeholder team_id_placeholder fastlane_apple_id_placeholder private_input_setup; do
  [[ -n "${owner_name:-}${file_name:-}" ]] || continue
  owner_path="$owner_dir/$file_name"
  require_file "$owner_path" "owner action brief for $owner_name"
  require_contains_file "$index_path" "| $owner_name | [$file_name]($file_name) | $actions | $blockers | $warnings |" "owner action brief index row for $owner_name"
  require_contains_file "$owner_path" "# $owner_name Release Actions" "owner action brief title for $owner_name"
  if ! grep -qF -- "- Actions: \`$actions\`" "$owner_path" ||
     ! grep -qF -- "- Blockers: \`$blockers\`" "$owner_path" ||
     ! grep -qF -- "- Warnings: \`$warnings\`" "$owner_path"; then
    fail "Owner action brief count mismatch for $owner_name"
  fi
  require_contains_file "$owner_path" "## Action Detail" "owner action detail section for $owner_name"
  require_contains_file "$owner_path" "## Validation Commands" "owner validation commands section for $owner_name"
  if [[ "${private_input_setup:-0}" == "1" ]]; then
    require_contains_file "$owner_path" "## Private Input Setup" "private input setup guidance for $owner_name"
    require_contains_file "$owner_path" "$private_input_installer_command" "private input setup guidance for $owner_name"
    require_contains_file "$owner_path" "$private_input_status_command" "private input setup guidance for $owner_name"
  fi
  if [[ "${selected_build_placeholder:-0}" == "1" ]]; then
    require_contains_file "$owner_path" "$selected_build_placeholder_guidance" "selected-build placeholder replacement guidance for $owner_name"
  fi
  if [[ "${team_id_placeholder:-0}" == "1" ]]; then
    require_contains_file "$owner_path" "$team_id_placeholder_guidance" "Team ID placeholder replacement guidance for $owner_name"
  fi
  if [[ "${fastlane_apple_id_placeholder:-0}" == "1" ]]; then
    require_contains_file "$owner_path" "$fastlane_apple_id_placeholder_guidance" "Fastlane Apple ID placeholder replacement guidance for $owner_name"
  fi
done <"$expected_owners"

while IFS=$'\t' read -r file_name field item expected_row; do
  [[ -n "${file_name:-}${expected_row:-}" ]] || continue
  owner_path="$owner_dir/$file_name"
  if [[ ! -s "$owner_path" ]]; then
    fail "action detail row cannot be checked because owner file is missing: $file_name"
    continue
  fi
  if ! grep -Fxq -- "$expected_row" "$owner_path"; then
    fail "action detail row is missing or mismatched in owner action brief: $field - $item"
  fi
done <"$expected_details"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'Release owner action briefs match external readiness actions and final submission guards.\n'
