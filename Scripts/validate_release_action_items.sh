#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  printf 'Usage: %s <readiness.txt> <external-readiness-actions.tsv> <ACTION_ITEMS.md>\n' "$0" >&2
  exit 2
fi

readiness_path="$1"
actions_path="$2"
action_items_path="$3"

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
  if ! grep -qF "$pattern" "$action_items_path"; then
    fail "$description is missing from ACTION_ITEMS.md"
  fi
}

action_items_count() {
  local label="$1"
  sed -nE "s/^- ${label}: ([0-9]+)$/\\1/p" "$action_items_path" | tail -n 1
}

compare_count() {
  local label="$1"
  local expected="$2"
  local actual
  actual="$(action_items_count "$label")"
  if [[ -z "$actual" ]]; then
    fail "$label count is missing from ACTION_ITEMS.md"
    return
  fi
  if [[ "$actual" != "$expected" ]]; then
    fail "$label count mismatch (ACTION_ITEMS.md: $actual; external-readiness-actions.tsv: $expected)"
  fi
}

section_has_bullet() {
  local section="$1"
  local item="$2"
  awk -v section="$section" -v bullet="- $item" '
    $0 == section {
      in_section = 1
      next
    }
    in_section && /^## / {
      in_section = 0
    }
    in_section && $0 == bullet {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }
  ' "$action_items_path"
}

require_file "$readiness_path" "readiness input"
require_file "$actions_path" "external readiness actions input"
require_file "$action_items_path" "release action items input"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

expected_action_items="$temp_dir/expected-action-items.tsv"
action_summary="$temp_dir/action-summary.tsv"

awk -F '\t' -v expected_action_items="$expected_action_items" '
  NR == 1 {
    for (i = 1; i <= NF; i += 1) {
      columns[$i] = i
    }
    required[1] = "severity"
    required[2] = "item"
    for (i = 1; i <= 2; i += 1) {
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
    item = $(columns["item"])
    if (severity == "blocker") {
      blockers += 1
      print severity "\t" item >expected_action_items
    } else if (severity == "warning") {
      warnings += 1
      print severity "\t" item >expected_action_items
    }
  }
  END {
    if (total == 0) {
      print "FAIL: external readiness actions file has no action rows" >"/dev/stderr"
      exit 4
    }
    printf "blockers\t%s\n", blockers + 0
    printf "warnings\t%s\n", warnings + 0
  }
' "$actions_path" >"$action_summary" || {
  exit 1
}

expected_blockers="$(awk -F '\t' '$1 == "blockers" { print $2 }' "$action_summary")"
expected_warnings="$(awk -F '\t' '$1 == "warnings" { print $2 }' "$action_summary")"

if ! Scripts/validate_external_readiness_actions.sh "$readiness_path" "$actions_path"; then
  failures=$((failures + 1))
fi

require_contains "# FreePrint Studio Release Action Items" "release action items title"
require_contains "## Readiness Blockers" "Readiness Blockers section"
require_contains "## Readiness Warnings" "Readiness Warnings section"
require_contains "## External Values To Provide" "External Values To Provide section"
require_contains "## Command Order" "Command Order section"

compare_count "Readiness Blockers" "$expected_blockers"
compare_count "Readiness Warnings" "$expected_warnings"

while IFS=$'\t' read -r severity item; do
  [[ -n "${severity:-}${item:-}" ]] || continue
  if [[ "$severity" == "blocker" ]]; then
    if ! section_has_bullet "## Readiness Blockers" "$item"; then
      fail "action item bullet is missing from Readiness Blockers: $item"
    fi
  elif [[ "$severity" == "warning" ]]; then
    if ! section_has_bullet "## Readiness Warnings" "$item"; then
      fail "action item bullet is missing from Readiness Warnings: $item"
    fi
  fi
done <"$expected_action_items"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'Release action items match external readiness actions.\n'
