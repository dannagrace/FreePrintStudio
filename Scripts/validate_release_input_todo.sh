#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <release-input-todo.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
todo_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

if [[ ! -s "$todo_path" ]]; then
  printf 'FAIL: release input TODO is missing or empty: %s\n' "$todo_path"
  exit 1
fi

failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

require_contains() {
  local pattern="$1"
  local description="$2"
  if ! grep -qF "$pattern" "$todo_path"; then
    fail "$description is missing from release input TODO"
  fi
}

todo_count() {
  local label="$1"
  sed -nE "s/^- ${label}: \`([0-9]+)\`$/\\1/p" "$todo_path" | tail -n 1
}

compare_count() {
  local label="$1"
  local expected="$2"
  local actual
  actual="$(todo_count "$label")"
  if [[ -z "$actual" ]]; then
    fail "$label count is missing from release input TODO"
    return
  fi
  if [[ "$actual" != "$expected" ]]; then
    fail "$label count mismatch (release input TODO: $actual; external-readiness-actions.tsv: $expected)"
  fi
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

expected_targets="$temp_dir/expected-targets.tsv"
actual_targets="$temp_dir/actual-targets.tsv"
target_diff="$temp_dir/target-diff.txt"
expected_owners="$temp_dir/expected-owners.tsv"
actual_owners="$temp_dir/actual-owners.tsv"
owner_diff="$temp_dir/owner-diff.txt"
expected_action_details="$temp_dir/expected-action-details.tsv"
expected_action_rows="$temp_dir/expected-action-rows.tsv"

awk -F '\t' '
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
        print "FAIL: external readiness actions file is missing required column: " required[i] >"/dev/stderr"
        exit 3
      }
    }
    next
  }
  $1 != "" {
    total += 1
    severity = $(columns["severity"])
    target = $(columns["target"])
    owner = $(columns["owner"])
    target_counts[target] += 1
    owner_counts[owner] += 1
    if (severity == "blocker") {
      blockers += 1
      owner_blocker_counts[owner] += 1
    } else if (severity == "warning") {
      warnings += 1
      owner_warning_counts[owner] += 1
    }
    placeholder_source = $(columns["next_action"]) " " $(columns["validation_command"])
    if (placeholder_source ~ /YOURTEAMID/) {
      has_team_id_placeholder = 1
    }
    if (placeholder_source ~ /apple-id@example[.]com/) {
      has_fastlane_apple_id_placeholder = 1
    }
  }
  END {
    if (total == 0) {
      print "FAIL: external readiness actions file has no action rows" >"/dev/stderr"
      exit 4
    }
    final_submission_guard_actions = 2
    final_submission_guard_blockers = 2
    target_counts["Config/release.env"] += final_submission_guard_actions
    owner_counts["Release owner"] += final_submission_guard_actions
    owner_blocker_counts["Release owner"] += final_submission_guard_blockers
    printf "total\t%s\n", total
    printf "final_submission_guard_actions\t%s\n", final_submission_guard_actions
    printf "total_handoff_actions\t%s\n", total + final_submission_guard_actions
    printf "blockers\t%s\n", blockers + 0
    printf "total_handoff_blockers\t%s\n", blockers + final_submission_guard_blockers
    printf "warnings\t%s\n", warnings + 0
    printf "total_handoff_warnings\t%s\n", warnings + 0
    for (target in target_counts) {
      printf "target\t%s\t%s\n", target, target_counts[target]
    }
    for (owner in owner_counts) {
      printf "owner\t%s\t%s\t%s\t%s\n", owner, owner_counts[owner], owner_blocker_counts[owner] + 0, owner_warning_counts[owner] + 0
    }
    printf "placeholder\tselected_build\t1\n"
    if (has_team_id_placeholder) {
      printf "placeholder\tteam_id\t1\n"
    }
    if (has_fastlane_apple_id_placeholder) {
      printf "placeholder\tfastlane_apple_id\t1\n"
    }
  }
' "$actions_path" >"$temp_dir/action-summary.tsv" || {
  cat "$temp_dir/action-summary.tsv" 2>/dev/null || true
  exit 1
}

awk -F '\t' -v expected_action_rows="$expected_action_rows" '
  function markdown_cell(value) {
    gsub(/\|/, "\\|", value)
    gsub(/`/, "\\`", value)
    return value
  }

  function code_text(value) {
    gsub(/`/, "\\`", value)
    return "`" value "`"
  }

  NR == 1 {
    for (i = 1; i <= NF; i += 1) {
      columns[$i] = i
    }
    next
  }
  $1 != "" {
    field = $(columns["field"])
    target = $(columns["target"])
    item = $(columns["item"])
    if (target == "Config/manual-release-verification.env" && \
      (field == "MANUAL_RELEASE_VERIFICATION_PATH" || item ~ /Manual release verification evidence file/)) {
      field = "manual-release-verification.env file"
    }
    print field "\t" item "\t" $(columns["validation_command"])
    printf "%s\t%s\t| %s | %s | %s | %s | %s | %s |\n", \
      field, \
      item, \
      markdown_cell($(columns["severity"])), \
      markdown_cell($(columns["owner"])), \
      code_text(markdown_cell(field)), \
      markdown_cell(item), \
      markdown_cell($(columns["next_action"])), \
      code_text(markdown_cell($(columns["validation_command"]))) >expected_action_rows
  }
' "$actions_path" >"$expected_action_details"

expected_total="$(awk -F '\t' '$1 == "total" { print $2 }' "$temp_dir/action-summary.tsv")"
expected_final_submission_guard_actions="$(awk -F '\t' '$1 == "final_submission_guard_actions" { print $2 }' "$temp_dir/action-summary.tsv")"
expected_total_handoff_actions="$(awk -F '\t' '$1 == "total_handoff_actions" { print $2 }' "$temp_dir/action-summary.tsv")"
expected_blockers="$(awk -F '\t' '$1 == "blockers" { print $2 }' "$temp_dir/action-summary.tsv")"
expected_total_handoff_blockers="$(awk -F '\t' '$1 == "total_handoff_blockers" { print $2 }' "$temp_dir/action-summary.tsv")"
expected_warnings="$(awk -F '\t' '$1 == "warnings" { print $2 }' "$temp_dir/action-summary.tsv")"
expected_total_handoff_warnings="$(awk -F '\t' '$1 == "total_handoff_warnings" { print $2 }' "$temp_dir/action-summary.tsv")"
has_selected_build_placeholder="$(awk -F '\t' '$1 == "placeholder" && $2 == "selected_build" { print $3 }' "$temp_dir/action-summary.tsv" | tail -n 1)"
has_team_id_placeholder="$(awk -F '\t' '$1 == "placeholder" && $2 == "team_id" { print $3 }' "$temp_dir/action-summary.tsv" | tail -n 1)"
has_fastlane_apple_id_placeholder="$(awk -F '\t' '$1 == "placeholder" && $2 == "fastlane_apple_id" { print $3 }' "$temp_dir/action-summary.tsv" | tail -n 1)"
private_template_install_command="Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config"
awk -F '\t' '$1 == "target" { print $2 "\t" $3 }' "$temp_dir/action-summary.tsv" | LC_ALL=C sort >"$expected_targets"
awk -F '\t' '$1 == "owner" { print $2 "\t" $3 "\t" $4 "\t" $5 }' "$temp_dir/action-summary.tsv" | LC_ALL=C sort >"$expected_owners"

require_contains "# FreePrint Studio Release Input TODO" "release input TODO title"
require_contains "## Target Summary" "Target Summary"
require_contains "## Owner Summary" "Owner Summary"
require_contains "External Actions" "External Actions"
require_contains "Final Submission Guard Actions" "Final Submission Guard Actions"
require_contains "Total Handoff Actions" "Total Handoff Actions"
require_contains "Blockers" "Blockers"
require_contains "Total Handoff Blockers" "Total Handoff Blockers"
require_contains "Warnings" "Warnings"
require_contains "Total Handoff Warnings" "Total Handoff Warnings"
require_contains "Config/release.env" "Config/release.env guidance"
require_contains "If the file does not exist yet, install or sync it from the current private templates with \`$private_template_install_command\` before filling release values." "Config/release.env private template installer guidance"
require_contains "Config/manual-release-verification.env" "Config/manual-release-verification.env guidance"
if grep -qF $'manual-release-verification.env file\t' "$expected_action_details"; then
  require_contains "If the file does not exist yet, install or sync it from the current private templates with \`$private_template_install_command\` before recording evidence." "Config/manual-release-verification.env private template installer guidance"
fi
require_contains "## Final Submission Guards" "Final Submission Guards section"
require_contains "APP_STORE_BUILD_NUMBER=" "selected App Store build guard"
require_contains "CONFIRM_SUBMIT_FOR_REVIEW=" "final review submission confirmation guard"
require_contains "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review" "guarded final App Review submission command"
require_contains "## Non-env External Actions" "Non-env External Actions section"
require_contains "## Placeholder Replacement Notes" "Placeholder Replacement Notes"
if [[ -n "$has_selected_build_placeholder" ]]; then
  require_contains "Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands." "selected-build placeholder replacement guidance"
fi
if [[ -n "$has_team_id_placeholder" ]]; then
  require_contains "Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands." "Team ID placeholder replacement guidance"
fi
if [[ -n "$has_fastlane_apple_id_placeholder" ]]; then
  require_contains "Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands." "Fastlane Apple ID placeholder replacement guidance"
fi

compare_count "External Actions" "$expected_total"
compare_count "Final Submission Guard Actions" "$expected_final_submission_guard_actions"
compare_count "Total Handoff Actions" "$expected_total_handoff_actions"
compare_count "Blockers" "$expected_blockers"
compare_count "Total Handoff Blockers" "$expected_total_handoff_blockers"
compare_count "Warnings" "$expected_warnings"
compare_count "Total Handoff Warnings" "$expected_total_handoff_warnings"

awk '
  /^## Target Summary$/ {
    in_summary = 1
    next
  }
  in_summary && /^## / {
    in_summary = 0
  }
  in_summary {
    print
  }
' "$todo_path" \
  | sed -nE 's/^\| `([^`]*)` \| ([0-9]+) \|$/\1	\2/p' \
  | LC_ALL=C sort >"$actual_targets"

if ! diff -u "$expected_targets" "$actual_targets" >"$target_diff"; then
  fail "Target Summary counts do not match external-readiness-actions.tsv"
  sed 's/^/  /' "$target_diff"
fi

awk '
  /^## Owner Summary$/ {
    in_summary = 1
    next
  }
  in_summary && /^## / {
    in_summary = 0
  }
  in_summary {
    print
  }
' "$todo_path" \
  | sed -nE 's/^\| `([^`]*)` \| ([0-9]+) \| ([0-9]+) \| ([0-9]+) \|$/\1	\2	\3	\4/p' \
  | LC_ALL=C sort >"$actual_owners"

if ! diff -u "$expected_owners" "$actual_owners" >"$owner_diff"; then
  fail "Owner Summary counts do not match external-readiness-actions.tsv"
  sed 's/^/  /' "$owner_diff"
fi

while IFS=$'\t' read -r expected_field expected_item expected_validation_command; do
  [[ -n "${expected_field:-}${expected_item:-}${expected_validation_command:-}" ]] || continue

  if ! grep -qF "$expected_field" "$todo_path"; then
    fail "action field is missing from release input TODO: $expected_field"
  fi

  if ! grep -qF "$expected_item" "$todo_path"; then
    fail "action item is missing from release input TODO: $expected_item"
  fi

  if ! grep -qF "$expected_validation_command" "$todo_path"; then
    fail "action validation command is missing from release input TODO: $expected_validation_command"
  fi
done <"$expected_action_details"

while IFS=$'\t' read -r expected_field expected_item expected_row; do
  [[ -n "${expected_row:-}" ]] || continue

  if ! grep -Fxq "$expected_row" "$todo_path"; then
    fail "action detail row is missing or mismatched in release input TODO: $expected_field - $expected_item"
  fi
done <"$expected_action_rows"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'Release input TODO matches external readiness actions.\n'
