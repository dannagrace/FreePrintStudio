#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <release-handoff-brief.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
brief_path="$2"
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

markdown_cell() {
  local value="$1"
  value="${value//|/\\|}"
  value="${value//\`/\\\`}"
  printf '%s' "$value"
}

require_file "$actions_path" "external readiness actions input"
require_file "$brief_path" "release handoff brief input"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

expected_summary="$temp_dir/expected-summary.tsv"
actual_summary="$temp_dir/actual-summary.tsv"
summary_diff="$temp_dir/summary-diff.txt"
expected_details="$temp_dir/expected-details.tsv"

awk -F '\t' -v expected_details="$expected_details" '
  NR == 1 {
    for (i = 1; i <= NF; i += 1) {
      columns[$i] = i
    }
    required[1] = "category"
    required[2] = "severity"
    required[3] = "field"
    required[4] = "item"
    required[5] = "next_action"
    required[6] = "validation_command"
    for (i = 1; i <= 6; i += 1) {
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
    key = category "\t" severity
    counts[key] += 1
    print \
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
  }
' "$actions_path" | LC_ALL=C sort >"$expected_summary" || {
  exit 1
}

require_contains "# FreePrint Studio Release Handoff Brief" "release handoff brief title"
require_contains "## External Action Summary" "External Action Summary section"
require_contains "## External Action Detail" "External Action Detail section"

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

while IFS=$'\t' read -r category severity field item next_action validation_command; do
  [[ -n "${category:-}${severity:-}${field:-}${item:-}${next_action:-}${validation_command:-}" ]] || continue
  expected_row="| $(markdown_cell "$category") | $(markdown_cell "$severity") | \`$(markdown_cell "$field")\` | $(markdown_cell "$item") | $(markdown_cell "$next_action") | \`$(markdown_cell "$validation_command")\` |"
  if ! grep -Fxq "$expected_row" "$brief_path"; then
    fail "external action detail row is missing or mismatched in release handoff brief: $field - $item"
  fi
done <"$expected_details"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'Release handoff brief matches external readiness actions.\n'
