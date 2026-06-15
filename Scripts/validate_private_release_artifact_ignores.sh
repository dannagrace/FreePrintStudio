#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${FREEPRINTSTUDIO_PRIVATE_ARTIFACT_IGNORE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'FAIL: private release artifact ignore validation requires a git worktree: %s\n' "$ROOT_DIR"
  exit 1
fi

failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

is_private_release_artifact_path() {
  local tracked_path="$1"

  [[ "$tracked_path" == "Config/release.env" ]] && return 0
  [[ "$tracked_path" == Config/release.env.bak.* ]] && return 0
  [[ "$tracked_path" == "Config/manual-release-verification.env" ]] && return 0
  [[ "$tracked_path" == Config/manual-release-verification.env.bak.* ]] && return 0
  [[ "$tracked_path" == "fastlane-api-key.json" ]] && return 0
  [[ "$tracked_path" == "Config/fastlane-api-key.json" ]] && return 0
  [[ "$tracked_path" == *.p8 ]] && return 0
  [[ "$tracked_path" == *.p12 ]] && return 0
  [[ "$tracked_path" == *.cer ]] && return 0
  [[ "$tracked_path" == *.mobileprovision ]] && return 0
  [[ "$tracked_path" == *.provisionprofile ]] && return 0
  [[ "$tracked_path" == *.ipa ]] && return 0
  [[ "$tracked_path" == *.xcarchive ]] && return 0
  [[ "$tracked_path" == *.xcarchive/* ]] && return 0

  return 1
}

required_ignored_samples=(
  "Config/release.env"
  "Config/release.env.bak.TEST"
  "Config/manual-release-verification.env"
  "Config/manual-release-verification.env.bak.TEST"
  "AuthKey_TESTKEY123.p8"
  "Certificates/AppleDistribution.p12"
  "Certificates/AppleDistribution.cer"
  "Profiles/FreePrintStudio.mobileprovision"
  "Profiles/FreePrintStudio.provisionprofile"
  "build/AppStoreExport/FreePrintStudio.ipa"
  "FreePrintStudio.xcarchive"
  "fastlane-api-key.json"
  "Config/fastlane-api-key.json"
)

private_permission_patterns=(
  "Config/release.env"
  "Config/release.env.bak.*"
  "Config/manual-release-verification.env"
  "Config/manual-release-verification.env.bak.*"
  "fastlane-api-key.json"
  "Config/fastlane-api-key.json"
  "*.p8"
  "*.p12"
  "*.cer"
  "*.mobileprovision"
  "*.provisionprofile"
  "*.ipa"
)

for sample_path in "${required_ignored_samples[@]}"; do
  if ! git check-ignore -q -- "$sample_path"; then
    fail "private release artifact sample is not ignored by git: $sample_path"
  fi
done

check_private_artifact_permissions() {
  local path="$1"
  local relative_path
  local mode

  [[ -f "$path" ]] || return
  relative_path="${path#./}"

  mode="$(stat -f '%Lp' "$path" 2>/dev/null || true)"
  if [[ -z "$mode" ]]; then
    fail "$relative_path permissions could not be checked"
    return
  fi

  if (( (8#$mode & 8#077) != 0 )); then
    fail "$relative_path permissions are too broad; run chmod 600 $relative_path"
  fi
}

for pattern in "${private_permission_patterns[@]}"; do
  while IFS= read -r -d '' private_path; do
    check_private_artifact_permissions "$private_path"
  done < <(find . -path "./$pattern" -type f -print0 2>/dev/null)
done

tracked_private_paths="$(
  git ls-files -z \
    | while IFS= read -r -d '' tracked_path; do
        if is_private_release_artifact_path "$tracked_path"; then
          printf '%s\n' "$tracked_path"
        fi
      done
)"

if [[ -n "$tracked_private_paths" ]]; then
  printf '%s\n' "$tracked_private_paths"
  fail "private release artifacts must not be tracked by git"
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'Private release artifact ignore validation passed.\n'
