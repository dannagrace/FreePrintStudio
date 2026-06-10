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

if [[ -n "${APP_STORE_CONNECT_API_KEY_JSON:-}" ]]; then
  if [[ -f "$APP_STORE_CONNECT_API_KEY_JSON" ]]; then
    python3 - "$APP_STORE_CONNECT_API_KEY_JSON" <<'PY'
import json
from pathlib import Path
import sys

path = sys.argv[1]
try:
    json_path = Path(path)
    payload = json.load(open(json_path, encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"BLOCKED: APP_STORE_CONNECT_API_KEY_JSON is not valid JSON: {exc}")

required_any_key = "key" in payload or "key_filepath" in payload
missing = [name for name in ("key_id", "issuer_id") if not payload.get(name)]
if missing or not required_any_key:
    fields = ", ".join(missing + ([] if required_any_key else ["key or key_filepath"]))
    raise SystemExit(f"BLOCKED: APP_STORE_CONNECT_API_KEY_JSON is missing {fields}")

inline_key = str(payload.get("key", "")).strip()
key_filepath = str(payload.get("key_filepath", "")).strip()
if inline_key and "BEGIN PRIVATE KEY" not in inline_key:
    raise SystemExit("BLOCKED: APP_STORE_CONNECT_API_KEY_JSON key does not look like an App Store Connect .p8 private key")
if key_filepath:
    key_path = Path(key_filepath).expanduser()
    if not key_path.is_absolute():
        key_path = (json_path.parent / key_path).resolve()
    if not key_path.is_file():
        raise SystemExit(f"BLOCKED: APP_STORE_CONNECT_API_KEY_JSON key_filepath does not exist: {key_path}")
    try:
        key_text = key_path.read_text(encoding="utf-8")
    except Exception as exc:
        raise SystemExit(f"BLOCKED: APP_STORE_CONNECT_API_KEY_JSON key_filepath is not readable: {exc}")
    if "BEGIN PRIVATE KEY" not in key_text:
        raise SystemExit("BLOCKED: APP_STORE_CONNECT_API_KEY_JSON key_filepath does not look like an App Store Connect .p8 private key")
print("OK: Fastlane App Store Connect API JSON is present")
PY
  else
    block "APP_STORE_CONNECT_API_KEY_JSON does not exist: $APP_STORE_CONNECT_API_KEY_JSON"
  fi
else
  [[ -n "${ASC_KEY_ID:-}" ]] && ok "ASC_KEY_ID is set" || block "ASC_KEY_ID is missing"
  [[ -n "${ASC_ISSUER_ID:-}" ]] && ok "ASC_ISSUER_ID is set" || block "ASC_ISSUER_ID is missing"

  if [[ -z "${ASC_KEY_PATH:-}" ]]; then
    block "ASC_KEY_PATH is missing"
  elif [[ ! -f "$ASC_KEY_PATH" ]]; then
    block "ASC_KEY_PATH does not exist: $ASC_KEY_PATH"
  elif ! grep -q "BEGIN PRIVATE KEY" "$ASC_KEY_PATH"; then
    block "ASC_KEY_PATH does not look like an App Store Connect .p8 private key"
  else
    ok "ASC_KEY_PATH points to an App Store Connect private key"
  fi
fi

if (( failures > 0 )); then
  printf '\nSet either:\n'
  printf '  APP_STORE_CONNECT_API_KEY_JSON=/absolute/path/to/fastlane-api-key.json\n'
  printf 'or:\n'
  printf '  ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=UUID ASC_KEY_PATH=/absolute/path/AuthKey_XXXXXXXXXX.p8\n'
  exit 1
fi
