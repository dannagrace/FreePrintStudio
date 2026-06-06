#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if bundle check >/tmp/freeprintstudio-bundle-check.log 2>&1; then
  exec bundle exec fastlane "$@"
fi

if command -v fastlane >/dev/null 2>&1; then
  exec fastlane "$@"
fi

printf 'Fastlane is not available.\n'
printf 'Install it with one of these commands:\n'
printf '  Scripts/install_release_dependencies.sh\n'
printf '  brew install fastlane\n'
exit 1
