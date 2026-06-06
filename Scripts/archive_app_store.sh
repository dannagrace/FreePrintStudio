#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="FreePrintStudio"
CONFIGURATION="Release"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/FreePrintStudio.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/build/AppStoreExport}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$ROOT_DIR/Config/ExportOptions-AppStore.plist}"
ARCHIVE_LOG="${ARCHIVE_LOG:-/tmp/freeprintstudio-archive.log}"
EXPORT_LOG="${EXPORT_LOG:-/tmp/freeprintstudio-export.log}"

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

  DEVELOPMENT_TEAM_ID=ABCDE12345 Scripts/archive_app_store.sh

The account must be enrolled in the Apple Developer Program and available to Xcode.
EOF
  exit 2
fi

if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  printf 'Missing export options plist: %s\n' "$EXPORT_OPTIONS_PLIST"
  exit 1
fi

Scripts/verify_release.sh

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"
rm -rf "$ARCHIVE_PATH"

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
rm -rf "$EXPORT_PATH"
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

printf '\nArchive: %s\n' "$ARCHIVE_PATH"
printf 'Export: %s\n' "$EXPORT_PATH"
