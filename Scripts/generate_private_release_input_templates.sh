#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <private-release-input-templates-dir>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
output_dir="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions file is missing or empty: %s\n' "$actions_path" >&2
  exit 1
fi

mkdir -p "$output_dir"
rm -f \
  "$output_dir/index.md" \
  "$output_dir/release.env" \
  "$output_dir/manual-release-verification.env"

# Emits MANUAL_AIRPRINT_RULER_TARGET_INCHES="6" when measured ruler evidence is required.
awk -F '\t' -v output_dir="$output_dir" -v actions_path="$actions_path" -v generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
  function fail(message) {
    print "FAIL: " message >"/dev/stderr"
    exit 1
  }

  function add_release_env(name) {
    if (name ~ /^[A-Z0-9_]+$/ && !(name in release_seen)) {
      release_seen[name] = 1
      release_count += 1
      release_names[release_count] = name
    }
  }

  function add_manual_env(name) {
    if (name == "MANUAL_AIRPRINT_RULER_MEASURED_INCHES" && !("MANUAL_AIRPRINT_RULER_TARGET_INCHES" in manual_seen)) {
      manual_seen["MANUAL_AIRPRINT_RULER_TARGET_INCHES"] = 1
      manual_count += 1
      manual_names[manual_count] = "MANUAL_AIRPRINT_RULER_TARGET_INCHES"
    }
    if (name ~ /^[A-Z0-9_]+$/ && !(name in manual_seen)) {
      manual_seen[name] = 1
      manual_count += 1
      manual_names[manual_count] = name
    }
  }

  function add_field_assignments(field_name, target,   parts, part_count, part_index, candidate) {
    if (field_name ~ /^[A-Z0-9_]+$/) {
      if (target ~ /^Config\/release\.env/) {
        add_release_env(field_name)
      } else if (target == "Config/manual-release-verification.env") {
        add_manual_env(field_name)
      }
      return
    }

    if (field_name ~ / or / || field_name ~ /\//) {
      part_count = split(field_name, parts, / or |\/+/)
      for (part_index = 1; part_index <= part_count; part_index += 1) {
        candidate = parts[part_index]
        gsub(/^ +| +$/, "", candidate)
        if (target ~ /^Config\/release\.env/) {
          add_release_env(candidate)
        } else if (target == "Config/manual-release-verification.env") {
          add_manual_env(candidate)
        }
      }
    }
  }

  function is_manual_file_setup(field_name, target, item) {
    return target == "Config/manual-release-verification.env" && \
      (field_name == "manual-release-verification.env file" || \
       field_name == "MANUAL_RELEASE_VERIFICATION_PATH" || \
       item ~ /Manual release verification evidence file/)
  }

  function write_env_file(path, label, count, names,   idx, name) {
    print "# FreePrint Studio " label "." >path
    print "# Generated At: " generated_at >>path
    print "# Source: " actions_path >>path
    print "# Copy this file to Config/" label " and fill real private values locally." >>path
    print "# Keep filled values out of git." >>path
    print "" >>path

    if (count == 0) {
      print "# No current external readiness action maps to this private input file." >>path
      return
    }

    for (idx = 1; idx <= count; idx += 1) {
      name = names[idx]
      if (name == "MANUAL_AIRPRINT_RULER_TARGET_INCHES") {
        print "MANUAL_AIRPRINT_RULER_TARGET_INCHES=\"6\"" >>path
      } else {
        printf "%s=\"\"\n", name >>path
      }
    }
  }

  NR == 1 {
    for (i = 1; i <= NF; i += 1) {
      columns[$i] = i
    }
    required[1] = "field"
    required[2] = "target"
    required[3] = "item"
    for (i = 1; i <= 3; i += 1) {
      if (!(required[i] in columns)) {
        fail("external readiness actions file is missing required column: " required[i])
      }
    }
    next
  }

  $1 != "" {
    row_count += 1
    field_name = $(columns["field"])
    target = $(columns["target"])
    item = $(columns["item"])
    if (is_manual_file_setup(field_name, target, item)) {
      next
    }
    add_field_assignments(field_name, target)
  }

  END {
    if (row_count == 0) {
      fail("external readiness actions file has no action rows")
    }

    index_path = output_dir "/index.md"
    release_path = output_dir "/release.env"
    manual_path = output_dir "/manual-release-verification.env"

    write_env_file(release_path, "release.env", release_count, release_names)
    write_env_file(manual_path, "manual-release-verification.env", manual_count, manual_names)

    print "# FreePrint Studio Private Release Input Templates" >index_path
    print "" >>index_path
    print "- Generated At: `" generated_at "`" >>index_path
    print "- Source: `" actions_path "`" >>index_path
    print "- Output: `private-release-input-templates/`" >>index_path
    print "" >>index_path
    print "These files are blank private-input starters generated from the current external readiness actions. Copy them into `Config/`, fill real values locally, and keep the filled files out of git." >>index_path
    print "" >>index_path
    print "## Templates" >>index_path
    print "" >>index_path
    print "| Template | File | Assignments |" >>index_path
    print "| --- | --- | ---: |" >>index_path
    printf "| `release.env` | [release.env](release.env) | %d |\n", release_count >>index_path
    printf "| `manual-release-verification.env` | [manual-release-verification.env](manual-release-verification.env) | %d |\n", manual_count >>index_path
    print "" >>index_path
    print "## Usage" >>index_path
    print "" >>index_path
    print "```sh" >>index_path
    print "cp private-release-input-templates/release.env Config/release.env" >>index_path
    print "cp private-release-input-templates/manual-release-verification.env Config/manual-release-verification.env" >>index_path
    print "chmod 600 Config/release.env Config/manual-release-verification.env" >>index_path
    print "Scripts/print_release_input_status.sh --strict" >>index_path
    print "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh" >>index_path
    print "```" >>index_path
  }
' "$actions_path"

printf 'Private release input templates written: %s\n' "$output_dir"
