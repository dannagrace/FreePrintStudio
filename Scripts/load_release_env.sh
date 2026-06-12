#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

release_env_path="${RELEASE_ENV_PATH:-$ROOT_DIR/Config/release.env}"

if [[ -f "$release_env_path" ]]; then
  if ! _freeprint_permission_status="$(python3 - "$release_env_path" <<'PY'
from pathlib import Path
import stat
import sys

path = Path(sys.argv[1]).expanduser()
try:
    mode = path.stat().st_mode
except Exception:
    print("Release environment permissions could not be checked")
    raise SystemExit(1)

if stat.S_IMODE(mode) & 0o077:
    print("Release environment permissions are too broad; run chmod 600 on the configured file")
    raise SystemExit(1)
PY
  )"; then
    printf 'BLOCKED: %s\n' "$_freeprint_permission_status" >&2
    unset _freeprint_permission_status
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
      return 1
    fi
    exit 1
  fi
  unset _freeprint_permission_status

  _freeprint_release_env_names=(
    DEVELOPMENT_TEAM_ID
    ALLOW_PROVISIONING_UPDATES
    APP_REVIEW_CONTACT_FIRST_NAME
    APP_REVIEW_CONTACT_LAST_NAME
    APP_REVIEW_CONTACT_PHONE
    APP_REVIEW_CONTACT_EMAIL
    APP_STORE_CONNECT_API_KEY_JSON
    ASC_KEY_ID
    ASC_ISSUER_ID
    ASC_KEY_PATH
    FASTLANE_USER
    FASTLANE_ITC_TEAM_ID
    FASTLANE_ITC_TEAM_NAME
    CONFIRM_UPLOAD_APP_PRIVACY
    APP_PRIVACY_SKIP_PUBLISH
    APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT
    IPA_PATH
    TESTFLIGHT_CHANGELOG
    APP_STORE_BUILD_NUMBER
    CONFIRM_SUBMIT_FOR_REVIEW
  )
  _freeprint_preserved_env_names=()
  _freeprint_preserved_env_values=()
  for _freeprint_env_name in "${_freeprint_release_env_names[@]}"; do
    _freeprint_env_value="${!_freeprint_env_name-}"
    if [[ -n "$_freeprint_env_value" ]]; then
      _freeprint_preserved_env_names+=("$_freeprint_env_name")
      _freeprint_preserved_env_values+=("$_freeprint_env_value")
    fi
  done

  _freeprint_restore_errexit=0
  _freeprint_restore_allexport=0
  _freeprint_source_log="${TMPDIR:-/tmp}/freeprintstudio-release-env-source.log"

  case "$-" in
    *e*) _freeprint_restore_errexit=1 ;;
  esac
  case "$-" in
    *a*) _freeprint_restore_allexport=1 ;;
  esac

  set +e
  set -a
  source "$release_env_path" >"$_freeprint_source_log" 2>&1
  _freeprint_source_status="$?"

  if [[ "$_freeprint_restore_allexport" -eq 0 ]]; then
    set +a
  fi
  if [[ "$_freeprint_restore_errexit" -eq 1 ]]; then
    set -e
  fi

  for ((_freeprint_env_index = 0; _freeprint_env_index < ${#_freeprint_preserved_env_names[@]}; _freeprint_env_index++)); do
    printf -v "${_freeprint_preserved_env_names[$_freeprint_env_index]}" \
      '%s' "${_freeprint_preserved_env_values[$_freeprint_env_index]}"
    export "${_freeprint_preserved_env_names[$_freeprint_env_index]}"
  done

  if [[ "$_freeprint_source_status" -ne 0 ]]; then
    printf 'BLOCKED: Release environment is not a valid shell env file\n' >&2
    while IFS= read -r _freeprint_source_line; do
      _freeprint_source_line="${_freeprint_source_line//$release_env_path/[configured release.env]}"
      printf '  %s\n' "$_freeprint_source_line" >&2
    done <"$_freeprint_source_log"
    printf '  Quote values containing spaces, for example APP_REVIEW_CONTACT_FIRST_NAME="Grace Lee".\n' >&2
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
      return "$_freeprint_source_status"
    fi
    exit "$_freeprint_source_status"
  fi

  unset _freeprint_restore_errexit
  unset _freeprint_restore_allexport
  unset _freeprint_source_log
  unset _freeprint_source_status
  unset _freeprint_source_line
  unset _freeprint_release_env_names
  unset _freeprint_preserved_env_names
  unset _freeprint_preserved_env_values
  unset _freeprint_env_name
  unset _freeprint_env_value
  unset _freeprint_env_index
fi
