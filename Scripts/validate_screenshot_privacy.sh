#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCREENSHOT_DIRS=(
  "AppStore/Screenshots"
  "fastlane/screenshots/en-US"
)

FORBIDDEN_METADATA_KEYS=(
  "kMDItemLatitude"
  "kMDItemLongitude"
  "kMDItemAltitude"
  "kMDItemGPSDateStamp"
  "kMDItemCity"
  "kMDItemStateOrProvince"
  "kMDItemCountry"
  "kMDItemAcquisitionMake"
  "kMDItemAcquisitionModel"
  "kMDItemCameraOwner"
  "kMDItemAuthors"
  "kMDItemAuthorEmailAddresses"
  "kMDItemCreator"
  "kMDItemOrganizations"
  "kMDItemWhereFroms"
)

failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

metadata_value_is_present() {
  local value="$1"
  local compact
  compact="$(printf '%s' "$value" | tr -d '[:space:]' | tr -d '\0')"
  [[ -n "$compact" && "$compact" != "(null)" && "$compact" != "()" ]]
}

check_screenshot_metadata() {
  local screenshot_path="$1"
  local key
  local value

  for key in "${FORBIDDEN_METADATA_KEYS[@]}"; do
    if ! value="$(mdls -raw -name "$key" "$screenshot_path" 2>/dev/null | tr -d '\0')"; then
      fail "Could not read $key from $screenshot_path"
      continue
    fi

    if metadata_value_is_present "$value"; then
      fail "$screenshot_path contains forbidden privacy metadata $key"
    fi
  done
}

if ! command -v mdls >/dev/null 2>&1; then
  fail "mdls is required to validate screenshot privacy metadata"
fi

if (( failures == 0 )); then
  screenshot_count=0
  for screenshot_dir in "${SCREENSHOT_DIRS[@]}"; do
    if [[ ! -d "$screenshot_dir" ]]; then
      fail "Screenshot directory missing: $screenshot_dir"
      continue
    fi

    while IFS= read -r -d '' screenshot_path; do
      screenshot_count=$((screenshot_count + 1))
      check_screenshot_metadata "$screenshot_path"
    done < <(find "$screenshot_dir" -maxdepth 1 -type f -name '*.jpg' -print0 | sort -z)
  done

  if (( screenshot_count == 0 )); then
    fail "No App Store screenshot JPG files found for privacy metadata validation"
  fi
fi

if (( failures > 0 )); then
  exit 1
fi

printf 'Screenshot privacy metadata validation passed.\n'
