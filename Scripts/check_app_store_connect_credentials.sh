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

validate_format() {
  local label="$1"
  local value="$2"
  local pattern="$3"
  local message="$4"

  if [[ "$value" =~ $pattern ]]; then
    ok "$label format is valid"
  else
    block "$message"
  fi
}

if [[ -n "${APP_STORE_CONNECT_API_KEY_JSON:-}" ]]; then
  if [[ -f "$APP_STORE_CONNECT_API_KEY_JSON" ]]; then
    python3 - "$APP_STORE_CONNECT_API_KEY_JSON" <<'PY'
import json
from pathlib import Path
import re
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

format_errors = []
if not re.fullmatch(r"[A-Z0-9]{10}", str(payload.get("key_id", ""))):
    format_errors.append("BLOCKED: APP_STORE_CONNECT_API_KEY_JSON key_id must be a 10-character App Store Connect API key id")
if not re.fullmatch(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", str(payload.get("issuer_id", ""))):
    format_errors.append("BLOCKED: APP_STORE_CONNECT_API_KEY_JSON issuer_id must be an App Store Connect issuer UUID")
if format_errors:
    print("\n".join(format_errors))
    sys.exit(1)

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
  if [[ -n "${ASC_KEY_ID:-}" ]]; then
    validate_format \
      "ASC_KEY_ID" \
      "$ASC_KEY_ID" \
      '^[A-Z0-9]{10}$' \
      "ASC_KEY_ID must be a 10-character App Store Connect API key id"
  else
    block "ASC_KEY_ID is missing"
  fi

  if [[ -n "${ASC_ISSUER_ID:-}" ]]; then
    validate_format \
      "ASC_ISSUER_ID" \
      "$ASC_ISSUER_ID" \
      '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' \
      "ASC_ISSUER_ID must be an App Store Connect issuer UUID"
  else
    block "ASC_ISSUER_ID is missing"
  fi

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
