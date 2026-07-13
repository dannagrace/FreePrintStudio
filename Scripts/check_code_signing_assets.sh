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

setting_value() {
  local key="$1"
  xcodebuild \
    -project FreePrintStudio.xcodeproj \
    -scheme FreePrintStudio \
    -configuration Release \
    -showBuildSettings 2>/dev/null \
    | awk -F'= ' -v key="$key" '{
        lhs = $1
        gsub(/^[ \t]+|[ \t]+$/, "", lhs)
        if (lhs == key) {
          gsub(/^[ \t]+|[ \t]+$/, "", $2)
          print $2
          exit
        }
      }'
}

bundle_id="$(setting_value PRODUCT_BUNDLE_IDENTIFIER)"
project_team_id="$(setting_value DEVELOPMENT_TEAM)"
team_id="${DEVELOPMENT_TEAM_ID:-$project_team_id}"
export_method="$(plutil -extract method raw -o - Config/ExportOptions-AppStore.plist 2>/dev/null || true)"

if [[ "$bundle_id" != "com.dannagrace.FreePrintStudio" ]]; then
  block "Unexpected release bundle id: ${bundle_id:-missing}"
fi

if [[ "$export_method" == "app-store-connect" ]]; then
  ok "Export method targets App Store Connect"
else
  block "Export method must be app-store-connect, found: ${export_method:-missing}"
fi

if [[ -z "$team_id" ]]; then
  block "Apple Developer Team ID missing; set DEVELOPMENT_TEAM_ID or configure DEVELOPMENT_TEAM in Xcode"
fi

identity_log="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "$team_id" ]] && grep -Eq "Apple Distribution: .*\($team_id\)" <<<"$identity_log"; then
  ok "Apple Distribution signing identity found for the selected team"
elif grep -q "Apple Distribution" <<<"$identity_log"; then
  if [[ -n "$team_id" ]]; then
    block "Apple Distribution identity exists, but none matched the selected team"
  else
    ok "Apple Distribution signing identity found"
  fi
else
  block "No valid Apple Distribution code signing identity found in the keychain"
fi

profile_paths=()
profile_directories=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)
for profiles_dir in "${profile_directories[@]}"; do
  if [[ ! -d "$profiles_dir" ]]; then
    continue
  fi

  while IFS= read -r -d '' profile_path; do
    profile_paths+=("$profile_path")
  done < <(find "$profiles_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print0 2>/dev/null)
done

if (( ${#profile_paths[@]} == 0 )); then
  block "No provisioning profiles found under Xcode UserData or ~/Library/MobileDevice/Provisioning Profiles"
elif [[ -n "$team_id" && -n "$bundle_id" ]]; then
  if ! python3 - "$bundle_id" "$team_id" "${profile_paths[@]}" <<'PY'
import plistlib
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

bundle_id = sys.argv[1]
team_id = sys.argv[2]
profile_paths = [Path(path) for path in sys.argv[3:]]
expected_application_identifier = f"{team_id}.{bundle_id}"
now = datetime.now(timezone.utc)
matches = []

for path in profile_paths:
    try:
        result = subprocess.run(
            ["security", "cms", "-D", "-i", str(path)],
            check=True,
            capture_output=True,
        )
        profile = plistlib.loads(result.stdout)
    except Exception:
        print("INFO: Ignoring unreadable provisioning profile during signing validation")
        continue

    entitlements = profile.get("Entitlements", {})
    application_identifier = entitlements.get("application-identifier", "")
    team_ids = profile.get("TeamIdentifier", [])
    expiration_date = profile.get("ExpirationDate")
    provisioned_devices = profile.get("ProvisionedDevices")
    get_task_allow = entitlements.get("get-task-allow")

    if expiration_date is not None:
        if expiration_date.tzinfo is None:
            expiration_date = expiration_date.replace(tzinfo=timezone.utc)
        if expiration_date <= now:
            continue

    if team_id not in team_ids:
        continue
    if application_identifier != expected_application_identifier:
        continue
    if provisioned_devices:
        # App Store Connect distribution profiles do not list devices; development/ad hoc profiles do.
        continue
    if get_task_allow:
        continue

    matches.append(True)

if matches:
    print(f"OK: Matching App Store provisioning profile found for {bundle_id}")
else:
    print(
        "BLOCKED: No matching App Store provisioning profile found for "
        f"{bundle_id} and the selected team; profile must not contain ProvisionedDevices"
    )
    sys.exit(1)
PY
  then
    failures=$((failures + 1))
  fi
fi

if (( failures > 0 )); then
  exit 1
fi
