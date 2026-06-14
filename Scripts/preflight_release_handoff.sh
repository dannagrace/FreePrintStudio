#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

packet_dir="${FREEPRINTSTUDIO_HANDOFF_PACKET_DIR:-build/CISubmissionPacket}"
readiness_log="${FREEPRINTSTUDIO_HANDOFF_READINESS_LOG:-build/release-handoff-readiness.txt}"
summary_path="${FREEPRINTSTUDIO_HANDOFF_SUMMARY_PATH:-build/release-handoff-summary.tsv}"
brief_path="${FREEPRINTSTUDIO_HANDOFF_BRIEF_PATH:-build/release-handoff-brief.md}"
input_todo_path="${FREEPRINTSTUDIO_HANDOFF_INPUT_TODO_PATH:-build/release-input-todo.md}"
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
  - runs the App Store readiness audit and surfaces remaining blockers
  - writes build/release-handoff-summary.tsv with CI packet and readiness status
  - writes build/release-handoff-brief.md for release owner handoff
  - writes build/release-input-todo.md with fillable private release input fields
EOF
}

provenance_value() {
  local key="$1"
  awk -F '\t' -v key="$key" 'NR > 1 && $1 == key { print $2; found = 1; exit } END { if (!found) exit 1 }' \
    "$packet_dir/release-provenance.tsv"
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
    printf 'release_input_todo\t%s\n' "$input_todo_path"
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

    printf '\n## External Action Detail\n\n'
    if [[ -s "$external_actions_path" ]]; then
      printf '| Category | Severity | Field | Item | Next Action | Validation Command |\n'
      printf '| --- | --- | --- | --- | --- | --- |\n'
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
          category = markdown_cell($(columns["category"]))
          severity = markdown_cell($(columns["severity"]))
          field = markdown_cell($(columns["field"]))
          item = markdown_cell($(columns["item"]))
          next_action = markdown_cell($(columns["next_action"]))
          validation_command = markdown_cell($(columns["validation_command"]))
          printf "| %s | %s | `%s` | %s | %s | `%s` |\n", category, severity, field, item, next_action, validation_command
        }
      ' "$external_actions_path"
    else
      printf 'No external readiness action manifest was found at `%s`.\n' "$external_actions_path"
    fi

    printf '\n## Primary Action Files\n\n'
    printf -- '- Machine summary: `%s`\n' "$summary_path"
    printf -- '- Human brief: `%s`\n' "$brief_path"
    printf -- '- Release input TODO: `%s`\n' "$input_todo_path"
    printf -- '- CI action manifest: `%s`\n' "$external_actions_path"
    printf -- '- CI action checklist: `%s/ACTION_ITEMS.md`\n' "$packet_dir"
    printf -- '- Release input worksheet: `AppStore/release-inputs-worksheet.md`\n'
    printf -- '- Private release values: `Config/release.env`\n'
    printf -- '- Manual device evidence: `Config/manual-release-verification.env`\n\n'

    printf '## Next Commands\n\n'
    printf '```sh\n'
    printf 'Scripts/bootstrap_release_inputs.sh\n'
    printf 'Scripts/print_release_input_status.sh --strict\n'
    printf 'Scripts/check_app_store_readiness.sh\n'
    printf 'APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh\n'
    printf 'DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh\n'
    printf 'APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh\n'
    printf '```\n\n'
    printf 'Replace `PROCESSED_BUILD_NUMBER` with the processed App Store Connect build selected for review.\n'
  } >"$brief_path"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

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

mkdir -p "$(dirname "$readiness_log")"
set +e
Scripts/check_app_store_readiness.sh >"$readiness_log" 2>&1
readiness_status="$?"
set -e

if [[ "$readiness_status" -ne 0 ]]; then
  write_handoff_summary "blocked"
  write_handoff_brief "blocked"
  Scripts/validate_release_handoff_summary.sh "$summary_path"
  tail -n 80 "$readiness_log"
  printf '\nRelease handoff preflight blocked. See %s for the full readiness audit.\n' "$readiness_log"
  printf 'Release handoff summary: %s\n' "$summary_path"
  printf 'Release handoff brief: %s\n' "$brief_path"
  exit "$readiness_status"
fi

write_handoff_summary "ready"
write_handoff_brief "ready"
Scripts/validate_release_handoff_summary.sh "$summary_path"
cat "$readiness_log"
printf '\nRelease handoff preflight passed for commit %s.\n' "$local_head"
printf 'Release handoff summary: %s\n' "$summary_path"
printf 'Release handoff brief: %s\n' "$brief_path"
