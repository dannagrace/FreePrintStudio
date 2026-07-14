#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

case "${APP_STORE_CONNECT_SUBMISSION_MODE:-api}" in
  manual)
    Scripts/validate_manual_app_store_connect_state.sh
    ;;
  api)
    Scripts/check_app_store_connect_credentials.sh
    Scripts/check_app_store_connect_state.sh
    ;;
  *)
    printf 'BLOCKED: APP_STORE_CONNECT_SUBMISSION_MODE must be manual or api\n'
    exit 1
    ;;
esac

