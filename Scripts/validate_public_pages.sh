#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PUBLIC_PAGE_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_PUBLIC_PAGE_TIMEOUT_SECONDS:-20}"
failures=0

ok() {
  printf 'OK: %s\n' "$1"
}

block() {
  printf 'BLOCKED: %s\n' "$1"
  failures=$((failures + 1))
}

check_page() {
  local label="$1"
  local source_path="$2"
  local url="$3"
  local expected_text="$4"
  local body_path
  local status="000"
  local attempt

  if [[ ! -s "$source_path" ]]; then
    block "$label local source is missing or empty: $source_path"
  elif ! grep -q "$expected_text" "$source_path"; then
    block "$label local source does not contain expected text: $expected_text"
  else
    ok "$label local source is ready: $source_path"
  fi

  body_path="$(mktemp)"
  for attempt in 1 2 3; do
    status="$(curl -L -s --connect-timeout 10 --max-time "$PUBLIC_PAGE_TIMEOUT_SECONDS" -o "$body_path" -w '%{http_code}' "$url" || true)"
    [[ "$status" == "200" ]] && break
    sleep 2
  done

  if [[ "$status" != "200" ]]; then
    block "$label URL is not publicly reachable: $url returned $status"
  elif ! grep -q "$expected_text" "$body_path"; then
    block "$label URL does not contain expected text: $expected_text"
  else
    ok "$label URL is public and contains expected text: $url"
  fi

  rm -f "$body_path"
}

check_page \
  "Privacy policy" \
  "docs/privacy-policy.html" \
  "https://dannagrace.github.io/FreePrintStudio/privacy-policy.html" \
  "FreePrint Studio Privacy Policy"

check_page \
  "Support" \
  "docs/support.html" \
  "https://dannagrace.github.io/FreePrintStudio/support.html" \
  "FreePrint Studio Support"

if (( failures > 0 )); then
  printf 'Public pages validation failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'Public pages validation passed.\n'
