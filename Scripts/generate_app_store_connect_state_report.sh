#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

output_path="${1:-build/app-store-connect-state-report.md}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
state_timeout_seconds="${FREEPRINTSTUDIO_ASC_STATE_REPORT_TIMEOUT_SECONDS:-120}"
release_env_path="${RELEASE_ENV_PATH:-$ROOT_DIR/Config/release.env}"
manual_evidence_path="${MANUAL_RELEASE_VERIFICATION_PATH:-$ROOT_DIR/Config/manual-release-verification.env}"

usage() {
  cat <<'EOF'
Usage: Scripts/generate_app_store_connect_state_report.sh [output-path]

Generates a redacted App Store Connect selected-build state report. The report
captures the selected build state check exit code and output without printing
private credential values or local absolute paths.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

mkdir -p "$(dirname "$output_path")"

mask_value() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    printf 'missing'
  elif (( ${#value} <= 4 )); then
    printf 'redacted'
  else
    printf 'redacted-%s' "${value: -4}"
  fi
}

looks_placeholder_like() {
  local value="${1:-}"
  local lower_value
  [[ -z "$value" ]] && return 1
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" == *YOUR* ]] && return 0
  [[ "$value" == *YOUR_* ]] && return 0
  [[ "$lower_value" == *todo* ]] && return 0
  [[ "$lower_value" == *tbd* ]] && return 0
  [[ "$lower_value" == *example* ]] && return 0
  [[ "$lower_value" == *placeholder* ]] && return 0
  [[ "$value" == "PROCESSED_BUILD_NUMBER" ]] && return 0
  return 1
}

selected_build_status() {
  if [[ -z "${APP_STORE_BUILD_NUMBER:-}" ]]; then
    printf 'Missing'
  elif looks_placeholder_like "${APP_STORE_BUILD_NUMBER:-}"; then
    printf 'Blocked; selected build still uses a placeholder'
  else
    printf 'Configured (%s)' "$(mask_value "${APP_STORE_BUILD_NUMBER:-}")"
  fi
}

redact_line() {
  local value="$1"
  local secret

  value="${value//$manual_evidence_path/[manual-evidence-env]}"
  value="${value//$release_env_path/[release-env]}"
  value="${value//$ROOT_DIR\//[repo]/}"
  value="${value//$ROOT_DIR/[repo]}"
  value="${value//$HOME\//[home]/}"
  value="${value//$HOME/[home]}"
  value="${value//\/private\/var\/folders\//[private-var-folders]/}"
  value="${value//\/var\/folders\//[var-folders]/}"
  value="${value//\/tmp\/freeprintstudio/[tmp-freeprintstudio]}"

  for secret in \
    "${APP_STORE_CONNECT_API_KEY_JSON:-}" \
    "${ASC_KEY_ID:-}" \
    "${ASC_ISSUER_ID:-}" \
    "${ASC_KEY_PATH:-}" \
    "${FASTLANE_USER:-}" \
    "${FASTLANE_ITC_TEAM_ID:-}" \
    "${FASTLANE_ITC_TEAM_NAME:-}" \
    "${APP_STORE_BUILD_NUMBER:-}"
  do
    if [[ -n "$secret" ]]; then
      value="${value//$secret/[redacted]}"
    fi
  done

  printf '%s' "$value"
}

run_state_check() {
  local timeout_seconds="$1"
  local output_file="$2"
  python3 - "$timeout_seconds" "$output_file" <<'PY'
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
output_file = sys.argv[2]
command = ["Scripts/validate_app_store_connect_submission_state.sh"]

with open(output_file, "w", encoding="utf-8") as output:
    try:
        completed = subprocess.run(
            command,
            stdout=output,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired:
        output.write(f"BLOCKED: App Store Connect state check timed out after {timeout_seconds:g} seconds\n")
        raise SystemExit(124)

raise SystemExit(completed.returncode)
PY
}

state_log="$(mktemp)"
redacted_state_log="$(mktemp)"
set +e
run_state_check "$state_timeout_seconds" "$state_log"
state_exit_code="$?"
set -e

while IFS= read -r line; do
  printf '%s\n' "$(redact_line "$line")"
done <"$state_log" >"$redacted_state_log"

if [[ "$state_exit_code" -eq 0 ]]; then
  state_status="Passed"
else
  state_status="Blocked"
fi

if [[ "${APP_STORE_CONNECT_SUBMISSION_MODE:-api}" == "manual" ]]; then
  required_next_actions="$(cat <<'EOF'
- [ ] Immediately before submission, re-open the signed-in App Store Connect version page.
- [ ] Confirm the version is ready for submission and the selected processed build still matches `APP_STORE_BUILD_NUMBER`.
- [ ] Refresh `APP_STORE_CONNECT_MANUAL_STATE_VERIFIED_DATE` and rerun `Scripts/validate_app_store_connect_submission_state.sh`.
- [ ] Keep this report in the submission packet as account-side selected-build evidence.
EOF
)"
else
  required_next_actions="$(cat <<'EOF'
- [ ] Configure App Store Connect credentials in untracked `Config/release.env`.
- [ ] Upload a signed TestFlight build.
- [ ] Wait for the build to finish App Store Connect processing.
- [ ] Set `APP_STORE_BUILD_NUMBER` to the processed build selected for App Review.
- [ ] Rerun `APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_app_store_connect_submission_state.sh` with the real processed build number.
- [ ] Keep this report in the submission packet as account-side selected-build evidence.
EOF
)"
fi

cat >"$output_path" <<EOF
# FreePrint Studio App Store Connect State Report

- Generated At: $generated_at
- This report is redacted: it does not print API key JSON paths, .p8 private key paths, Apple ID values, App Review contact values, selected build values, or private credential contents.
- Submission Mode: ${APP_STORE_CONNECT_SUBMISSION_MODE:-api}
- State check command: \`Scripts/validate_app_store_connect_submission_state.sh\`
- Exit Code: $state_exit_code
- Status: $state_status
- Timeout Seconds: $state_timeout_seconds

## Selected Build Input

| Item | Status |
| --- | --- |
| \`APP_STORE_BUILD_NUMBER\` | $(selected_build_status) |

## Redacted Output

\`\`\`text
$(cat "$redacted_state_log")
\`\`\`

## Required Next Actions

$required_next_actions
EOF

rm -f "$state_log" "$redacted_state_log"

printf 'App Store Connect state report generated: %s\n' "$output_path"
