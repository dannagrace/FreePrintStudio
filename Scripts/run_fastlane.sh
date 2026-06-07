#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bundle_check() {
  python3 - /tmp/freeprintstudio-bundle-check.log <<'PY'
import subprocess
import sys

log_path = sys.argv[1]
with open(log_path, "w") as log:
    try:
        result = subprocess.run(
            ["bundle", "check"],
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=15,
        )
    except FileNotFoundError:
        sys.exit(127)
    except subprocess.TimeoutExpired:
        log.write("bundle check timed out after 15 seconds\n")
        sys.exit(124)
sys.exit(result.returncode)
PY
}

if [[ -f Gemfile.lock ]] && bundle_check; then
  exec bundle exec fastlane "$@"
fi

if command -v fastlane >/dev/null 2>&1; then
  export FASTLANE_SKIP_UPDATE_CHECK=1
  export FASTLANE_HIDE_CHANGELOG=1
  export SKIP_SLOW_FASTLANE_WARNING=1
  exec fastlane "$@"
fi

printf 'Fastlane is not available.\n'
printf 'Install it with one of these commands:\n'
printf '  Scripts/install_release_dependencies.sh\n'
printf '  brew install fastlane\n'
exit 1
