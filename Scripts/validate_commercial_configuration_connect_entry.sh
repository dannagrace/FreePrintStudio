#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

value="${APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT:-}"

if [[ "$value" == "1" ]]; then
  printf 'OK: Commercial configuration confirmed in App Store Connect\n'
  exit 0
fi

if [[ -n "$value" ]]; then
  printf 'BLOCKED: APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT must be 1 after App Store Connect pricing, availability, and release options match AppStore/commercial-configuration.md\n'
else
  printf 'BLOCKED: Set APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1 after App Store Connect Pricing, Availability, monetization, release option, and phased release match AppStore/commercial-configuration.md\n'
fi

printf '  Apply AppStore/commercial-configuration.md in App Store Connect, verify Pricing is Free, Availability is all countries or regions, In-App Purchases/Subscriptions/Advertising are none, Release option is manual release after approval, Phased release is off, then set APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1.\n'

exit 1
