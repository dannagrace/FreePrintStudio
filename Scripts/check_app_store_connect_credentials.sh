#!/usr/bin/env bash
set -euo pipefail

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
import sys

path = sys.argv[1]
try:
    payload = json.load(open(path, encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"BLOCKED: APP_STORE_CONNECT_API_KEY_JSON is not valid JSON: {exc}")

required_any_key = "key" in payload or "key_filepath" in payload
missing = [name for name in ("key_id", "issuer_id") if not payload.get(name)]
if missing or not required_any_key:
    fields = ", ".join(missing + ([] if required_any_key else ["key or key_filepath"]))
    raise SystemExit(f"BLOCKED: APP_STORE_CONNECT_API_KEY_JSON is missing {fields}")
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
