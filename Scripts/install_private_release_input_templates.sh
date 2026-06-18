#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source_dir="${FREEPRINTSTUDIO_PRIVATE_INPUT_TEMPLATE_DIR:-$ROOT_DIR/build/private-release-input-templates}"
target_dir="${FREEPRINTSTUDIO_PRIVATE_INPUT_TARGET_DIR:-$ROOT_DIR/Config}"
force=0

usage() {
  cat <<'EOF'
Usage: Scripts/install_private_release_input_templates.sh [--source-dir DIR] [--target-dir DIR] [--force]

Installs generated blank private release input templates into git-ignored files:
  - Config/release.env
  - Config/manual-release-verification.env

Defaults:
  --source-dir build/private-release-input-templates
  --target-dir Config

Options:
  --source-dir DIR  generated private-release-input-templates directory
  --target-dir DIR  target directory for private input files
  --force           replace existing private files after backing them up
EOF
}

absolute_path() {
  local path="$1"
  case "$path" in
    /*)
      printf '%s' "$path"
      ;;
    *)
      printf '%s/%s' "$ROOT_DIR" "$path"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --source-dir\n\n' >&2
        usage >&2
        exit 1
      fi
      source_dir="$(absolute_path "$2")"
      shift
      ;;
    --target-dir)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --target-dir\n\n' >&2
        usage >&2
        exit 1
      fi
      target_dir="$(absolute_path "$2")"
      shift
      ;;
    --force)
      force=1
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

release_template="$source_dir/release.env"
manual_template="$source_dir/manual-release-verification.env"
release_target="$target_dir/release.env"
manual_target="$target_dir/manual-release-verification.env"

require_template() {
  local path="$1"
  local label="$2"
  if [[ ! -s "$path" ]]; then
    printf 'FAIL: generated %s template is missing or empty: %s\n' "$label" "$path" >&2
    exit 1
  fi
}

ensure_repo_private_path() {
  local path="$1"
  local label="$2"
  local relative_path

  if [[ "$path" != "$ROOT_DIR/"* ]]; then
    printf 'Refusing to install %s outside this repository: %s\n' "$label" "$path" >&2
    exit 1
  fi

  relative_path="${path#"$ROOT_DIR/"}"
  if ! git check-ignore -q "$relative_path"; then
    printf 'Refusing to install %s because it is not ignored by git: %s\n' "$label" "$relative_path" >&2
    exit 1
  fi
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
  local source_path="$1"
  local target_path="$2"
  local label="$3"
  local missing_path
  local missing_count

  missing_path="$(mktemp)"
  awk '
    function assignment_key(raw_line,   line, key) {
      line = raw_line
      sub(/^[[:space:]]+/, "", line)
      sub(/^export[[:space:]]+/, "", line)
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
        key = line
        sub(/=.*/, "", key)
        return key
      }
      return ""
    }

    FNR == NR {
      key = assignment_key($0)
      if (key != "") {
        existing[key] = 1
      }
      next
    }
    {
      key = assignment_key($0)
      if (key != "") {
        if (!(key in existing)) {
          print $0
        }
      }
    }
  ' "$target_path" "$source_path" >"$missing_path"

  missing_count="$(wc -l <"$missing_path" | tr -d '[:space:]')"
  if [[ "$missing_count" -gt 0 ]]; then
    backup_existing_private_file "$target_path" "$label"
    {
      printf '\n# Added by Scripts/install_private_release_input_templates.sh from generated private-release-input-templates.\n'
      while IFS= read -r line; do
        printf '%s\n' "$line"
      done <"$missing_path"
    } >>"$target_path"
    chmod 600 "$target_path"
    printf 'Updated private %s with %s missing template key(s): %s\n' "$label" "$missing_count" "$target_path"
  else
    chmod 600 "$target_path"
    printf '%s already exists and has all generated template keys: %s\n' "$label" "$target_path"
  fi

  rm -f "$missing_path"
}

install_template() {
  local source_path="$1"
  local target_path="$2"
  local label="$3"

  if [[ -e "$target_path" && "$force" != "1" ]]; then
    sync_missing_template_assignments "$source_path" "$target_path" "$label"
    printf 'Use --force only to replace the full private file after backing up values.\n'
    return
  fi

  mkdir -p "$(dirname "$target_path")"
  if [[ -e "$target_path" && "$force" == "1" ]]; then
    backup_existing_private_file "$target_path" "$label"
  fi

  umask 077
  cp "$source_path" "$target_path"
  chmod 600 "$target_path"
  printf 'Installed private %s from generated template: %s\n' "$label" "$target_path"
}

require_template "$release_template" "release.env"
require_template "$manual_template" "manual-release-verification.env"

ensure_repo_private_path "$release_target" "release environment"
ensure_repo_private_path "$manual_target" "manual release verification evidence"

install_template "$release_template" "$release_target" "release environment"
install_template "$manual_template" "$manual_target" "manual release verification evidence"

printf '\nNext release input commands:\n'
printf '  1. Fill real Apple signing, App Review contact, and App Store Connect values in %s\n' "$release_target"
printf '  2. Record real iPhone, AirPrint, iPad, and TestFlight evidence in %s after testing\n' "$manual_target"
printf '  3. Run Scripts/print_release_input_status.sh --strict\n'
printf '  4. Run Scripts/validate_release_env.sh\n'
printf '  5. Run APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh\n'
printf '     Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands.\n'
