#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: Scripts/download_latest_submission_packet.sh [destination]

Downloads the latest successful Release Gates App Store submission packet artifact
from GitHub Actions, then validates the downloaded packet locally.

Environment overrides:
  FREEPRINTSTUDIO_GITHUB_REPO                 GitHub repo, default dannagrace/FreePrintStudio
  FREEPRINTSTUDIO_RELEASE_WORKFLOW           Workflow file/name, default release.yml
  FREEPRINTSTUDIO_RELEASE_BRANCH             Branch, default main
  FREEPRINTSTUDIO_SUBMISSION_PACKET_ARTIFACT Artifact name, default freeprintstudio-app-store-submission-packet
  FREEPRINTSTUDIO_CI_SUBMISSION_PACKET_DIR   Destination, default build/CISubmissionPacket
  FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_ATTEMPTS Download attempts, default 3
  FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_TIMEOUT_SECONDS
                                               Per-attempt artifact download timeout, default 180
                                               If gh run download stalls, the helper falls back to the
                                               GitHub artifact API for the same artifact.
  FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_METHOD    auto, gh, or api; default auto
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  printf 'FAIL: GitHub CLI is required to download the CI submission packet. Install gh and authenticate with GitHub.\n' >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  printf 'FAIL: curl is required for the GitHub artifact API fallback.\n' >&2
  exit 1
fi

repo="${FREEPRINTSTUDIO_GITHUB_REPO:-dannagrace/FreePrintStudio}"
workflow="${FREEPRINTSTUDIO_RELEASE_WORKFLOW:-release.yml}"
branch="${FREEPRINTSTUDIO_RELEASE_BRANCH:-main}"
artifact_name="${FREEPRINTSTUDIO_SUBMISSION_PACKET_ARTIFACT:-freeprintstudio-app-store-submission-packet}"
destination="${1:-${FREEPRINTSTUDIO_CI_SUBMISSION_PACKET_DIR:-build/CISubmissionPacket}}"
download_attempts="${FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_ATTEMPTS:-3}"
download_timeout_seconds="${FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_TIMEOUT_SECONDS:-180}"
download_method="${FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_METHOD:-auto}"
if ! [[ "$download_attempts" =~ ^[1-9][0-9]*$ ]]; then
  printf 'FAIL: FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_ATTEMPTS must be a positive integer.\n' >&2
  exit 1
fi
if ! [[ "$download_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  printf 'FAIL: FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_TIMEOUT_SECONDS must be a positive integer.\n' >&2
  exit 1
fi
case "$download_method" in
  auto|gh|api)
    ;;
  *)
    printf 'FAIL: FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_METHOD must be auto, gh, or api.\n' >&2
    exit 1
    ;;
esac

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout_text = sys.argv[1]
command = sys.argv[2:]
try:
    completed = subprocess.run(
        command,
        timeout=float(timeout_text),
        check=False,
    )
except subprocess.TimeoutExpired:
    print(
        f"Artifact download command timed out after {timeout_text} seconds: {' '.join(command)}",
        file=sys.stderr,
    )
    raise SystemExit(124)

raise SystemExit(completed.returncode)
PY
}

download_with_artifact_api() {
  local run_id="$1"
  local artifact_name="$2"
  local output_dir="$3"
  local timeout_seconds="$4"
  local artifact_name_jq
  local artifact_info
  local artifact_id
  local artifact_expired
  local artifact_zip_url
  local api_token
  local zip_path

  artifact_name_jq="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$artifact_name")"
  if ! artifact_info="$(
    gh api --method GET "repos/$repo/actions/runs/$run_id/artifacts" \
      -F per_page=100 \
      --jq ".artifacts[] | select(.name == $artifact_name_jq) | [.id, .expired] | @tsv"
  )"; then
    printf 'GitHub artifact API fallback could not list artifacts for run %s.\n' "$run_id" >&2
    return 1
  fi

  artifact_info="${artifact_info%%$'\n'*}"
  if [[ -z "$artifact_info" ]]; then
    printf 'GitHub artifact API fallback could not find artifact %s for run %s.\n' "$artifact_name" "$run_id" >&2
    return 1
  fi

  IFS=$'\t' read -r artifact_id artifact_expired <<<"$artifact_info"
  if [[ -z "${artifact_id:-}" || "$artifact_expired" == "true" ]]; then
    printf 'GitHub artifact API fallback found an unusable artifact record for %s.\n' "$artifact_name" >&2
    return 1
  fi

  zip_path="$output_dir/artifact.zip"
  artifact_zip_url="https://api.github.com/repos/$repo/actions/artifacts/$artifact_id/zip"
  if ! api_token="$(gh auth token)"; then
    printf 'GitHub artifact API fallback could not read GitHub CLI auth token.\n' >&2
    return 1
  fi

  if ! GITHUB_TOKEN="$api_token" run_with_timeout "$timeout_seconds" bash -c '
    curl --fail --location --silent --show-error \
      --header "Authorization: Bearer ${GITHUB_TOKEN}" \
      --header "Accept: application/vnd.github+json" \
      --output "$1" \
      "$2"
  ' bash "$zip_path" "$artifact_zip_url"; then
    printf 'GitHub artifact API fallback failed to download artifact archive %s.\n' "$artifact_id" >&2
    return 1
  fi

  if ! python3 - "$zip_path" "$output_dir" <<'PY'; then
import sys
import zipfile
from pathlib import Path

zip_path = Path(sys.argv[1])
output_dir = Path(sys.argv[2]).resolve()

with zipfile.ZipFile(zip_path) as archive:
    for member in archive.infolist():
        target = (output_dir / member.filename).resolve()
        if target != output_dir and output_dir not in target.parents:
            raise SystemExit(f"Refusing unsafe artifact zip path: {member.filename}")
    archive.extractall(output_dir)
PY
    printf 'GitHub artifact API fallback downloaded an invalid artifact zip for %s.\n' "$artifact_name" >&2
    return 1
  fi

  rm -f "$zip_path"
  return 0
}

case "$destination" in
  ""|"/"|"$ROOT_DIR"|"$HOME")
    printf 'FAIL: Refusing unsafe submission packet destination: %s\n' "${destination:-empty}" >&2
    exit 1
    ;;
esac

run_info="$(
  gh run list \
    --repo "$repo" \
    --workflow "$workflow" \
    --branch "$branch" \
    --status success \
    --limit 1 \
    --json databaseId,headSha,url \
    --jq '.[0] | [.databaseId, .headSha, .url] | @tsv'
)"

if [[ -z "$run_info" ]]; then
  printf 'FAIL: No successful Release Gates run found for %s on %s.\n' "$repo" "$branch" >&2
  exit 1
fi

IFS=$'\t' read -r run_id run_sha run_url <<<"$run_info"
if [[ -z "${run_id:-}" || -z "${run_sha:-}" || -z "${run_url:-}" ]]; then
  printf 'FAIL: Latest successful Release Gates run metadata is incomplete.\n' >&2
  exit 1
fi

temp_dir="$(mktemp -d -t freeprintstudio-ci-packet)"
cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

printf 'Downloading %s from %s\n' "$artifact_name" "$run_url"
downloaded=0
for attempt in $(seq 1 "$download_attempts"); do
  printf 'Artifact download attempt %s of %s\n' "$attempt" "$download_attempts"
  rm -rf "$temp_dir"/*

  if [[ "$download_method" != "api" ]]; then
    if run_with_timeout "$download_timeout_seconds" gh run download "$run_id" \
      --repo "$repo" \
      --name "$artifact_name" \
      --dir "$temp_dir"; then
      downloaded=1
      break
    fi
  fi

  if [[ "$download_method" != "gh" ]]; then
    if [[ "$download_method" == "api" ]]; then
      printf 'Using GitHub artifact API download path.\n' >&2
    else
      printf 'gh run download did not complete; trying GitHub artifact API fallback.\n' >&2
    fi
    rm -rf "$temp_dir"/*
    if download_with_artifact_api "$run_id" "$artifact_name" "$temp_dir" "$download_timeout_seconds"; then
      downloaded=1
      break
    fi
  fi

  if [[ "$attempt" != "$download_attempts" ]]; then
    sleep "$attempt"
  fi
done

if [[ "$downloaded" != "1" ]]; then
  printf 'FAIL: Could not download %s from latest successful Release Gates run after %s attempt(s).\n' \
    "$artifact_name" "$download_attempts" >&2
  exit 1
fi

packet_source=""
if [[ -f "$temp_dir/SUMMARY.md" ]]; then
  packet_source="$temp_dir"
else
  summary_path="$(find "$temp_dir" -mindepth 2 -maxdepth 4 -type f -name SUMMARY.md | sort | head -n 1)"
  if [[ -n "$summary_path" ]]; then
    packet_source="$(dirname "$summary_path")"
  fi
fi

if [[ -z "$packet_source" ]]; then
  printf 'FAIL: Downloaded artifact does not look like an App Store submission packet; SUMMARY.md is missing.\n' >&2
  exit 1
fi

rm -rf "$destination"
mkdir -p "$destination"
cp -R "$packet_source"/. "$destination"/

FREEPRINTSTUDIO_SUBMISSION_PACKET_DIR="$destination" Scripts/validate_app_store_submission_packet.sh
Scripts/validate_release_provenance.sh "$destination/release-provenance.tsv" "$run_sha" "$run_url"

printf 'Downloaded and validated CI submission packet: %s\n' "$destination"
printf 'Source run: %s\n' "$run_url"
printf 'Source SHA: %s\n' "$run_sha"
