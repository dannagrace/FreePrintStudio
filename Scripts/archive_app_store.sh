#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

SCHEME="FreePrintStudio"
CONFIGURATION="Release"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/FreePrintStudio.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/build/AppStoreExport}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$ROOT_DIR/Config/ExportOptions-AppStore.plist}"
ARCHIVE_LOG="${ARCHIVE_LOG:-/tmp/freeprintstudio-archive.log}"
EXPORT_LOG="${EXPORT_LOG:-/tmp/freeprintstudio-export.log}"

safe_output_path() {
  local label="$1"
  local requested_path="$2"

  python3 - "$ROOT_DIR" "$label" "$requested_path" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
label = sys.argv[2]
raw_path = Path(sys.argv[3]).expanduser()
candidate = raw_path if raw_path.is_absolute() else root / raw_path
build_dir = (root / "build").resolve()

resolved = candidate.resolve(strict=False)
if resolved == build_dir or build_dir not in resolved.parents:
    print(
        f"Refusing to use {label} path outside build/: {candidate}; outputs must stay inside build/",
        file=sys.stderr,
    )
    raise SystemExit(1)

print(resolved)
PY
}

safe_remove() {
  local path="$1"
  local checked_path

  checked_path="$(safe_output_path "archive cleanup" "$path")"
  rm -rf "$checked_path"
}

project_team_id() {
  xcodebuild \
    -project FreePrintStudio.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null \
    | awk -F'= ' '/DEVELOPMENT_TEAM/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }'
}

TEAM_ID="${DEVELOPMENT_TEAM_ID:-$(project_team_id)}"
if [[ -z "$TEAM_ID" ]]; then
  cat <<'EOF'
Missing Apple Developer Team ID.

Set DEVELOPMENT_TEAM_ID and rerun, for example:

  DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh

The account must be enrolled in the Apple Developer Program and available to Xcode.
EOF
  exit 2
fi
export DEVELOPMENT_TEAM_ID="$TEAM_ID"

if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  printf 'Missing export options plist: %s\n' "$EXPORT_OPTIONS_PLIST"
  exit 1
fi

mkdir -p "$ROOT_DIR/build"
ARCHIVE_PATH="$(safe_output_path "archive" "$ARCHIVE_PATH")"
EXPORT_PATH="$(safe_output_path "export" "$EXPORT_PATH")"

Scripts/preflight_app_store_archive.sh

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"
safe_remove "$ARCHIVE_PATH"

provisioning_args=()
if [[ "${ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
  provisioning_args=(-allowProvisioningUpdates)
fi

printf '== Archive ==\n'
xcodebuild \
  -project FreePrintStudio.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  "${provisioning_args[@]}" \
  archive >"$ARCHIVE_LOG" 2>&1
tail -n 20 "$ARCHIVE_LOG"

printf '\n== Export ==\n'
safe_remove "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  "${provisioning_args[@]}" \
  >"$EXPORT_LOG" 2>&1
tail -n 20 "$EXPORT_LOG"

printf '\n== Validate Export ==\n'
ARCHIVE_PATH="$ARCHIVE_PATH" \
EXPORT_PATH="$EXPORT_PATH" \
  Scripts/validate_app_store_export.sh

printf '\nArchive: %s\n' "$ARCHIVE_PATH"
printf 'Export: %s\n' "$EXPORT_PATH"
