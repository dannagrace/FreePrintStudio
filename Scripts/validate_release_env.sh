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

PLACEHOLDER_VALUES=(
  "ABCDE12345"
  "YOURTEAMID"
  "YOUR_FIRST_NAME"
  "YOUR_LAST_NAME"
  "+1-555-0100"
  "review-contact@example.com"
  "apple-id@example.com"
  "XXXXXXXXXX"
  "00000000-0000-0000-0000-000000000000"
  "/absolute/path/to/AuthKey_XXXXXXXXXX.p8"
  "/absolute/path/to/fastlane-api-key.json"
  "/absolute/path/to/FreePrintStudio.ipa"
  "/secure/AuthKey_XXXXXXXXXX.p8"
  "123456789"
  "Your Team Name"
  "PROCESSED_BUILD_NUMBER"
  "TODO"
  "TBD"
  "PLACEHOLDER"
)

tracked_env_names=(
  DEVELOPMENT_TEAM_ID
  ASC_KEY_ID
  ASC_ISSUER_ID
  ASC_KEY_PATH
  APP_STORE_CONNECT_API_KEY_JSON
  APP_REVIEW_CONTACT_FIRST_NAME
  APP_REVIEW_CONTACT_LAST_NAME
  APP_REVIEW_CONTACT_PHONE
  APP_REVIEW_CONTACT_EMAIL
  FASTLANE_USER
  FASTLANE_ITC_TEAM_ID
  FASTLANE_ITC_TEAM_NAME
  IPA_PATH
  APP_STORE_BUILD_NUMBER
)

looks_like_placeholder() {
  local value="$1"
  local lower_value
  local placeholder

  [[ -z "$value" ]] && return 1
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  for placeholder in "${PLACEHOLDER_VALUES[@]}"; do
    [[ "$value" == "$placeholder" ]] && return 0
  done

  [[ "$value" == *"YOUR_"* ]] && return 0
  [[ "$value" == *"XXXXXXXXXX"* ]] && return 0
  [[ "$lower_value" == *"example.com"* ]] && return 0
  [[ "$lower_value" == *@example.* ]] && return 0
  [[ "$lower_value" == *"todo"* ]] && return 0
  [[ "$lower_value" == *"tbd"* ]] && return 0
  [[ "$lower_value" == *"placeholder"* ]] && return 0
  [[ "$value" == /absolute/path/* ]] && return 0

  return 1
}

for env_name in "${tracked_env_names[@]}"; do
  value="${!env_name:-}"
  if looks_like_placeholder "$value"; then
    block "$env_name still uses a placeholder value"
  fi
done

if (( failures > 0 )); then
  printf '\nReplace placeholder values in Config/release.env or unset them until real account values are available.\n'
  exit 1
fi

ok "Release environment contains no known placeholder values"
