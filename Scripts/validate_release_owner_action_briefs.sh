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
    owner_name = $(columns["owner"])
    severity = $(columns["severity"])
    validation_command = $(columns["validation_command"])
    file_name = owner_file(owner_name)
    owner_counts[owner_name] += 1
    if (validation_command ~ /PROCESSED_BUILD_NUMBER/) {
      owner_selected_build_placeholder[owner_name] = 1
    }
    if (!(owner_name in owner_seen)) {
      owner_seen[owner_name] = 1
      owner_order_count += 1
      owner_order[owner_order_count] = owner_name
    }
    if (severity == "blocker") {
      owner_blocker_counts[owner_name] += 1
    } else if (severity == "warning") {
      owner_warning_counts[owner_name] += 1
    }
    expected_row = "| " \
      markdown_cell($(columns["category"])) " | " \
      markdown_cell(severity) " | " \
      code_text(markdown_cell($(columns["field"]))) " | " \
      code_text(markdown_cell($(columns["target"]))) " | " \
      markdown_cell($(columns["item"])) " | " \
      markdown_cell($(columns["next_action"])) " | " \
      code_text(markdown_cell(validation_command)) " |"
    print file_name "\t" $(columns["field"]) "\t" $(columns["item"]) "\t" expected_row >expected_details
  }

  END {
    if (total == 0) {
      fail("external readiness actions file has no action rows")
    }
    for (owner_index = 1; owner_index <= owner_order_count; owner_index += 1) {
      owner_name = owner_order[owner_index]
      print owner_name "\t" owner_file(owner_name) "\t" owner_counts[owner_name] "\t" owner_blocker_counts[owner_name] + 0 "\t" owner_warning_counts[owner_name] + 0 "\t" owner_selected_build_placeholder[owner_name] + 0 >expected_owners
    }
  }
' "$actions_path" || {
  exit 1
}

index_path="$owner_dir/index.md"
require_file "$index_path" "owner action brief index"
require_contains_file "$index_path" "# FreePrint Studio Release Owner Action Briefs" "owner action brief index title"

while IFS=$'\t' read -r owner_name file_name actions blockers warnings selected_build_placeholder; do
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
  if [[ "${selected_build_placeholder:-0}" == "1" ]]; then
    require_contains_file "$owner_path" "$selected_build_placeholder_guidance" "selected-build placeholder replacement guidance for $owner_name"
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

printf 'Release owner action briefs match external readiness actions.\n'
