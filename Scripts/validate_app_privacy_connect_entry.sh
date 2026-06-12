#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

value="${APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT:-}"

if [[ "$value" == "1" ]]; then
  printf 'OK: App Privacy Details confirmed in App Store Connect\n'
  exit 0
fi

if [[ -n "$value" ]]; then
  printf 'BLOCKED: APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT must be 1 after App Store Connect matches AppStore/app_privacy_details.json\n'
else
  printf 'BLOCKED: Set APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 after App Store Connect App Privacy Details match AppStore/app_privacy_details.json\n'
fi

if [[ -n "${FASTLANE_USER:-}" ]]; then
  printf '  Run CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details, verify App Store Connect, then set APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1.\n'
else
  printf '  Enter the App Privacy Details manually in App Store Connect from AppStore/app_privacy_details.json, then set APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1.\n'
fi

exit 1
