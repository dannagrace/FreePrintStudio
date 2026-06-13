#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

packet_dir="${FREEPRINTSTUDIO_HANDOFF_PACKET_DIR:-build/CISubmissionPacket}"
readiness_log="${FREEPRINTSTUDIO_HANDOFF_READINESS_LOG:-build/release-handoff-readiness.txt}"
summary_path="${FREEPRINTSTUDIO_HANDOFF_SUMMARY_PATH:-build/release-handoff-summary.tsv}"
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
EOF
}

provenance_value() {
  local key="$1"
  awk -F '\t' -v key="$key" 'NR > 1 && $1 == key { print $2; found = 1; exit } END { if (!found) exit 1 }' \
    "$packet_dir/release-provenance.tsv"
}

write_handoff_summary() {
  local handoff_status="$1"
  local packet_git_commit
  local packet_github_run_url
  local packet_github_sha
  local readiness_blockers
  local readiness_warnings

  packet_git_commit="$(provenance_value git_commit 2>/dev/null || printf 'missing')"
  packet_github_run_url="$(provenance_value github_run_url 2>/dev/null || printf 'missing')"
  packet_github_sha="$(provenance_value github_sha 2>/dev/null || printf 'missing')"
  readiness_blockers="$(grep -c '^BLOCKED:' "$readiness_log" || true)"
  readiness_warnings="$(grep -c '^WARN:' "$readiness_log" || true)"

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
    printf 'external_readiness_actions\t%s\n' "$external_actions_path"
    printf 'readiness_log\t%s\n' "$readiness_log"
    printf 'readiness_status\t%s\n' "$readiness_status"
    printf 'readiness_blockers\t%s\n' "$readiness_blockers"
    printf 'readiness_warnings\t%s\n' "$readiness_warnings"
  } >"$summary_path"
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

mkdir -p "$(dirname "$readiness_log")"
set +e
Scripts/check_app_store_readiness.sh >"$readiness_log" 2>&1
readiness_status="$?"
set -e

if [[ "$readiness_status" -ne 0 ]]; then
  write_handoff_summary "blocked"
  tail -n 80 "$readiness_log"
  printf '\nRelease handoff preflight blocked. See %s for the full readiness audit.\n' "$readiness_log"
  printf 'Release handoff summary: %s\n' "$summary_path"
  exit "$readiness_status"
fi

write_handoff_summary "ready"
cat "$readiness_log"
printf '\nRelease handoff preflight passed for commit %s.\n' "$local_head"
printf 'Release handoff summary: %s\n' "$summary_path"
