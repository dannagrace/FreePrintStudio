#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: %s <release-provenance.tsv>\n' "$0" >&2
  exit 2
fi

provenance_path="$1"

if [[ ! -s "$provenance_path" ]]; then
  printf 'FAIL: release provenance is missing or empty: %s\n' "$provenance_path"
  exit 1
fi

header="$(sed -n '1p' "$provenance_path")"
if [[ "$header" != $'key\tvalue' ]]; then
  printf 'FAIL: release provenance has unexpected header: %s\n' "$header"
  exit 1
fi

value_for_key() {
  local key="$1"
  awk -F '\t' -v key="$key" 'NR > 1 && $1 == key { print $2; found = 1; exit } END { if (!found) exit 1 }' "$provenance_path"
}

failures=0

require_key() {
  local key="$1"
  local value
  if ! value="$(value_for_key "$key")"; then
    printf 'FAIL: release provenance is missing required key: %s\n' "$key"
    failures=$((failures + 1))
    return
  fi
  if [[ -z "$value" ]]; then
    printf 'FAIL: release provenance key has an empty value: %s\n' "$key"
    failures=$((failures + 1))
  fi
}

require_key "generated_at"
require_key "git_commit"
require_key "git_branch"
require_key "git_remote_origin"
require_key "git_status"
require_key "git_dirty_count"
require_key "github_run_url"
require_key "github_ref"
require_key "github_sha"

git_status="$(value_for_key "git_status" 2>/dev/null || true)"
git_dirty_count="$(value_for_key "git_dirty_count" 2>/dev/null || true)"
git_commit="$(value_for_key "git_commit" 2>/dev/null || true)"
git_branch="$(value_for_key "git_branch" 2>/dev/null || true)"

if [[ "$git_status" != "clean" ]]; then
  printf 'FAIL: release provenance git_status must be clean before App Store handoff (got: %s)\n' "${git_status:-missing}"
  failures=$((failures + 1))
fi

if [[ "$git_dirty_count" != "0" ]]; then
  printf 'FAIL: release provenance git_dirty_count must be 0 before App Store handoff (got: %s)\n' "${git_dirty_count:-missing}"
  failures=$((failures + 1))
fi

if [[ "$git_commit" == "unknown" ]]; then
  printf 'FAIL: release provenance git_commit must record a real source commit\n'
  failures=$((failures + 1))
fi

if [[ "$git_branch" == "unknown" ]]; then
  printf 'FAIL: release provenance git_branch must record a real source branch\n'
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'Release provenance is clean and complete.\n'
