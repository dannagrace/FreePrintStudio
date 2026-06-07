#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

failures=0

ok() {
  printf 'OK: %s\n' "$1"
}

block() {
  printf 'BLOCKED: %s\n' "$1"
  failures=$((failures + 1))
}

trimmed_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

first_name="$(trimmed_value "${APP_REVIEW_CONTACT_FIRST_NAME:-}")"
last_name="$(trimmed_value "${APP_REVIEW_CONTACT_LAST_NAME:-}")"
phone="$(trimmed_value "${APP_REVIEW_CONTACT_PHONE:-}")"
email="$(trimmed_value "${APP_REVIEW_CONTACT_EMAIL:-}")"
name_pattern="^[[:alpha:]][[:alpha:]' -]{0,63}$"
email_pattern='^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'
phone_pattern='^\+?[0-9][0-9 .()/-]{6,24}$'

[[ -n "$first_name" ]] || block "APP_REVIEW_CONTACT_FIRST_NAME is missing"
[[ -n "$last_name" ]] || block "APP_REVIEW_CONTACT_LAST_NAME is missing"
[[ -n "$phone" ]] || block "APP_REVIEW_CONTACT_PHONE is missing"
[[ -n "$email" ]] || block "APP_REVIEW_CONTACT_EMAIL is missing"

if [[ -n "$first_name" && ! "$first_name" =~ $name_pattern ]]; then
  block "APP_REVIEW_CONTACT_FIRST_NAME contains unsupported characters"
fi

if [[ -n "$last_name" && ! "$last_name" =~ $name_pattern ]]; then
  block "APP_REVIEW_CONTACT_LAST_NAME contains unsupported characters"
fi

# Basic email pattern for App Review contact details: local@domain.tld, no spaces.
if [[ -n "$email" && ! "$email" =~ $email_pattern ]]; then
  block "APP_REVIEW_CONTACT_EMAIL does not match the expected email pattern"
fi

if [[ -n "$phone" ]]; then
  if [[ "$phone" =~ [A-Za-z] ]]; then
    block "APP_REVIEW_CONTACT_PHONE must not contain letters"
  fi

  if [[ ! "$phone" =~ $phone_pattern ]]; then
    block "APP_REVIEW_CONTACT_PHONE must contain a dialable phone number"
  fi

  digit_count="$(tr -cd '0-9' <<<"$phone" | wc -c | tr -d ' ')"
  if [[ ! "$digit_count" =~ ^[0-9]+$ ]] || (( digit_count < 7 || digit_count > 15 )); then
    block "APP_REVIEW_CONTACT_PHONE must contain 7 to 15 digits"
  fi
fi

if Scripts/validate_release_env.sh >/tmp/freeprintstudio-review-contact-env.log 2>&1; then
  :
else
  while IFS= read -r line; do
    case "$line" in
      *APP_REVIEW_CONTACT_*|*FASTLANE_USER*)
        printf '%s\n' "$line"
        failures=$((failures + 1))
        ;;
    esac
  done </tmp/freeprintstudio-review-contact-env.log
fi

if (( failures > 0 )); then
  exit 1
fi

ok "App Review contact details are present and formatted"
