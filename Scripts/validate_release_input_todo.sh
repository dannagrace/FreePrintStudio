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
    target_counts[target] += 1
    if (severity == "blocker") {
      blockers += 1
    } else if (severity == "warning") {
      warnings += 1
    }
  }
  END {
    if (total == 0) {
      print "FAIL: external readiness actions file has no action rows" >"/dev/stderr"
      exit 4
    }
    printf "total\t%s\n", total
    printf "blockers\t%s\n", blockers + 0
    printf "warnings\t%s\n", warnings + 0
    for (target in target_counts) {
      printf "target\t%s\t%s\n", target, target_counts[target]
    }
  }
' "$actions_path" >"$temp_dir/action-summary.tsv" || {
  cat "$temp_dir/action-summary.tsv" 2>/dev/null || true
  exit 1
}

expected_total="$(awk -F '\t' '$1 == "total" { print $2 }' "$temp_dir/action-summary.tsv")"
expected_blockers="$(awk -F '\t' '$1 == "blockers" { print $2 }' "$temp_dir/action-summary.tsv")"
expected_warnings="$(awk -F '\t' '$1 == "warnings" { print $2 }' "$temp_dir/action-summary.tsv")"
awk -F '\t' '$1 == "target" { print $2 "\t" $3 }' "$temp_dir/action-summary.tsv" | LC_ALL=C sort >"$expected_targets"

require_contains "# FreePrint Studio Release Input TODO" "release input TODO title"
require_contains "## Target Summary" "Target Summary"
require_contains "External Actions" "External Actions"
require_contains "Blockers" "Blockers"
require_contains "Warnings" "Warnings"
require_contains "Config/release.env" "Config/release.env guidance"
require_contains "Config/manual-release-verification.env" "Config/manual-release-verification.env guidance"
require_contains "## Non-env External Actions" "Non-env External Actions section"

compare_count "External Actions" "$expected_total"
compare_count "Blockers" "$expected_blockers"
compare_count "Warnings" "$expected_warnings"

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

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'Release input TODO matches external readiness actions.\n'
