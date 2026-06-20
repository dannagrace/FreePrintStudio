#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

packet_dir="${FREEPRINTSTUDIO_HANDOFF_PACKET_DIR:-build/CISubmissionPacket}"
readiness_log="${FREEPRINTSTUDIO_HANDOFF_READINESS_LOG:-build/release-handoff-readiness.txt}"
summary_path="${FREEPRINTSTUDIO_HANDOFF_SUMMARY_PATH:-build/release-handoff-summary.tsv}"
brief_path="${FREEPRINTSTUDIO_HANDOFF_BRIEF_PATH:-build/release-handoff-brief.md}"
release_input_status_path="${FREEPRINTSTUDIO_HANDOFF_RELEASE_INPUT_STATUS_PATH:-build/release-handoff-input-status.txt}"
owner_input_status_dir="${FREEPRINTSTUDIO_HANDOFF_OWNER_INPUT_STATUS_DIR:-build/release-owner-input-status}"
input_todo_path="${FREEPRINTSTUDIO_HANDOFF_INPUT_TODO_PATH:-build/release-input-todo.md}"
phase_plan_path="${FREEPRINTSTUDIO_HANDOFF_PHASE_PLAN_PATH:-build/release-phase-plan.md}"
owner_action_dir="${FREEPRINTSTUDIO_HANDOFF_OWNER_ACTION_DIR:-build/release-owner-actions}"
private_template_dir="${FREEPRINTSTUDIO_HANDOFF_PRIVATE_TEMPLATE_DIR:-build/private-release-input-templates}"
ci_readiness_log="$packet_dir/readiness.txt"
external_actions_path="$packet_dir/external-readiness-actions.tsv"

usage() {
  cat <<'EOF'
Usage: Scripts/preflight_release_handoff.sh

Runs the final local handoff checks before release ownership moves to App Store
Connect account work:
  - requires a clean local git worktree
  - downloads and validates the latest successful CI submission packet
  - verifies the downloaded packet provenance matches the local HEAD
  - validates the CI external-readiness-actions.tsv manifest
  - writes a redacted release input status report
  - writes owner-scoped redacted release input status reports
  - runs the App Store readiness audit and surfaces remaining blockers
  - writes build/release-handoff-summary.tsv with CI packet and readiness status
  - writes build/release-handoff-brief.md for release owner handoff
  - writes build/release-input-todo.md with fillable private release input fields
  - writes build/release-phase-plan.md with phase-ordered release work
  - writes build/release-owner-actions/ with per-owner action briefs
  - writes build/private-release-input-templates/ with blank private env starters
EOF
}

provenance_value() {
  local key="$1"
  awk -F '\t' -v key="$key" 'NR > 1 && $1 == key { print $2; found = 1; exit } END { if (!found) exit 1 }' \
    "$packet_dir/release-provenance.tsv"
}

release_input_summary_value() {
  local path="$1"
  local field="$2"
  local summary_line

  if [[ ! -s "$path" ]]; then
    printf 'missing'
    return
  fi

  summary_line="$(grep -E '^Summary: [0-9]+ missing required release input check\(s\), [0-9]+ missing field/action item\(s\)\.$' "$path" | tail -n 1 || true)"
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

phase_plan_metadata_value() {
  local path="$1"
  local label="$2"
  local prefix

  if [[ ! -s "$path" ]]; then
    printf 'missing'
    return
  fi

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
        exit 1
      }
    }
  ' "$path" 2>/dev/null || printf 'missing'
}

phase_plan_summary_value() {
  local path="$1"
  local field="$2"

  if [[ ! -s "$path" ]]; then
    printf 'missing'
    return
  fi

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
  ' "$path"
}

external_action_count() {
  local severity="${1:-}"
  if [[ ! -s "$external_actions_path" ]]; then
    printf '0'
    return
  fi
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
  ' "$external_actions_path"
}

markdown_cell() {
  local value="$1"
  value="${value//|/\\|}"
  value="${value//\`/\\\`}"
  printf '%s' "$value"
}

owner_slug() {
  local value="$1"
  local slug
  slug="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "$slug" ]]; then
    slug="owner"
  fi
  printf '%s' "$slug"
}

owner_status_command() {
  local owner="$1"
  printf 'Scripts/print_release_input_status.sh --strict --owner %s' "$(owner_slug "$owner")"
}

list_handoff_owners() {
  local final_guard_actions="$1"

  if [[ -s "$external_actions_path" ]]; then
    awk -F '\t' -v final_guard_actions="$final_guard_actions" '
      NR == 1 {
        for (i = 1; i <= NF; i++) {
          columns[$i] = i
        }
        next
      }
      $1 != "" {
        owner = $(columns["owner"])
        if (!(owner in seen)) {
          seen[owner] = 1
          owner_order[++owner_count] = owner
        }
      }
      END {
        final_guard_actions += 0
        if (final_guard_actions > 0 && !("Release owner" in seen)) {
          owner_order[++owner_count] = "Release owner"
        }
        for (owner_index = 1; owner_index <= owner_count; owner_index += 1) {
          print owner_order[owner_index]
        }
      }
    ' "$external_actions_path"
  else
    printf 'Release owner\n'
  fi
}

readiness_signal_lines() {
  local path="$1"
  if [[ -s "$path" ]]; then
    grep -E '^(BLOCKED|WARN):' "$path" | LC_ALL=C sort || true
  fi
}

write_readiness_delta_section() {
  local title="$1"
  local source_path="$2"
  local comparison_path="$3"
  local empty_text="$4"
  local delta_lines

  printf '## %s\n\n' "$title"

  delta_lines="$(comm -23 <(readiness_signal_lines "$source_path") <(readiness_signal_lines "$comparison_path"))"
  if [[ -z "$delta_lines" ]]; then
    printf '%s\n\n' "$empty_text"
    return
  fi

  printf '| Severity | Item |\n'
  printf '| --- | --- |\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    local severity="${line%%:*}"
    local item="${line#*: }"
    printf '| %s | %s |\n' "$(markdown_cell "$severity")" "$(markdown_cell "$item")"
  done <<<"$delta_lines"
  printf '\n'
}

write_owner_status_commands() {
  local final_guard_actions="$1"

  printf '## Owner-Scoped Status Commands\n\n'
  printf 'Use these redacted commands when one handoff owner needs to check only their assigned release inputs.\n\n'
  printf '| Owner | Command |\n'
  printf '| --- | --- |\n'
  list_handoff_owners "$final_guard_actions" | while IFS= read -r owner; do
    [[ -n "$owner" ]] || continue
    local escaped_owner
    local escaped_command
    escaped_owner="$(markdown_cell "$owner")"
    escaped_command="$(markdown_cell "$(owner_status_command "$owner")")"
    printf '| `%s` | `%s` |\n' "$escaped_owner" "$escaped_command"
  done
  printf '\n'
}

write_owner_input_status_reports() {
  local final_guard_actions="$1"
  local index_path="$owner_input_status_dir/index.tsv"

  rm -rf "$owner_input_status_dir"
  mkdir -p "$owner_input_status_dir"
  printf 'owner_slug\towner\tstatus\tpath\tcommand\n' >"$index_path"

  list_handoff_owners "$final_guard_actions" | while IFS= read -r owner; do
    [[ -n "$owner" ]] || continue
    local command
    local report_path
    local slug
    local status
    slug="$(owner_slug "$owner")"
    report_path="$owner_input_status_dir/$slug.txt"
    command="$(owner_status_command "$owner")"
    set +e
    Scripts/print_release_input_status.sh --strict --owner "$slug" >"$report_path" 2>&1
    status="$?"
    set -e
    printf '%s\t%s\t%s\t%s\t%s\n' "$slug" "$owner" "$status" "$report_path" "$command" >>"$index_path"
  done
}

write_owner_input_status_reports_section() {
  local index_path="$owner_input_status_dir/index.tsv"

  printf '## Owner-Scoped Status Reports\n\n'
  printf 'These redacted reports are generated during handoff so each owner can review current missing inputs without re-running commands first.\n\n'
  printf '| Owner | Status | Report | Command |\n'
  printf '| --- | ---: | --- | --- |\n'
  if [[ -s "$index_path" ]]; then
    while IFS=$'\t' read -r slug owner status report_path command; do
      [[ "$slug" != "owner_slug" ]] || continue
      [[ -n "${owner:-}" ]] || continue
      printf '| `%s` | `%s` | `%s` | `%s` |\n' \
        "$(markdown_cell "$owner")" \
        "$(markdown_cell "$status")" \
        "$(markdown_cell "$report_path")" \
        "$(markdown_cell "$command")"
    done <"$index_path"
  else
    printf '| `Release owner` | `missing` | `%s/release-owner.txt` | `%s` |\n' \
      "$(markdown_cell "$owner_input_status_dir")" \
      "$(markdown_cell "$(owner_status_command "Release owner")")"
  fi
  printf '\n'
}

write_handoff_summary() {
  local handoff_status="$1"
  local packet_git_commit
  local packet_github_run_url
  local packet_github_sha
  local ci_readiness_blockers
  local ci_readiness_warnings
  local readiness_blockers
  local readiness_warnings
  local external_action_total
  local external_action_blockers
  local external_action_warnings
  local release_input_missing_checks
  local release_input_missing_fields
  local release_phase_plan_total_actions
  local release_phase_plan_total_blockers
  local release_phase_plan_total_warnings
  local release_phase_plan_final_submission_guard_actions
  local ci_local_readiness_blocker_delta
  local ci_local_readiness_warning_delta

  packet_git_commit="$(provenance_value git_commit 2>/dev/null || printf 'missing')"
  packet_github_run_url="$(provenance_value github_run_url 2>/dev/null || printf 'missing')"
  packet_github_sha="$(provenance_value github_sha 2>/dev/null || printf 'missing')"
  ci_readiness_blockers="$(grep -c '^BLOCKED:' "$ci_readiness_log" || true)"
  ci_readiness_warnings="$(grep -c '^WARN:' "$ci_readiness_log" || true)"
  readiness_blockers="$(grep -c '^BLOCKED:' "$readiness_log" || true)"
  readiness_warnings="$(grep -c '^WARN:' "$readiness_log" || true)"
  external_action_total="$(external_action_count)"
  external_action_blockers="$(external_action_count blocker)"
  external_action_warnings="$(external_action_count warning)"
  release_input_missing_checks="$(release_input_summary_value "$release_input_status_path" checks)"
  release_input_missing_fields="$(release_input_summary_value "$release_input_status_path" fields)"
  release_phase_plan_total_actions="$(phase_plan_summary_value "$phase_plan_path" actions)"
  release_phase_plan_total_blockers="$(phase_plan_summary_value "$phase_plan_path" blockers)"
  release_phase_plan_total_warnings="$(phase_plan_summary_value "$phase_plan_path" warnings)"
  release_phase_plan_final_submission_guard_actions="$(phase_plan_metadata_value "$phase_plan_path" "Final Submission Guard Actions")"
  ci_local_readiness_blocker_delta="$((readiness_blockers - ci_readiness_blockers))"
  ci_local_readiness_warning_delta="$((readiness_warnings - ci_readiness_warnings))"

  mkdir -p "$(dirname "$summary_path")"
  {
    printf 'key\tvalue\n'
    printf 'generated_at\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'handoff_status\t%s\n' "$handoff_status"
    printf 'local_head\t%s\n' "$local_head"
    printf 'packet_dir\t%s\n' "$packet_dir"
    printf 'packet_git_commit\t%s\n' "$packet_git_commit"
    printf 'packet_github_sha\t%s\n' "$packet_github_sha"
    printf 'packet_github_run_url\t%s\n' "$packet_github_run_url"
    printf 'handoff_brief\t%s\n' "$brief_path"
    printf 'release_input_status_path\t%s\n' "$release_input_status_path"
    printf 'release_input_status\t%s\n' "$release_input_status"
    printf 'release_input_missing_checks\t%s\n' "$release_input_missing_checks"
    printf 'release_input_missing_fields\t%s\n' "$release_input_missing_fields"
    printf 'owner_input_status_dir\t%s\n' "$owner_input_status_dir"
    printf 'release_input_todo\t%s\n' "$input_todo_path"
    printf 'release_phase_plan\t%s\n' "$phase_plan_path"
    printf 'release_phase_plan_total_actions\t%s\n' "$release_phase_plan_total_actions"
    printf 'release_phase_plan_total_blockers\t%s\n' "$release_phase_plan_total_blockers"
    printf 'release_phase_plan_total_warnings\t%s\n' "$release_phase_plan_total_warnings"
    printf 'release_phase_plan_final_submission_guard_actions\t%s\n' "$release_phase_plan_final_submission_guard_actions"
    printf 'owner_action_dir\t%s\n' "$owner_action_dir"
    printf 'private_template_dir\t%s\n' "$private_template_dir"
    printf 'ci_readiness_log\t%s\n' "$ci_readiness_log"
    printf 'ci_readiness_blockers\t%s\n' "$ci_readiness_blockers"
    printf 'ci_readiness_warnings\t%s\n' "$ci_readiness_warnings"
    printf 'external_readiness_actions\t%s\n' "$external_actions_path"
    printf 'external_action_total\t%s\n' "$external_action_total"
    printf 'external_action_blockers\t%s\n' "$external_action_blockers"
    printf 'external_action_warnings\t%s\n' "$external_action_warnings"
    printf 'readiness_log\t%s\n' "$readiness_log"
    printf 'readiness_status\t%s\n' "$readiness_status"
    printf 'readiness_blockers\t%s\n' "$readiness_blockers"
    printf 'readiness_warnings\t%s\n' "$readiness_warnings"
    printf 'ci_local_readiness_blocker_delta\t%s\n' "$ci_local_readiness_blocker_delta"
    printf 'ci_local_readiness_warning_delta\t%s\n' "$ci_local_readiness_warning_delta"
  } >"$summary_path"
}

write_handoff_brief() {
  local handoff_status="$1"
  local packet_git_commit
  local packet_github_run_url
  local packet_github_sha
  local ci_readiness_blockers
  local ci_readiness_warnings
  local readiness_blockers
  local readiness_warnings
  local external_action_total
  local external_action_blockers
  local external_action_warnings
  local release_input_missing_checks
  local release_input_missing_fields
  local release_phase_plan_total_actions
  local release_phase_plan_total_blockers
  local release_phase_plan_total_warnings
  local release_phase_plan_final_submission_guard_actions
  local ci_local_readiness_blocker_delta
  local ci_local_readiness_warning_delta

  packet_git_commit="$(provenance_value git_commit 2>/dev/null || printf 'missing')"
  packet_github_run_url="$(provenance_value github_run_url 2>/dev/null || printf 'missing')"
  packet_github_sha="$(provenance_value github_sha 2>/dev/null || printf 'missing')"
  ci_readiness_blockers="$(grep -c '^BLOCKED:' "$ci_readiness_log" || true)"
  ci_readiness_warnings="$(grep -c '^WARN:' "$ci_readiness_log" || true)"
  readiness_blockers="$(grep -c '^BLOCKED:' "$readiness_log" || true)"
  readiness_warnings="$(grep -c '^WARN:' "$readiness_log" || true)"
  external_action_total="$(external_action_count)"
  external_action_blockers="$(external_action_count blocker)"
  external_action_warnings="$(external_action_count warning)"
  release_input_missing_checks="$(release_input_summary_value "$release_input_status_path" checks)"
  release_input_missing_fields="$(release_input_summary_value "$release_input_status_path" fields)"
  release_phase_plan_total_actions="$(phase_plan_summary_value "$phase_plan_path" actions)"
  release_phase_plan_total_blockers="$(phase_plan_summary_value "$phase_plan_path" blockers)"
  release_phase_plan_total_warnings="$(phase_plan_summary_value "$phase_plan_path" warnings)"
  release_phase_plan_final_submission_guard_actions="$(phase_plan_metadata_value "$phase_plan_path" "Final Submission Guard Actions")"
  ci_local_readiness_blocker_delta="$((readiness_blockers - ci_readiness_blockers))"
  ci_local_readiness_warning_delta="$((readiness_warnings - ci_readiness_warnings))"

  mkdir -p "$(dirname "$brief_path")"
  {
    printf '# FreePrint Studio Release Handoff Brief\n\n'
    printf -- '- Generated At: `%s`\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf -- '- Handoff Status: `%s`\n' "$handoff_status"
    printf -- '- Local HEAD: `%s`\n' "$local_head"
    printf -- '- CI Packet Commit: `%s`\n' "$packet_git_commit"
    printf -- '- CI Packet SHA: `%s`\n' "$packet_github_sha"
    printf -- '- CI Run: %s\n\n' "$packet_github_run_url"

    printf '## Readiness Counts\n\n'
    printf '| Source | Blockers | Warnings | Log |\n'
    printf '| --- | ---: | ---: | --- |\n'
    printf '| CI packet | %s | %s | `%s` |\n' "$ci_readiness_blockers" "$ci_readiness_warnings" "$ci_readiness_log"
    printf '| Local preflight | %s | %s | `%s` |\n' "$readiness_blockers" "$readiness_warnings" "$readiness_log"
    printf '| External actions | %s | %s | `%s` (%s total) |\n\n' "$external_action_blockers" "$external_action_warnings" "$external_actions_path" "$external_action_total"

    printf '## Release Input Status\n\n'
    printf '| Metric | Value |\n'
    printf '| --- | --- |\n'
    printf '| Status | `%s` |\n' "$release_input_status"
    printf '| Missing required release input checks | %s |\n' "$release_input_missing_checks"
    printf '| Missing field/action items | %s |\n' "$release_input_missing_fields"
    printf '| Log | `%s` |\n\n' "$release_input_status_path"
    printf 'This redacted status includes final submission guards such as `APP_STORE_BUILD_NUMBER` and `CONFIRM_SUBMIT_FOR_REVIEW`, so it can show required final handoff inputs that are not readiness blockers yet.\n\n'

    printf '## Release Phase Plan Status\n\n'
    printf '| Metric | Value |\n'
    printf '| --- | ---: |\n'
    printf '| Total phase plan actions | %s |\n' "$release_phase_plan_total_actions"
    printf '| Total phase plan blockers | %s |\n' "$release_phase_plan_total_blockers"
    printf '| Total phase plan warnings | %s |\n' "$release_phase_plan_total_warnings"
    printf '| Final submission guard actions | %s |\n' "$release_phase_plan_final_submission_guard_actions"
    printf '| Plan | `%s` |\n\n' "$phase_plan_path"
    printf 'The phase plan count includes derived final submission guard actions that are not present in the CI external readiness manifest.\n\n'

    printf '## CI vs Local Readiness Delta\n\n'
    printf '| Metric | Local - CI |\n'
    printf '| --- | ---: |\n'
    printf '| Blockers | %s |\n' "$ci_local_readiness_blocker_delta"
    printf '| Warnings | %s |\n\n' "$ci_local_readiness_warning_delta"
    printf 'A non-zero CI/local readiness delta means the local ignored release input files or host state differ from the clean CI packet environment. Use the CI external action manifest for account-owner handoff, and use the local preflight log for this machine.\n\n'
    write_readiness_delta_section \
      "CI-only Readiness Detail" \
      "$ci_readiness_log" \
      "$readiness_log" \
      "No CI-only blockers or warnings."
    write_readiness_delta_section \
      "Local-only Readiness Detail" \
      "$readiness_log" \
      "$ci_readiness_log" \
      "No local-only blockers or warnings."

    printf '## External Action Summary\n\n'
    if [[ -s "$external_actions_path" ]]; then
      printf '| Category | Severity | Count |\n'
      printf '| --- | --- | ---: |\n'
      awk -F '\t' '
        NR > 1 && $1 != "" && $2 != "" {
          key = $1 "\t" $2
          counts[key] += 1
        }
        END {
          for (key in counts) {
            print key "\t" counts[key]
          }
        }
      ' "$external_actions_path" \
        | LC_ALL=C sort \
        | awk -F '\t' '{ printf "| %s | %s | %s |\n", $1, $2, $3 }'
    else
      printf 'No external readiness action manifest was found at `%s`.\n' "$external_actions_path"
    fi

    printf '\n## Owner Summary\n\n'
    if [[ -s "$external_actions_path" ]]; then
      printf '| Owner | Actions | Blockers | Warnings |\n'
      printf '| --- | ---: | ---: | ---: |\n'
      awk -F '\t' '
        NR == 1 {
          for (i = 1; i <= NF; i++) {
            columns[$i] = i
          }
          next
        }
        $1 != "" {
          owner = $(columns["owner"])
          severity = $(columns["severity"])
          owner_counts[owner] += 1
          if (severity == "blocker") {
            owner_blocker_counts[owner] += 1
          } else if (severity == "warning") {
            owner_warning_counts[owner] += 1
          }
        }
        END {
          for (owner in owner_counts) {
            print owner "\t" owner_counts[owner] "\t" owner_blocker_counts[owner] + 0 "\t" owner_warning_counts[owner] + 0
          }
        }
      ' "$external_actions_path" \
        | LC_ALL=C sort \
        | awk -F '\t' '{ printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4 }'
    else
      printf 'No external readiness action manifest was found at `%s`.\n' "$external_actions_path"
    fi

    printf '\n'
    write_owner_status_commands "$release_phase_plan_final_submission_guard_actions"
    write_owner_input_status_reports_section

    printf '\n## Total Handoff Owner Summary\n\n'
    if [[ -s "$external_actions_path" ]]; then
      printf 'This adds derived final submission guard blockers to the Release owner so the owner view matches the total phase plan handoff count.\n\n'
      printf '| Owner | Actions | Blockers | Warnings |\n'
      printf '| --- | ---: | ---: | ---: |\n'
      awk -F '\t' -v final_guard_actions="$release_phase_plan_final_submission_guard_actions" '
        NR == 1 {
          for (i = 1; i <= NF; i++) {
            columns[$i] = i
          }
          next
        }
        $1 != "" {
          owner = $(columns["owner"])
          severity = $(columns["severity"])
          owner_counts[owner] += 1
          if (severity == "blocker") {
            owner_blocker_counts[owner] += 1
          } else if (severity == "warning") {
            owner_warning_counts[owner] += 1
          }
        }
        END {
          final_guard_actions += 0
          owner_counts["Release owner"] += final_guard_actions
          owner_blocker_counts["Release owner"] += final_guard_actions
          for (owner in owner_counts) {
            print owner "\t" owner_counts[owner] "\t" owner_blocker_counts[owner] + 0 "\t" owner_warning_counts[owner] + 0
          }
        }
      ' "$external_actions_path" \
        | LC_ALL=C sort \
        | awk -F '\t' '{ printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4 }'
    else
      printf 'No external readiness action manifest was found at `%s`.\n' "$external_actions_path"
    fi

    printf '\n## External Action Detail\n\n'
    if [[ -s "$external_actions_path" ]]; then
      printf '| Owner | Category | Severity | Field | Item | Next Action | Validation Command |\n'
      printf '| --- | --- | --- | --- | --- | --- | --- |\n'
      awk -F '\t' '
        function markdown_cell(value) {
          gsub(/\|/, "\\|", value)
          gsub(/`/, "\\`", value)
          return value
        }
        NR == 1 {
          for (i = 1; i <= NF; i++) {
            columns[$i] = i
          }
          next
        }
        $1 != "" {
          owner = markdown_cell($(columns["owner"]))
          category = markdown_cell($(columns["category"]))
          severity = markdown_cell($(columns["severity"]))
          field = markdown_cell($(columns["field"]))
          item = markdown_cell($(columns["item"]))
          next_action = markdown_cell($(columns["next_action"]))
          validation_command = markdown_cell($(columns["validation_command"]))
          printf "| %s | %s | %s | `%s` | %s | %s | `%s` |\n", owner, category, severity, field, item, next_action, validation_command
        }
      ' "$external_actions_path"
    else
      printf 'No external readiness action manifest was found at `%s`.\n' "$external_actions_path"
    fi

    printf '\n## Primary Action Files\n\n'
    printf -- '- Machine summary: `%s`\n' "$summary_path"
    printf -- '- Human brief: `%s`\n' "$brief_path"
    printf -- '- Release input status: `%s`\n' "$release_input_status_path"
    printf -- '- Release input TODO: `%s`\n' "$input_todo_path"
    printf -- '- Release phase plan: `%s`\n' "$phase_plan_path"
    printf -- '- Per-owner action briefs: `%s`\n' "$owner_action_dir"
    printf -- '- Owner-scoped release input status reports: `%s`\n' "$owner_input_status_dir"
    printf -- '- Private release input templates: `%s`\n' "$private_template_dir"
    printf -- '- CI action manifest: `%s`\n' "$external_actions_path"
    printf -- '- CI action checklist: `%s/ACTION_ITEMS.md`\n' "$packet_dir"
    printf -- '- Release input worksheet: `AppStore/release-inputs-worksheet.md`\n'
    printf -- '- Private release values: `Config/release.env`\n'
    printf -- '- Manual device evidence: `Config/manual-release-verification.env`\n\n'

    printf '## Next Commands\n\n'
    printf '```sh\n'
    printf 'Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config\n'
    printf 'Scripts/print_release_input_status.sh --strict\n'
    printf 'Scripts/check_app_store_readiness.sh\n'
    printf 'Scripts/validate_release_phase_plan.sh build/CISubmissionPacket/external-readiness-actions.tsv build/release-phase-plan.md\n'
    printf 'APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh\n'
    printf 'DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh\n'
    printf 'APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh\n'
    printf '```\n\n'
    printf 'Replace `PROCESSED_BUILD_NUMBER` with the processed App Store Connect build selected for review.\n'
    printf 'Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands.\n'
    printf 'Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.\n'
  } >"$brief_path"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

Scripts/validate_private_release_artifact_ignores.sh

local_status="$(git status --short)"
if [[ -n "$local_status" ]]; then
  printf 'FAIL: release handoff requires a clean local worktree.\n' >&2
  printf '%s\n' "$local_status" >&2
  exit 1
fi

local_head="$(git rev-parse HEAD)"

Scripts/download_latest_submission_packet.sh "$packet_dir"
Scripts/validate_release_provenance.sh "$packet_dir/release-provenance.tsv" "$local_head"
Scripts/validate_external_readiness_actions.sh "$packet_dir/readiness.txt" "$external_actions_path"
Scripts/generate_release_input_todo.sh "$external_actions_path" "$input_todo_path"
Scripts/validate_release_input_todo.sh "$external_actions_path" "$input_todo_path"
Scripts/generate_release_phase_plan.sh "$external_actions_path" "$phase_plan_path"
Scripts/validate_release_phase_plan.sh "$external_actions_path" "$phase_plan_path"
Scripts/generate_release_owner_action_briefs.sh "$external_actions_path" "$owner_action_dir"
Scripts/validate_release_owner_action_briefs.sh "$external_actions_path" "$owner_action_dir"
Scripts/generate_private_release_input_templates.sh "$external_actions_path" "$private_template_dir"
Scripts/validate_private_release_input_templates.sh "$external_actions_path" "$private_template_dir"

mkdir -p "$(dirname "$release_input_status_path")"
set +e
Scripts/print_release_input_status.sh --strict >"$release_input_status_path" 2>&1
release_input_status="$?"
set -e

release_phase_plan_final_submission_guard_actions="$(phase_plan_metadata_value "$phase_plan_path" "Final Submission Guard Actions")"
write_owner_input_status_reports "$release_phase_plan_final_submission_guard_actions"

mkdir -p "$(dirname "$readiness_log")"
set +e
Scripts/check_app_store_readiness.sh >"$readiness_log" 2>&1
readiness_status="$?"
set -e

if [[ "$readiness_status" -ne 0 ]]; then
  write_handoff_summary "blocked"
  write_handoff_brief "blocked"
  Scripts/validate_release_handoff_summary.sh "$summary_path"
  Scripts/validate_release_handoff_brief.sh "$external_actions_path" "$brief_path" "$ci_readiness_log" "$readiness_log"
  tail -n 80 "$readiness_log"
  printf '\nRelease handoff preflight blocked. See %s for the full readiness audit.\n' "$readiness_log"
  printf 'Release handoff summary: %s\n' "$summary_path"
  printf 'Release handoff brief: %s\n' "$brief_path"
  exit "$readiness_status"
fi

write_handoff_summary "ready"
write_handoff_brief "ready"
Scripts/validate_release_handoff_summary.sh "$summary_path"
Scripts/validate_release_handoff_brief.sh "$external_actions_path" "$brief_path" "$ci_readiness_log" "$readiness_log"
cat "$readiness_log"
printf '\nRelease handoff preflight passed for commit %s.\n' "$local_head"
printf 'Release handoff summary: %s\n' "$summary_path"
printf 'Release handoff brief: %s\n' "$brief_path"
