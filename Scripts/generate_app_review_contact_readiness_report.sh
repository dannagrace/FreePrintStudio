#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

output_path="${1:-build/app-review-contact-readiness-report.md}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

usage() {
  cat <<'EOF'
Usage: Scripts/generate_app_review_contact_readiness_report.sh [output-path]

Generates a redacted App Review contact readiness report. The report is safe to
package because it summarizes required contact-field status without printing
names, phone numbers, email addresses, or other personal contact details.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

mkdir -p "$(dirname "$output_path")"

ready_count=0
failure_count=0
warning_count=0

trimmed_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

record_ready() {
  ready_count=$((ready_count + 1))
}

record_failure() {
  failure_count=$((failure_count + 1))
}

record_warning() {
  warning_count=$((warning_count + 1))
}

looks_placeholder_like() {
  local value="$1"
  [[ -z "$value" ]] && return 1
  [[ "$value" == *YOUR* ]] && return 0
  [[ "$value" == *TODO* ]] && return 0
  [[ "$value" == *TBD* ]] && return 0
  [[ "$value" == *example* ]] && return 0
  [[ "$value" == *placeholder* ]] && return 0
  return 1
}

name_pattern="^[[:alpha:]][[:alpha:]' -]{0,63}$"
email_pattern='^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'
phone_pattern='^\+?[0-9][0-9 .()/-]{6,24}$'

first_name="$(trimmed_value "${APP_REVIEW_CONTACT_FIRST_NAME:-}")"
last_name="$(trimmed_value "${APP_REVIEW_CONTACT_LAST_NAME:-}")"
phone="$(trimmed_value "${APP_REVIEW_CONTACT_PHONE:-}")"
email="$(trimmed_value "${APP_REVIEW_CONTACT_EMAIL:-}")"

value_status() {
  local value="$1"
  if [[ -z "$value" ]]; then
    record_failure
    status_result='Missing'
  elif looks_placeholder_like "$value"; then
    record_failure
    status_result='Placeholder-like'
  else
    record_ready
    status_result='Recorded; value redacted'
  fi
}

name_status() {
  local value="$1"
  value_status "$value"
  if [[ "$status_result" == "Recorded; value redacted" && ! "$value" =~ $name_pattern ]]; then
    ready_count=$((ready_count - 1))
    record_failure
    status_result='Invalid format; value redacted'
  fi
}

email_status() {
  local value="$1"
  value_status "$value"
  if [[ "$status_result" == "Recorded; value redacted" && ! "$value" =~ $email_pattern ]]; then
    ready_count=$((ready_count - 1))
    record_failure
    status_result='Invalid email format; value redacted'
  fi
}

phone_status() {
  local value="$1"
  local digit_count
  value_status "$value"
  if [[ "$status_result" != "Recorded; value redacted" ]]; then
    return
  fi

  if [[ "$value" =~ [A-Za-z] ]]; then
    ready_count=$((ready_count - 1))
    record_failure
    status_result='Invalid phone format; contains letters'
    return
  fi

  if [[ ! "$value" =~ $phone_pattern ]]; then
    ready_count=$((ready_count - 1))
    record_failure
    status_result='Invalid phone format; value redacted'
    return
  fi

  digit_count="$(tr -cd '0-9' <<<"$value" | wc -c | tr -d ' ')"
  if [[ ! "$digit_count" =~ ^[0-9]+$ ]] || (( digit_count < 7 || digit_count > 15 )); then
    ready_count=$((ready_count - 1))
    record_failure
    status_result='Invalid digit count; value redacted'
  fi
}

name_status "$first_name"
status_first_name="$status_result"
name_status "$last_name"
status_last_name="$status_result"
phone_status "$phone"
status_phone="$status_result"
email_status "$email"
status_email="$status_result"

validator_status='Not run'
set +e
Scripts/validate_app_review_contact.sh >/tmp/freeprintstudio-contact-report-validator.log 2>&1
strict_status="$?"
set -e
if [[ "$strict_status" -eq 0 ]]; then
  validator_status='Pass'
else
  validator_status='Blocked; see strict validator output'
fi

cat >"$output_path" <<EOF
# FreePrint Studio App Review Contact Readiness Report

- Generated At: $generated_at
- This report is redacted: it does not print names, phone numbers, email addresses, or personal contact details.
- Strict validation command: \`Scripts/validate_app_review_contact.sh\`
- Release input status command: \`Scripts/print_release_input_status.sh --strict\`
- Source of private values: git-ignored \`Config/release.env\` or shell environment.

## Summary

| Metric | Value |
| --- | ---: |
| Ready contact checks | $ready_count |
| Blocking contact checks | $failure_count |
| Warning contact checks | $warning_count |
| Strict validator | $validator_status |

## Required Contact Fields

| Field | Env field | Status |
| --- | --- | --- |
| First name | \`APP_REVIEW_CONTACT_FIRST_NAME\` | $status_first_name |
| Last name | \`APP_REVIEW_CONTACT_LAST_NAME\` | $status_last_name |
| Phone number | \`APP_REVIEW_CONTACT_PHONE\` | $status_phone |
| Email address | \`APP_REVIEW_CONTACT_EMAIL\` | $status_email |

## Required Next Actions

- [ ] Fill \`APP_REVIEW_CONTACT_FIRST_NAME\`, \`APP_REVIEW_CONTACT_LAST_NAME\`, \`APP_REVIEW_CONTACT_PHONE\`, and \`APP_REVIEW_CONTACT_EMAIL\` in the git-ignored \`Config/release.env\` file or shell environment.
- [ ] Run \`Scripts/validate_app_review_contact.sh\`.
- [ ] Run \`Scripts/run_fastlane.sh ios metadata\` only after the strict contact validator passes if metadata upload is automated.
- [ ] Run \`APP_STORE_BUILD_NUMBER=<processed-build> Scripts/preflight_app_review_submission.sh\` before final review submission.
EOF

printf 'App Review contact readiness report generated: %s\n' "$output_path"
