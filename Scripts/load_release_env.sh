#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

release_env_path="${RELEASE_ENV_PATH:-$ROOT_DIR/Config/release.env}"

if [[ -f "$release_env_path" ]]; then
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

  if [[ "$_freeprint_source_status" -ne 0 ]]; then
    printf 'BLOCKED: Release environment is not a valid shell env file: %s\n' "$release_env_path" >&2
    sed 's/^/  /' "$_freeprint_source_log" >&2
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
fi
