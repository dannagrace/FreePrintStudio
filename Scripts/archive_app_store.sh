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
ARCHIVE_CODE_SIGN_IDENTITY="${ARCHIVE_CODE_SIGN_IDENTITY:-Apple Distribution}"

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

secure_private_release_artifacts() {
  if [[ -d "$ARCHIVE_PATH" ]]; then
    find "$ARCHIVE_PATH" -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -exec chmod 600 {} +
  fi
  if [[ -d "$EXPORT_PATH" ]]; then
    find "$EXPORT_PATH" -type f -name '*.ipa' -exec chmod 600 {} +
  fi
}

project_team_id() {
  xcodebuild \
    -project FreePrintStudio.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null \
    | awk -F'= ' '/DEVELOPMENT_TEAM/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }'
}

project_bundle_id() {
  xcodebuild \
    -project FreePrintStudio.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null \
    | awk -F'= ' '{
        lhs = $1
        gsub(/^[ \t]+|[ \t]+$/, "", lhs)
        if (lhs == "PRODUCT_BUNDLE_IDENTIFIER") {
          gsub(/^[ \t]+|[ \t]+$/, "", $2)
          print $2
          exit
        }
      }'
}

matching_app_store_profile_name() {
  local bundle_id="$1"
  local team_id="$2"

  python3 - "$bundle_id" "$team_id" \
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
    "$HOME/Library/MobileDevice/Provisioning Profiles" <<'PY'
import plistlib
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

bundle_id = sys.argv[1]
team_id = sys.argv[2]
expected_identifier = f"{team_id}.{bundle_id}"
now = datetime.now(timezone.utc)
matches = []

for directory_text in sys.argv[3:]:
    directory = Path(directory_text)
    if not directory.is_dir():
        continue
    paths = list(directory.glob("*.mobileprovision"))
    paths.extend(directory.glob("*.provisionprofile"))
    for path in paths:
        try:
            result = subprocess.run(
                ["security", "cms", "-D", "-i", str(path)],
                check=True,
                capture_output=True,
            )
            profile = plistlib.loads(result.stdout)
        except Exception:
            continue

        entitlements = profile.get("Entitlements", {})
        expiration = profile.get("ExpirationDate")
        if expiration is None:
            continue
        if expiration.tzinfo is None:
            expiration = expiration.replace(tzinfo=timezone.utc)
        if expiration <= now:
            continue
        if team_id not in profile.get("TeamIdentifier", []):
            continue
        if entitlements.get("application-identifier") != expected_identifier:
            continue
        if profile.get("ProvisionedDevices") or entitlements.get("get-task-allow"):
            continue
        if profile.get("Name"):
            matches.append((expiration, profile["Name"]))

if matches:
    print(max(matches)[1])
PY
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
BUNDLE_ID="$(project_bundle_id)"
PROFILE_SPECIFIER="${APP_STORE_PROVISIONING_PROFILE_SPECIFIER:-$(matching_app_store_profile_name "$BUNDLE_ID" "$TEAM_ID")}"
if [[ -z "$PROFILE_SPECIFIER" ]]; then
  printf 'Missing matching App Store provisioning profile for the selected bundle and team.\n'
  printf 'Install the profile or set APP_STORE_PROVISIONING_PROFILE_SPECIFIER and rerun.\n'
  exit 2
fi

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
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$ARCHIVE_CODE_SIGN_IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_SPECIFIER" \
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
secure_private_release_artifacts

printf '\n== Validate Export ==\n'
ARCHIVE_PATH="$ARCHIVE_PATH" \
EXPORT_PATH="$EXPORT_PATH" \
  Scripts/validate_app_store_export.sh

printf '\nArchive: %s\n' "$ARCHIVE_PATH"
printf 'Export: %s\n' "$EXPORT_PATH"
