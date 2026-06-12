#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

release_env_path="${RELEASE_ENV_PATH:-$ROOT_DIR/Config/release.env}"
manual_evidence_path="${MANUAL_RELEASE_VERIFICATION_PATH:-$ROOT_DIR/Config/manual-release-verification.env}"
force=0

usage() {
  cat <<'EOF'
Usage: Scripts/bootstrap_release_inputs.sh [--force]

Creates the private, git-ignored release input files used before App Store submission:
  - Config/release.env
  - Config/manual-release-verification.env

Options:
  --force  overwrite existing private input files after backing up any real values
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

ensure_repo_private_path() {
  local path="$1"
  local label="$2"
  local relative_path

  if [[ "$path" != "$ROOT_DIR/"* ]]; then
    printf 'Refusing to bootstrap %s outside this repository: %s\n' "$label" "$path" >&2
    exit 1
  fi

  relative_path="${path#"$ROOT_DIR/"}"
  if ! git check-ignore -q "$relative_path"; then
    printf 'Refusing to create %s because it is not ignored by git: %s\n' "$label" "$relative_path" >&2
    exit 1
  fi
}

copy_private_template() {
  local source_path="$1"
  local target_path="$2"
  local label="$3"

  if [[ -e "$target_path" && "$force" != "1" ]]; then
    printf '%s already exists: %s\n' "$label" "$target_path"
    printf 'Leaving it unchanged. Use --force only after backing up private values.\n'
    return
  fi

  mkdir -p "$(dirname "$target_path")"
  umask 077
  cp "$source_path" "$target_path"
  chmod 600 "$target_path"
  printf 'Created private %s: %s\n' "$label" "$target_path"
}

ensure_repo_private_path "$release_env_path" "release environment"
ensure_repo_private_path "$manual_evidence_path" "manual release verification evidence"

release_args=()
if [[ "$force" == "1" ]]; then
  release_args+=(--force)
fi
if (( ${#release_args[@]} > 0 )); then
  RELEASE_ENV_PATH="$release_env_path" Scripts/bootstrap_release_env.sh "${release_args[@]}"
else
  RELEASE_ENV_PATH="$release_env_path" Scripts/bootstrap_release_env.sh
fi

copy_private_template \
  "$ROOT_DIR/Config/manual-release-verification.env.example" \
  "$manual_evidence_path" \
  "manual release verification evidence"

printf '\nNext release input and submission commands:\n'
printf '  1. Fill real Apple signing, App Review contact, and App Store Connect values in %s\n' "$release_env_path"
printf '  2. Record real iPhone, AirPrint, iPad, and TestFlight evidence in %s after testing\n' "$manual_evidence_path"
printf '  3. Run Scripts/print_release_input_status.sh\n'
printf '  4. Run Scripts/validate_release_env.sh\n'
printf '  5. Run APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh\n'
printf '  6. Run Scripts/check_app_store_readiness.sh\n'
printf '  7. Run Scripts/verify_release.sh testflight-dependencies-preflight\n'
printf '  8. Run Scripts/preflight_app_store_archive.sh\n'
printf '  9. Run DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh\n'
printf '  10. Run Scripts/preflight_testflight_upload.sh\n'
printf '  11. Run ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight\n'
printf '  12. Run APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state\n'
printf '  13. Run APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh\n'
printf '  14. Run APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review\n'
