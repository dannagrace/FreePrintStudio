#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

release_env_path="${RELEASE_ENV_PATH:-$ROOT_DIR/Config/release.env}"
force=0
print_only=0

usage() {
  cat <<'EOF'
Usage: Scripts/bootstrap_release_env.sh [--force] [--print]

Creates the private, git-ignored Config/release.env skeleton used by release scripts.

Options:
  --force  overwrite an existing Config/release.env
  --print  print the skeleton to stdout without writing a file
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=1
      ;;
    --print)
      print_only=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

write_template() {
  cat <<'EOF'
# FreePrint Studio private release environment.
# Fill real values here only. This file is git-ignored and should never be committed.

# Apple signing.
DEVELOPMENT_TEAM_ID=
ALLOW_PROVISIONING_UPDATES=1

# App Store Review contact details.
APP_REVIEW_CONTACT_FIRST_NAME=
APP_REVIEW_CONTACT_LAST_NAME=
APP_REVIEW_CONTACT_PHONE=
APP_REVIEW_CONTACT_EMAIL=

# Option A: Fastlane App Store Connect API JSON.
APP_STORE_CONNECT_API_KEY_JSON=

# Option B: App Store Connect API key triplet.
ASC_KEY_ID=
ASC_ISSUER_ID=
ASC_KEY_PATH=

# App Privacy Details upload through the Fastlane Apple ID login flow.
FASTLANE_USER=
FASTLANE_ITC_TEAM_ID=
FASTLANE_ITC_TEAM_NAME=
CONFIRM_UPLOAD_APP_PRIVACY=
APP_PRIVACY_SKIP_PUBLISH=

# Set after Fastlane upload or manual App Store Connect entry matches AppStore/app_privacy_details.json.
APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=

# Optional overrides.
IPA_PATH=
TESTFLIGHT_CHANGELOG=

# Final App Review submission guard. Set only when the uploaded build is processed
# and every App Store Connect field has been reviewed.
APP_STORE_BUILD_NUMBER=
CONFIRM_SUBMIT_FOR_REVIEW=
EOF
}

backup_existing_private_file() {
  local target_path="$1"
  local label="$2"
  local backup_path

  if [[ ! -e "$target_path" ]]; then
    return
  fi

  umask 077
  backup_path="$(mktemp "${target_path}.bak.XXXXXX")"
  cp "$target_path" "$backup_path"
  chmod 600 "$backup_path"
  printf 'Backed up existing private %s: %s\n' "$label" "$backup_path"
}

sync_missing_template_assignments() {
  local target_path="$1"
  local label="$2"
  local template_path
  local missing_path
  local missing_count

  template_path="$(mktemp)"
  missing_path="$(mktemp)"
  write_template >"$template_path"

  awk '
    FNR == NR {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
        key = line
        sub(/=.*/, "", key)
        existing[key] = 1
      }
      next
    }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
        key = line
        sub(/=.*/, "", key)
        if (!(key in existing)) {
          print $0
        }
      }
    }
  ' "$target_path" "$template_path" >"$missing_path"

  missing_count="$(wc -l <"$missing_path" | tr -d '[:space:]')"
  if [[ "$missing_count" -gt 0 ]]; then
    backup_existing_private_file "$target_path" "$label"
    {
      printf '\n# Added by Scripts/bootstrap_release_env.sh to sync newer release inputs.\n'
      while IFS= read -r line; do
        printf '%s\n' "$line"
      done <"$missing_path"
    } >>"$target_path"
    chmod 600 "$target_path"
    printf 'Updated private %s with %s missing template key(s): %s\n' "$label" "$missing_count" "$target_path"
  else
    printf '%s already exists and is up to date: %s\n' "$label" "$target_path"
  fi

  rm -f "$template_path" "$missing_path"
}

if [[ "$print_only" == "1" ]]; then
  write_template
  exit 0
fi

if [[ "$release_env_path" != "$ROOT_DIR/"* ]]; then
  printf 'Refusing to bootstrap outside this repository: %s\n' "$release_env_path" >&2
  printf 'Unset RELEASE_ENV_PATH to create Config/release.env.\n' >&2
  exit 1
fi

relative_env_path="${release_env_path#"$ROOT_DIR/"}"
if ! git check-ignore -q "$relative_env_path"; then
  printf 'Refusing to create %s because it is not ignored by git.\n' "$relative_env_path" >&2
  printf 'Add it to .gitignore before writing private release values.\n' >&2
  exit 1
fi

if [[ -e "$release_env_path" && "$force" != "1" ]]; then
  printf 'Release environment already exists: %s\n' "$release_env_path"
  sync_missing_template_assignments "$release_env_path" "release environment"
  printf 'Use --force only to replace the full private file after backing up values.\n'
  exit 0
fi

mkdir -p "$(dirname "$release_env_path")"
if [[ -e "$release_env_path" && "$force" == "1" ]]; then
  backup_existing_private_file "$release_env_path" "release environment"
fi
umask 077
write_template >"$release_env_path"
chmod 600 "$release_env_path"

printf 'Created private release environment: %s\n' "$release_env_path"
printf 'Next: fill real Apple signing, App Review contact, and App Store Connect values, then run:\n'
printf '  Scripts/validate_release_env.sh\n'
printf '  Scripts/check_app_store_readiness.sh\n'
