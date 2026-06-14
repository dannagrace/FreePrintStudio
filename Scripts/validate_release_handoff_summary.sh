#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: %s <release-handoff-summary.tsv>\n' "$0" >&2
  exit 2
fi

summary_path="$1"

if [[ ! -s "$summary_path" ]]; then
  printf 'FAIL: release handoff summary is missing or empty: %s\n' "$summary_path"
  exit 1
fi

header="$(sed -n '1p' "$summary_path")"
if [[ "$header" != $'key\tvalue' ]]; then
  printf 'FAIL: release handoff summary has unexpected header: %s\n' "$header"
  exit 1
fi

summary_value() {
  local key="$1"
  awk -F '\t' -v key="$key" 'NR > 1 && $1 == key { print $2; found = 1; exit } END { if (!found) exit 1 }' "$summary_path"
}

failures=0

require_key() {
  local key="$1"
  local value
  if ! value="$(summary_value "$key")"; then
    printf 'FAIL: release handoff summary is missing required key: %s\n' "$key"
    failures=$((failures + 1))
    return
  fi
  if [[ -z "$value" ]]; then
    printf 'FAIL: release handoff summary key has an empty value: %s\n' "$key"
    failures=$((failures + 1))
  fi
}

require_file_key() {
  local key="$1"
  local value
  require_key "$key"
  value="$(summary_value "$key" 2>/dev/null || true)"
  if [[ -n "$value" && ! -s "$value" ]]; then
    printf 'FAIL: release handoff summary %s points to a missing or empty file: %s\n' "$key" "$value"
    failures=$((failures + 1))
  fi
}

require_integer_key() {
  local key="$1"
  local value
  require_key "$key"
  value="$(summary_value "$key" 2>/dev/null || true)"
  if [[ -n "$value" && ! "$value" =~ ^[0-9]+$ ]]; then
    printf 'FAIL: release handoff summary %s must be a non-negative integer (got: %s)\n' "$key" "$value"
    failures=$((failures + 1))
  fi
}

require_signed_integer_key() {
  local key="$1"
  local value
  require_key "$key"
  value="$(summary_value "$key" 2>/dev/null || true)"
  if [[ -n "$value" && ! "$value" =~ ^-?[0-9]+$ ]]; then
    printf 'FAIL: release handoff summary %s must be an integer (got: %s)\n' "$key" "$value"
    failures=$((failures + 1))
  fi
}

readiness_count() {
  local readiness_path="$1"
  local prefix="$2"
  grep -c "^${prefix}:" "$readiness_path" || true
}

external_action_count() {
  local actions_path="$1"
  local severity="${2:-}"
  awk -F '\t' -v severity="$severity" '
    NR == 1 {
      for (i = 1; i <= NF; i++) {
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

compare_count() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(summary_value "$key" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: release handoff summary %s mismatch (summary: %s; actual: %s)\n' \
      "$key" "${actual:-missing}" "$expected"
    failures=$((failures + 1))
  fi
}

for key in \
  generated_at \
  handoff_status \
  local_head \
  packet_dir \
  packet_git_commit \
  packet_github_sha \
  packet_github_run_url \
  readiness_status; do
  require_key "$key"
done

require_file_key "handoff_brief"
require_file_key "release_input_todo"
require_file_key "ci_readiness_log"
require_file_key "external_readiness_actions"
require_file_key "readiness_log"

for key in \
  ci_readiness_blockers \
  ci_readiness_warnings \
  external_action_total \
  external_action_blockers \
  external_action_warnings \
  readiness_blockers \
  readiness_warnings; do
  require_integer_key "$key"
done

for key in \
  ci_local_readiness_blocker_delta \
  ci_local_readiness_warning_delta; do
  require_signed_integer_key "$key"
done

local_head="$(summary_value "local_head" 2>/dev/null || true)"
packet_git_commit="$(summary_value "packet_git_commit" 2>/dev/null || true)"
packet_github_sha="$(summary_value "packet_github_sha" 2>/dev/null || true)"

if [[ -n "$local_head" && -n "$packet_git_commit" && "$local_head" != "$packet_git_commit" ]]; then
  printf 'FAIL: release handoff summary packet_git_commit must match local_head (local_head: %s; packet_git_commit: %s)\n' \
    "$local_head" "$packet_git_commit"
  failures=$((failures + 1))
fi

if [[ -n "$local_head" && -n "$packet_github_sha" && "$local_head" != "$packet_github_sha" ]]; then
  printf 'FAIL: release handoff summary packet_github_sha must match local_head (local_head: %s; packet_github_sha: %s)\n' \
    "$local_head" "$packet_github_sha"
  failures=$((failures + 1))
fi

ci_readiness_log="$(summary_value "ci_readiness_log" 2>/dev/null || true)"
readiness_log="$(summary_value "readiness_log" 2>/dev/null || true)"
external_actions_path="$(summary_value "external_readiness_actions" 2>/dev/null || true)"

if [[ -s "$ci_readiness_log" ]]; then
  compare_count "ci_readiness_blockers" "$(readiness_count "$ci_readiness_log" "BLOCKED")"
  compare_count "ci_readiness_warnings" "$(readiness_count "$ci_readiness_log" "WARN")"
fi

if [[ -s "$readiness_log" ]]; then
  compare_count "readiness_blockers" "$(readiness_count "$readiness_log" "BLOCKED")"
  compare_count "readiness_warnings" "$(readiness_count "$readiness_log" "WARN")"
fi

ci_readiness_blockers="$(summary_value "ci_readiness_blockers" 2>/dev/null || true)"
ci_readiness_warnings="$(summary_value "ci_readiness_warnings" 2>/dev/null || true)"
readiness_blockers="$(summary_value "readiness_blockers" 2>/dev/null || true)"
readiness_warnings="$(summary_value "readiness_warnings" 2>/dev/null || true)"
if [[ "$ci_readiness_blockers" =~ ^[0-9]+$ && "$readiness_blockers" =~ ^[0-9]+$ ]]; then
  compare_count "ci_local_readiness_blocker_delta" "$((readiness_blockers - ci_readiness_blockers))"
fi
if [[ "$ci_readiness_warnings" =~ ^[0-9]+$ && "$readiness_warnings" =~ ^[0-9]+$ ]]; then
  compare_count "ci_local_readiness_warning_delta" "$((readiness_warnings - ci_readiness_warnings))"
fi

if [[ -s "$external_actions_path" ]]; then
  compare_count "external_action_total" "$(external_action_count "$external_actions_path")"
  compare_count "external_action_blockers" "$(external_action_count "$external_actions_path" "blocker")"
  compare_count "external_action_warnings" "$(external_action_count "$external_actions_path" "warning")"
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'Release handoff summary is internally consistent.\n'
