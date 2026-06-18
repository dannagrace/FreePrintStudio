#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

block() {
  printf 'BLOCKED: %s\n' "$1"
  exit 1
}

ok() {
  printf 'OK: %s\n' "$1"
}

PLACEHOLDER_BUILD_VALUES=(
  "PROCESSED_BUILD_NUMBER"
  "YOUR_BUILD_NUMBER"
  "TODO"
  "TBD"
)

looks_like_placeholder_build() {
  local value="$1"
  local lower_value
  local placeholder

  [[ -z "$value" ]] && return 1
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  for placeholder in "${PLACEHOLDER_BUILD_VALUES[@]}"; do
    [[ "$value" == "$placeholder" ]] && return 0
  done

  [[ "$value" == *"YOUR_"* ]] && return 0
  [[ "$value" == *"XXXXXXXXXX"* ]] && return 0
  [[ "$lower_value" == *"example.com"* ]] && return 0
  [[ "$lower_value" == *@example.* ]] && return 0
  [[ "$lower_value" == *"todo"* ]] && return 0
  [[ "$lower_value" == *"tbd"* ]] && return 0
  [[ "$lower_value" == *"placeholder"* ]] && return 0

  return 1
}

bundle_check() {
  local log_path="$1"
  python3 - "$log_path" <<'PY'
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

run_spaceship_ruby() {
  if [[ -f Gemfile.lock ]] && bundle_check /tmp/freeprintstudio-bundle-check.log; then
    bundle exec ruby - "$@"
    return
  fi

  if ruby -e 'require "spaceship"' >/dev/null 2>&1; then
    ruby - "$@"
    return
  fi

  if command -v fastlane >/dev/null 2>&1; then
    local fastlane_bin
    local libexec_fastlane
    local libexec_dir
    local homebrew_ruby
    local gem_home

    fastlane_bin="$(command -v fastlane)"
    libexec_fastlane="$(
      sed -n 's/.*exec "\([^"]*\/libexec\/bin\/fastlane\)".*/\1/p' "$fastlane_bin" 2>/dev/null | head -n 1
    )"

    if [[ -n "$libexec_fastlane" ]]; then
      libexec_dir="${libexec_fastlane%/bin/fastlane}"
      homebrew_ruby="/opt/homebrew/opt/ruby/bin/ruby"
      gem_home="${FASTLANE_GEM_HOME:-$HOME/.local/share/fastlane/4.0.0}"

      if [[ -x "$homebrew_ruby" ]]; then
        GEM_HOME="$gem_home" \
        GEM_PATH="$gem_home:$libexec_dir" \
        PATH="/opt/homebrew/opt/ruby/bin:$libexec_dir/bin:$PATH" \
          "$homebrew_ruby" - "$@"
        return
      fi

      GEM_HOME="$gem_home" GEM_PATH="$gem_home:$libexec_dir" ruby - "$@"
      return
    fi
  fi

  block "Unable to load Fastlane Spaceship Ruby libraries; run Scripts/install_release_dependencies.sh or brew install fastlane"
}

selected_build_number="${APP_STORE_BUILD_NUMBER:-}"
skip_build_check="${APP_STORE_CONNECT_SKIP_BUILD_CHECK:-}"

if [[ "$skip_build_check" != "1" && -z "$selected_build_number" ]]; then
  block "APP_STORE_BUILD_NUMBER is missing; set it to the processed App Store Connect build number"
fi

if looks_like_placeholder_build "$selected_build_number"; then
  block "APP_STORE_BUILD_NUMBER still uses a placeholder value; replace it with the processed App Store Connect build number"
fi

if [[ -n "$selected_build_number" && ! "$selected_build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  block "APP_STORE_BUILD_NUMBER must be a processed App Store Connect build number, for example 42 or 1.0.1"
fi

Scripts/check_app_store_connect_credentials.sh >/tmp/freeprintstudio-asc-credentials.log 2>&1 || {
  sed 's/^/  /' /tmp/freeprintstudio-asc-credentials.log
  block "App Store Connect API credentials are not configured"
}
ok "App Store Connect API credentials are syntactically configured"

app_identifier="${APP_IDENTIFIER:-$(setting_value PRODUCT_BUNDLE_IDENTIFIER)}"
app_version="${APP_VERSION:-$(setting_value MARKETING_VERSION)}"

[[ -n "$app_identifier" ]] || block "Could not determine PRODUCT_BUNDLE_IDENTIFIER from the Xcode project"
[[ -n "$app_version" ]] || block "Could not determine MARKETING_VERSION from the Xcode project"

run_spaceship_ruby "$app_identifier" "$app_version" "$selected_build_number" "$skip_build_check" <<'RUBY'
require "json"
require "pathname"
require "spaceship"

app_identifier = ARGV.fetch(0)
app_version = ARGV.fetch(1)
selected_build_number = ARGV.fetch(2, "").strip
skip_build_check = ARGV.fetch(3, "").strip == "1"

def ok(message)
  puts("OK: #{message}")
end

def block(message)
  puts("BLOCKED: #{message}")
  exit(1)
end

def api_token_from_env
  api_key_json = ENV.fetch("APP_STORE_CONNECT_API_KEY_JSON", "").strip
  unless api_key_json.empty?
    api_key_json_path = Pathname.new(api_key_json).expand_path
    payload = JSON.parse(File.read(api_key_json_path))
    if payload["key_filepath"].to_s.strip.empty?
      return Spaceship::ConnectAPI::Token.from(hash: payload)
    end

    raw_key_path = Pathname.new(payload.fetch("key_filepath"))
    unless raw_key_path.absolute?
      raw_key_path = api_key_json_path.dirname + raw_key_path
    end
    key_path = raw_key_path.expand_path.to_s
    return Spaceship::ConnectAPI::Token.create(
      key_id: payload.fetch("key_id"),
      issuer_id: payload["issuer_id"],
      filepath: key_path,
      duration: payload["duration"] || 1200,
      in_house: payload["in_house"] || false
    )
  end

  key_id = ENV.fetch("ASC_KEY_ID", "").strip
  issuer_id = ENV.fetch("ASC_ISSUER_ID", "").strip
  key_path = ENV.fetch("ASC_KEY_PATH", "").strip
  if key_id.empty? || issuer_id.empty? || key_path.empty?
    block("Set APP_STORE_CONNECT_API_KEY_JSON, or ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH")
  end

  Spaceship::ConnectAPI::Token.create(
    key_id: key_id,
    issuer_id: issuer_id,
    filepath: key_path,
    duration: 1200,
    in_house: false
  )
end

begin
  Spaceship::ConnectAPI.token = api_token_from_env

  app = Spaceship::ConnectAPI::App.find(app_identifier)
  block("App Store Connect app record not found for bundle ID #{app_identifier}") if app.nil?
  ok("App Store Connect app record found: #{app.name} (#{app.bundle_id})")

  versions = app.get_app_store_versions(
    filter: { platform: Spaceship::ConnectAPI::Platform::IOS },
    includes: Spaceship::ConnectAPI::AppStoreVersion::ESSENTIAL_INCLUDES
  )
  version = versions.find { |candidate| candidate.version_string == app_version }
  if version.nil?
    known_versions = versions.map(&:version_string).compact.uniq.sort.join(", ")
    suffix = known_versions.empty? ? "" : "; available versions: #{known_versions}"
    block("App Store Connect version #{app_version} for iOS was not found#{suffix}")
  end
  ok("App Store Connect version #{version.version_string} found with state #{version.app_version_state || version.app_store_state || "UNKNOWN"}")

  if skip_build_check
    ok("Skipping TestFlight build lookup because APP_STORE_CONNECT_SKIP_BUILD_CHECK=1")
    exit(0)
  end

  build_filter = {
    app_id: app.id,
    version: app_version,
    platform: Spaceship::ConnectAPI::Platform::IOS,
    limit: 10
  }
  build_filter[:build_number] = selected_build_number unless selected_build_number.empty?
  builds = Spaceship::ConnectAPI::Build.all(**build_filter)

  build = builds.find { |candidate| candidate.processing_state == Spaceship::ConnectAPI::Build::ProcessingState::VALID } || builds.first
  if build.nil?
    build_label = selected_build_number.empty? ? "any build" : "build #{selected_build_number}"
    block("No TestFlight #{build_label} found for iOS version #{app_version}")
  end

  if build.processing_state != Spaceship::ConnectAPI::Build::ProcessingState::VALID
    block("TestFlight build #{build.version} is not processed yet: #{build.processing_state}")
  end

  if !selected_build_number.empty? && build.version != selected_build_number
    block("Selected build mismatch: expected #{selected_build_number}, found #{build.version}")
  end

  ok("Processed TestFlight build found: #{build.version} for version #{app_version}")
rescue SystemExit
  raise
rescue StandardError => error
  block("App Store Connect state query failed: #{error.class}: #{error.message}")
end
RUBY
