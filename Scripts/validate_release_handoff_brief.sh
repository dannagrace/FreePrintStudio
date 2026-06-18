#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 && "$#" -ne 4 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <release-handoff-brief.md> [ci-readiness.txt local-readiness.txt]\n' "$0" >&2
  exit 2
fi

actions_path="$1"
brief_path="$2"
ci_readiness_path="${3:-}"
local_readiness_path="${4:-}"
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
  local pattern="$1"
  local description="$2"
  if ! grep -qF "$pattern" "$brief_path"; then
    fail "$description is missing from release handoff brief"
  fi
}

require_section_contains() {
  local section_title="$1"
  local pattern="$2"
  local description="$3"
  if ! awk -v section_title="## $section_title" -v pattern="$pattern" '
    $0 == section_title {
      in_section = 1
      next
    }
    in_section && /^## / {
      exit
    }
    in_section && index($0, pattern) > 0 {
      found = 1
      exit
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$brief_path"; then
    fail "$description is missing from release handoff brief"
  fi
}

require_placeholder_guidance() {
  local placeholder="$1"
  local guidance="$2"
  local description="$3"
  if grep -qF "$placeholder" "$brief_path" && ! grep -qF "$guidance" "$brief_path"; then
    fail "$description is missing from release handoff brief"
  fi
}

markdown_cell() {
  local value="$1"
  value="${value//|/\\|}"
  value="${value//\`/\\\`}"
  printf '%s' "$value"
}

readiness_signal_lines() {
  local path="$1"
  if [[ -s "$path" ]]; then
    grep -E '^(BLOCKED|WARN):' "$path" | LC_ALL=C sort || true
  fi
}

readiness_count() {
  local path="$1"
  local prefix="$2"
  grep -c "^${prefix}:" "$path" || true
}

external_action_count() {
  local severity="${1:-}"
  awk -F '\t' -v severity="$severity" '
    NR == 1 {
      for (i = 1; i <= NF; i += 1) {
        columns[$i] = i
      }
      next
    }
    $1 != "" && (severity == "" || $(columns["severity"]) == severity) {
      count += 1
    }
    END { print count + 0 }
  ' "$actions_path"
}

write_expected_readiness_count_rows() {
  if [[ "$#" -eq 4 ]]; then
    printf 'CI packet\t%s\t%s\n' \
      "$(readiness_count "$ci_readiness_path" "BLOCKED")" \
      "$(readiness_count "$ci_readiness_path" "WARN")"
    printf 'Local preflight\t%s\t%s\n' \
      "$(readiness_count "$local_readiness_path" "BLOCKED")" \
      "$(readiness_count "$local_readiness_path" "WARN")"
  fi
  printf 'External actions\t%s\t%s\n' \
    "$(external_action_count blocker)" \
    "$(external_action_count warning)"
}

write_actual_readiness_count_rows() {
  local include_readiness_logs=0
  if [[ "$#" -eq 4 ]]; then
    include_readiness_logs=1
  fi
  awk '
    /^## Readiness Counts$/ {
      in_section = 1
      next
    }
    in_section && /^## / {
      in_section = 0
    }
    in_section {
      print
    }
  ' "$brief_path" \
    | sed -nE 's/^\| ([^|]+) \| ([0-9]+) \| ([0-9]+) \|.*\|$/\1	\2	\3/p' \
    | awk -F '\t' -v include_readiness_logs="$include_readiness_logs" 'include_readiness_logs == 1 || $1 == "External actions" { print }' \
    | LC_ALL=C sort || true
}

write_expected_readiness_delta_rows() {
  local source_path="$1"
  local comparison_path="$2"
  local line
  comm -23 <(readiness_signal_lines "$source_path") <(readiness_signal_lines "$comparison_path") |
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local severity="${line%%:*}"
      local item="${line#*: }"
      printf '%s\t%s\n' "$(markdown_cell "$severity")" "$(markdown_cell "$item")"
    done
}

write_actual_readiness_delta_rows() {
  local section_title="$1"
  awk -v section_title="## $section_title" '
    $0 == section_title {
      in_section = 1
      next
    }
    in_section && /^## / {
      in_section = 0
    }
    in_section {
      print
    }
  ' "$brief_path" \
    | sed -nE 's/^\| ([^|]+) \| ([^|]+) \|$/\1	\2/p' \
    | grep -v -e $'^Severity\tItem$' -e $'^---\t---$' \
    | LC_ALL=C sort || true
}

validate_readiness_delta_section() {
  local section_title="$1"
  local source_path="$2"
  local comparison_path="$3"
  local empty_text="$4"
  local description="$5"
  local expected_path="$temp_dir/${description}-expected.tsv"
  local actual_path="$temp_dir/${description}-actual.tsv"
  local diff_path="$temp_dir/${description}-diff.txt"

  write_expected_readiness_delta_rows "$source_path" "$comparison_path" >"$expected_path"
  write_actual_readiness_delta_rows "$section_title" >"$actual_path"

  if [[ ! -s "$expected_path" ]]; then
    if [[ -s "$actual_path" ]]; then
      fail "$section_title mismatch"
      diff -u "$expected_path" "$actual_path" >"$diff_path" || true
      sed 's/^/  /' "$diff_path"
    fi
    require_contains "$empty_text" "$section_title empty-state guidance"
    return
  fi

  if ! diff -u "$expected_path" "$actual_path" >"$diff_path"; then
    fail "$section_title mismatch"
    sed 's/^/  /' "$diff_path"
  fi
}

require_file "$actions_path" "external readiness actions input"
require_file "$brief_path" "release handoff brief input"
if [[ "$#" -eq 4 ]]; then
  require_file "$ci_readiness_path" "CI readiness log input"
  require_file "$local_readiness_path" "local readiness log input"
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

expected_summary="$temp_dir/expected-summary.tsv"
actual_summary="$temp_dir/actual-summary.tsv"
summary_diff="$temp_dir/summary-diff.txt"
expected_owner_summary="$temp_dir/expected-owner-summary.tsv"
actual_owner_summary="$temp_dir/actual-owner-summary.tsv"
owner_summary_diff="$temp_dir/owner-summary-diff.txt"
expected_details="$temp_dir/expected-details.tsv"

awk -F '\t' -v expected_details="$expected_details" '
  NR == 1 {
    for (i = 1; i <= NF; i += 1) {
      columns[$i] = i
    }
    required[1] = "category"
    required[2] = "severity"
    required[3] = "owner"
    required[4] = "field"
    required[5] = "item"
    required[6] = "next_action"
    required[7] = "validation_command"
    for (i = 1; i <= 7; i += 1) {
      if (!(required[i] in columns)) {
        print "FAIL: external readiness actions file is missing required column: " required[i] >"/dev/stderr"
        exit 3
      }
    }
    next
  }
  $1 != "" {
    total += 1
    category = $(columns["category"])
    severity = $(columns["severity"])
    owner = $(columns["owner"])
    key = category "\t" severity
    counts[key] += 1
    owner_counts[owner] += 1
    if (severity == "blocker") {
      owner_blocker_counts[owner] += 1
    } else if (severity == "warning") {
      owner_warning_counts[owner] += 1
    }
    print \
      owner "\t" \
      category "\t" \
      severity "\t" \
      $(columns["field"]) "\t" \
      $(columns["item"]) "\t" \
      $(columns["next_action"]) "\t" \
      $(columns["validation_command"]) >expected_details
  }
  END {
    if (total == 0) {
      print "FAIL: external readiness actions file has no action rows" >"/dev/stderr"
      exit 4
    }
    for (key in counts) {
      print key "\t" counts[key]
    }
    for (owner in owner_counts) {
      print "owner\t" owner "\t" owner_counts[owner] "\t" owner_blocker_counts[owner] + 0 "\t" owner_warning_counts[owner] + 0
    }
  }
' "$actions_path" >"$temp_dir/action-summary.tsv" || {
  exit 1
}
awk -F '\t' '$1 != "owner" { print }' "$temp_dir/action-summary.tsv" | LC_ALL=C sort >"$expected_summary"
awk -F '\t' '$1 == "owner" { print $2 "\t" $3 "\t" $4 "\t" $5 }' "$temp_dir/action-summary.tsv" | LC_ALL=C sort >"$expected_owner_summary"

require_contains "# FreePrint Studio Release Handoff Brief" "release handoff brief title"
require_contains "## Readiness Counts" "Readiness Counts section"
require_contains "## CI-only Readiness Detail" "CI-only Readiness Detail section"
require_contains "## Local-only Readiness Detail" "Local-only Readiness Detail section"
require_contains "## External Action Summary" "External Action Summary section"
require_contains "## Owner Summary" "Owner Summary section"
require_contains "## External Action Detail" "External Action Detail section"
require_contains "## Primary Action Files" "Primary Action Files section"
require_contains "## Next Commands" "Next Commands section"
require_placeholder_guidance \
  "PROCESSED_BUILD_NUMBER" \
  "Replace \`PROCESSED_BUILD_NUMBER\` with the processed App Store Connect build selected for review." \
  "selected-build placeholder replacement guidance"
require_placeholder_guidance \
  "YOURTEAMID" \
  "Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands." \
  "Team ID placeholder replacement guidance"
require_placeholder_guidance \
  "apple-id@example.com" \
  "Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands." \
  "Fastlane Apple ID placeholder replacement guidance"

for required_action_file in \
  "release-handoff-summary.tsv" \
  "release-handoff-brief.md" \
  "release-input-todo.md" \
  "release-owner-actions" \
  "private-release-input-templates" \
  "external-readiness-actions.tsv" \
  "ACTION_ITEMS.md" \
  "AppStore/release-inputs-worksheet.md" \
  "Config/release.env" \
  "Config/manual-release-verification.env"; do
  require_section_contains \
    "Primary Action Files" \
    "$required_action_file" \
    "primary action file reference is missing: $required_action_file"
done

for required_handoff_command in \
  "Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config" \
  "Scripts/print_release_input_status.sh --strict" \
  "Scripts/check_app_store_readiness.sh" \
  "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh" \
  "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" \
  "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh"; do
  require_section_contains \
    "Next Commands" \
    "$required_handoff_command" \
    "required handoff command is missing: $required_handoff_command"
done

if [[ "$#" -eq 4 ]]; then
  validate_readiness_delta_section \
    "CI-only Readiness Detail" \
    "$ci_readiness_path" \
    "$local_readiness_path" \
    "No CI-only blockers or warnings." \
    "ci-only-readiness-detail"
  validate_readiness_delta_section \
    "Local-only Readiness Detail" \
    "$local_readiness_path" \
    "$ci_readiness_path" \
    "No local-only blockers or warnings." \
    "local-only-readiness-detail"
fi

expected_readiness_counts="$temp_dir/expected-readiness-counts.tsv"
actual_readiness_counts="$temp_dir/actual-readiness-counts.tsv"
readiness_counts_diff="$temp_dir/readiness-counts-diff.txt"
write_expected_readiness_count_rows "$@" | LC_ALL=C sort >"$expected_readiness_counts"
write_actual_readiness_count_rows "$@" >"$actual_readiness_counts"
if ! diff -u "$expected_readiness_counts" "$actual_readiness_counts" >"$readiness_counts_diff"; then
  fail "Readiness Counts mismatch"
  sed 's/^/  /' "$readiness_counts_diff"
fi

awk '
  /^## External Action Summary$/ {
    in_summary = 1
    next
  }
  in_summary && /^## / {
    in_summary = 0
  }
  in_summary {
    print
  }
' "$brief_path" \
  | sed -nE 's/^\| ([^|]+) \| ([^|]+) \| ([0-9]+) \|$/\1	\2	\3/p' \
  | grep -v $'^Category\tSeverity\tCount$' \
  | LC_ALL=C sort >"$actual_summary"

if ! diff -u "$expected_summary" "$actual_summary" >"$summary_diff"; then
  fail "External Action Summary count mismatch"
  sed 's/^/  /' "$summary_diff"
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
' "$brief_path" \
  | sed -nE 's/^\| ([^|]+) \| ([0-9]+) \| ([0-9]+) \| ([0-9]+) \|$/\1	\2	\3	\4/p' \
  | grep -v $'^Owner\tActions\tBlockers\tWarnings$' \
  | LC_ALL=C sort >"$actual_owner_summary"

if ! diff -u "$expected_owner_summary" "$actual_owner_summary" >"$owner_summary_diff"; then
  fail "Owner Summary count mismatch"
  sed 's/^/  /' "$owner_summary_diff"
fi

while IFS=$'\t' read -r owner category severity field item next_action validation_command; do
  [[ -n "${owner:-}${category:-}${severity:-}${field:-}${item:-}${next_action:-}${validation_command:-}" ]] || continue
  expected_row="| $(markdown_cell "$owner") | $(markdown_cell "$category") | $(markdown_cell "$severity") | \`$(markdown_cell "$field")\` | $(markdown_cell "$item") | $(markdown_cell "$next_action") | \`$(markdown_cell "$validation_command")\` |"
  if ! grep -Fxq "$expected_row" "$brief_path"; then
    fail "external action detail row is missing or mismatched in release handoff brief: $field - $item"
  fi
done <"$expected_details"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'Release handoff brief matches external readiness actions.\n'
