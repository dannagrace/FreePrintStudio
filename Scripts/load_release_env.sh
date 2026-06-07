#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

release_env_path="${RELEASE_ENV_PATH:-$ROOT_DIR/Config/release.env}"

if [[ -f "$release_env_path" ]]; then
  set -a
  source "$release_env_path"
  set +a
fi
