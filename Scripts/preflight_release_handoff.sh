#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

packet_dir="${FREEPRINTSTUDIO_HANDOFF_PACKET_DIR:-build/CISubmissionPacket}"
readiness_log="${FREEPRINTSTUDIO_HANDOFF_READINESS_LOG:-build/release-handoff-readiness.txt}"

usage() {
  cat <<'EOF'
Usage: Scripts/preflight_release_handoff.sh

Runs the final local handoff checks before release ownership moves to App Store
Connect account work:
  - requires a clean local git worktree
  - downloads and validates the latest successful CI submission packet
  - verifies the downloaded packet provenance matches the local HEAD
  - runs the App Store readiness audit and surfaces remaining blockers
EOF
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

mkdir -p "$(dirname "$readiness_log")"
set +e
Scripts/check_app_store_readiness.sh >"$readiness_log" 2>&1
readiness_status="$?"
set -e

if [[ "$readiness_status" -ne 0 ]]; then
  tail -n 80 "$readiness_log"
  printf '\nRelease handoff preflight blocked. See %s for the full readiness audit.\n' "$readiness_log"
  exit "$readiness_status"
fi

cat "$readiness_log"
printf '\nRelease handoff preflight passed for commit %s.\n' "$local_head"
