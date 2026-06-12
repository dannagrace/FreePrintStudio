#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_path="${1:-build/public-pages-readiness-report.md}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PUBLIC_PAGE_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_PUBLIC_PAGE_TIMEOUT_SECONDS:-20}"

usage() {
  cat <<'EOF'
Usage: Scripts/generate_public_pages_readiness_report.sh [output-path]

Generates a public privacy and support page readiness report for App Store
handoff. The report records local source checks and public GitHub Pages
reachability without printing temporary file paths.
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
blocker_count=0
warning_count=0
rows=""

append_row() {
  local page="$1"
  local source_path="$2"
  local url="$3"
  local status="$4"
  local http_status="$5"
  local expected_text="$6"
  local notes="$7"

  rows+=$'| '"$page"$' | `'"$source_path"$'` | '"$url"$' | '"$status"$' | '"$http_status"$' | `'"$expected_text"$'` | '"$notes"$' |\n'
}

check_page() {
  local page="$1"
  local source_path="$2"
  local url="$3"
  local expected_text="$4"
  local source_status="Pass"
  local public_status="Pass"
  local status="Pass"
  local http_status="not checked"
  local notes="Ready"
  local body_path
  local attempt

  if [[ ! -s "$source_path" ]]; then
    source_status="Blocked"
    status="Blocked"
    notes="Local source file is missing or empty."
  elif ! grep -q "$expected_text" "$source_path"; then
    source_status="Blocked"
    status="Blocked"
    notes="Local source is missing expected App Store review text."
  fi

  body_path="$(mktemp)"
  for attempt in 1 2 3; do
    http_status="$(curl -L -s --connect-timeout 10 --max-time "$PUBLIC_PAGE_TIMEOUT_SECONDS" -o "$body_path" -w '%{http_code}' "$url" || true)"
    [[ "$http_status" == "200" ]] && break
    sleep 2
  done

  if [[ "$http_status" != "200" ]]; then
    public_status="Blocked"
    status="Blocked"
    notes="Public URL is not reachable with HTTP 200."
  elif ! grep -q "$expected_text" "$body_path"; then
    public_status="Blocked"
    status="Blocked"
    notes="Public URL does not contain expected App Store review text."
  fi
  rm -f "$body_path"

  if [[ "$status" == "Pass" ]]; then
    ready_count=$((ready_count + 1))
  else
    blocker_count=$((blocker_count + 1))
  fi

  append_row "$page" "$source_path" "$url" "$status" "$http_status" "$expected_text" "$notes"

  if [[ "$source_status" == "Blocked" || "$public_status" == "Blocked" ]]; then
    return 1
  fi
  return 0
}

check_page \
  "Privacy policy" \
  "docs/privacy-policy.html" \
  "https://dannagrace.github.io/FreePrintStudio/privacy-policy.html" \
  "FreePrint Studio Privacy Policy" >/dev/null || true

check_page \
  "Support" \
  "docs/support.html" \
  "https://dannagrace.github.io/FreePrintStudio/support.html" \
  "FreePrint Studio Support" >/dev/null || true

cat >"$output_path" <<EOF
# FreePrint Studio Public Pages Readiness Report

- Generated At: $generated_at
- This report is safe to package: it records public URLs, local source file names, HTTP status, expected page text, and next actions without private Apple account values.
- Validation source in readiness audit: \`Scripts/check_app_store_readiness.sh\`
- Regenerate command: \`Scripts/verify_release.sh public-pages-report\`

## Summary

| Status | Count |
| --- | ---: |
| Ready public page checks | $ready_count |
| Blocking public page checks | $blocker_count |
| Warning public page checks | $warning_count |

## Public page checks

| Page | Local source | Public URL | Status | HTTP status | Expected text | Notes |
| --- | --- | --- | --- | ---: | --- | --- |
$rows
## Required Next Actions

- [ ] Enable GitHub Pages from the repository \`docs\` folder.
- [ ] Verify \`https://dannagrace.github.io/FreePrintStudio/privacy-policy.html\` returns HTTP 200 and contains \`FreePrint Studio Privacy Policy\`.
- [ ] Verify \`https://dannagrace.github.io/FreePrintStudio/support.html\` returns HTTP 200 and contains \`FreePrint Studio Support\`.
- [ ] Keep the App Store metadata privacy and support URLs aligned with these deployed pages.
EOF

printf 'Public pages readiness report generated: %s\n' "$output_path"
