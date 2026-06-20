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

require_directory_key() {
  local key="$1"
  local value
  require_key "$key"
  value="$(summary_value "$key" 2>/dev/null || true)"
  if [[ -n "$value" && ! -d "$value" ]]; then
    printf 'FAIL: release handoff summary %s points to a missing directory: %s\n' "$key" "$value"
    failures=$((failures + 1))
  fi
}

require_owner_input_status_dir() {
  local value
  local index_path
  local header
  require_directory_key "owner_input_status_dir"
  value="$(summary_value "owner_input_status_dir" 2>/dev/null || true)"
  [[ -n "$value" && -d "$value" ]] || return

  index_path="$value/index.tsv"
  if [[ ! -s "$index_path" ]]; then
    printf 'FAIL: release handoff summary owner_input_status_dir is missing index.tsv: %s\n' "$index_path"
    failures=$((failures + 1))
    return
  fi

  header="$(sed -n '1p' "$index_path")"
  if [[ "$header" != $'owner_slug\towner\tstatus\tpath\tcommand' ]]; then
    printf 'FAIL: release handoff owner input status index has unexpected header: %s\n' "$header"
    failures=$((failures + 1))
  fi

  while IFS=$'\t' read -r owner_slug owner status report_path command; do
    [[ "$owner_slug" != "owner_slug" ]] || continue
    [[ -n "${owner_slug:-}${owner:-}${status:-}${report_path:-}${command:-}" ]] || continue
    if [[ ! -s "$report_path" ]]; then
      printf 'FAIL: release handoff owner input status report is missing or empty for %s: %s\n' "$owner" "$report_path"
      failures=$((failures + 1))
    fi
  done <"$index_path"
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

release_input_summary_count() {
  local status_path="$1"
  local field="$2"
  local summary_line

  summary_line="$(grep -E '^Summary: [0-9]+ missing required release input check\(s\), [0-9]+ missing field/action item\(s\)\.$' "$status_path" | tail -n 1 || true)"
  if [[ -z "$summary_line" ]]; then
    printf 'missing'
    return
  fi

  case "$field" in
    checks)
      sed -E 's/^Summary: ([0-9]+) missing required release input check\(s\), ([0-9]+) missing field\/action item\(s\)\.$/\1/' <<<"$summary_line"
      ;;
    fields)
      sed -E 's/^Summary: ([0-9]+) missing required release input check\(s\), ([0-9]+) missing field\/action item\(s\)\.$/\2/' <<<"$summary_line"
      ;;
    *)
      printf 'missing'
      ;;
  esac
}

phase_plan_metadata_count() {
  local plan_path="$1"
  local label="$2"
  local prefix

  printf -v prefix -- '- %s: `' "$label"
  awk -v label="$prefix" '
    index($0, label) == 1 {
      value = substr($0, length(label) + 1)
      sub(/`$/, "", value)
      print value
      found = 1
      exit
    }
    END {
      if (!found) {
        print "missing"
      }
    }
  ' "$plan_path"
}

phase_plan_summary_count() {
  local plan_path="$1"
  local field="$2"

  awk -F '|' -v field="$field" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    $0 == "## Phase Summary" {
      in_section = 1
      next
    }
    in_section && /^## / {
      in_section = 0
    }
    in_section && $2 ~ /^[[:space:]]*Phase [0-9]+ - / {
      actions += trim($3)
      blockers += trim($4)
      warnings += trim($5)
    }
    END {
      if (field == "actions") {
        print actions + 0
      } else if (field == "blockers") {
        print blockers + 0
      } else if (field == "warnings") {
        print warnings + 0
      } else {
        print "missing"
      }
    }
  ' "$plan_path"
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
require_file_key "release_input_status_path"
require_file_key "release_input_todo"
require_file_key "release_phase_plan"
require_file_key "ci_readiness_log"
require_file_key "external_readiness_actions"
require_file_key "readiness_log"
require_owner_input_status_dir

for key in \
  ci_readiness_blockers \
  ci_readiness_warnings \
  release_input_status \
  release_input_missing_checks \
  release_input_missing_fields \
  release_phase_plan_total_actions \
  release_phase_plan_total_blockers \
  release_phase_plan_total_warnings \
  release_phase_plan_final_submission_guard_actions \
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
release_input_status_path="$(summary_value "release_input_status_path" 2>/dev/null || true)"
release_phase_plan_path="$(summary_value "release_phase_plan" 2>/dev/null || true)"

if [[ -s "$ci_readiness_log" ]]; then
  compare_count "ci_readiness_blockers" "$(readiness_count "$ci_readiness_log" "BLOCKED")"
  compare_count "ci_readiness_warnings" "$(readiness_count "$ci_readiness_log" "WARN")"
fi

if [[ -s "$readiness_log" ]]; then
  compare_count "readiness_blockers" "$(readiness_count "$readiness_log" "BLOCKED")"
  compare_count "readiness_warnings" "$(readiness_count "$readiness_log" "WARN")"
fi

if [[ -s "$release_input_status_path" ]]; then
  compare_count "release_input_missing_checks" "$(release_input_summary_count "$release_input_status_path" checks)"
  compare_count "release_input_missing_fields" "$(release_input_summary_count "$release_input_status_path" fields)"
fi

if [[ -s "$release_phase_plan_path" ]]; then
  compare_count "release_phase_plan_total_actions" "$(phase_plan_summary_count "$release_phase_plan_path" actions)"
  compare_count "release_phase_plan_total_blockers" "$(phase_plan_summary_count "$release_phase_plan_path" blockers)"
  compare_count "release_phase_plan_total_warnings" "$(phase_plan_summary_count "$release_phase_plan_path" warnings)"
  compare_count "release_phase_plan_final_submission_guard_actions" "$(phase_plan_metadata_count "$release_phase_plan_path" "Final Submission Guard Actions")"
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
