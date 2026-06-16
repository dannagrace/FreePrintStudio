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

awk -F '\t' '
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

require_file "$index_path" "private release input template index"
require_file "$release_env_path" "release.env private input template"
require_file "$manual_env_path" "manual-release-verification.env private input template"

require_contains "$index_path" "# FreePrint Studio Private Release Input Templates" "private release input template index title"
require_contains "$index_path" "private-release-input-templates/" "private release input template output directory reference"
require_contains "$index_path" "Scripts/install_private_release_input_templates.sh --source-dir private-release-input-templates --target-dir Config" "safe installer command"
require_not_contains "$index_path" "cp private-release-input-templates/" "unsafe manual copy instructions"

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
