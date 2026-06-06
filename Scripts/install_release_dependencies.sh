#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v bundle >/dev/null 2>&1; then
  printf 'Bundler is not available. Install Bundler before release dependency setup.\n'
  printf 'Alternatively, install Homebrew Fastlane with: brew install fastlane\n'
  exit 1
fi

bundler_version="$(bundle -v | awk '{ print $3 }')"
case "$bundler_version" in
  1.*)
    bundle config --local path vendor/bundle
    ;;
  *)
    bundle config set --local path vendor/bundle
    ;;
esac

BUNDLE_TIMEOUT="${BUNDLE_TIMEOUT:-20}" \
BUNDLE_RETRY="${BUNDLE_RETRY:-3}" \
bundle install

Scripts/run_fastlane.sh --version
