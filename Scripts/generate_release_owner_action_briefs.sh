#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <owner-action-briefs-dir>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
output_dir="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions file is missing or empty: %s\n' "$actions_path" >&2
  exit 1
fi

mkdir -p "$output_dir"
find "$output_dir" -maxdepth 1 -type f -name '*.md' -delete

awk -F '\t' -v output_dir="$output_dir" -v actions_path="$actions_path" -v generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
  function fail(message) {
    print "FAIL: " message >"/dev/stderr"
    exit 1
  }

  function markdown_cell(value) {
    gsub(/\|/, "\\|", value)
    gsub(/`/, "\\`", value)
    return value
  }

  function code_text(value) {
    gsub(/`/, "\\`", value)
    return "`" value "`"
  }

  function owner_slug(value, slug) {
    slug = tolower(value)
    gsub(/[^a-z0-9]+/, "-", slug)
    gsub(/^-+|-+$/, "", slug)
    if (slug == "") {
      slug = "owner"
    }
    return slug
  }

  function owner_file(owner_name) {
    return owner_slug(owner_name) ".md"
  }

  function owner_status_command(owner_name) {
    return "Scripts/print_release_input_status.sh --strict --owner " owner_slug(owner_name)
  }

  function print_detail_header(path) {
    print "| Category | Severity | Field | Target | Item | Next Action | Validation Command |" >>path
    print "| --- | --- | --- | --- | --- | --- | --- |" >>path
  }

  function print_detail_row(row, path) {
    printf "| %s | %s | %s | %s | %s | %s | %s |\n", \
      markdown_cell(category[row]), \
      markdown_cell(severity[row]), \
      code_text(markdown_cell(field[row])), \
      code_text(markdown_cell(target[row])), \
      markdown_cell(item[row]), \
      markdown_cell(next_action[row]), \
      code_text(markdown_cell(validation_command[row])) >>path
  }

  function add_action(action_category, action_severity, action_owner, action_field, action_target, action_item, action_next_action, action_validation_command, placeholder_source) {
    row_count += 1
    category[row_count] = action_category
    severity[row_count] = action_severity
    owner[row_count] = action_owner
    field[row_count] = action_field
    target[row_count] = action_target
    item[row_count] = action_item
    next_action[row_count] = action_next_action
    validation_command[row_count] = action_validation_command

    owner_counts[action_owner] += 1
    placeholder_source = action_next_action " " action_validation_command
    if (placeholder_source ~ /PROCESSED_BUILD_NUMBER/) {
      owner_selected_build_placeholder[action_owner] = 1
    }
    if (placeholder_source ~ /YOURTEAMID/) {
      owner_team_id_placeholder[action_owner] = 1
    }
    if (placeholder_source ~ /apple-id@example\.com/) {
      owner_fastlane_apple_id_placeholder[action_owner] = 1
    }
    if (action_target ~ /(^| )Config\//) {
      owner_private_input_setup[action_owner] = 1
    }
    if (!(action_owner in owner_seen)) {
      owner_seen[action_owner] = 1
      owner_order_count += 1
      owner_order[owner_order_count] = action_owner
    }
    if (action_severity == "blocker") {
      owner_blocker_counts[action_owner] += 1
    } else if (action_severity == "warning") {
      owner_warning_counts[action_owner] += 1
    }
  }

  NR == 1 {
    for (i = 1; i <= NF; i += 1) {
      columns[$i] = i
    }
    required[1] = "category"
    required[2] = "severity"
    required[3] = "owner"
    required[4] = "field"
    required[5] = "target"
    required[6] = "item"
    required[7] = "next_action"
    required[8] = "validation_command"
    for (i = 1; i <= 8; i += 1) {
      if (!(required[i] in columns)) {
        fail("external readiness actions file is missing required column: " required[i])
      }
    }
    next
  }

  $1 != "" {
    external_row_count += 1
    add_action( \
      $(columns["category"]), \
      $(columns["severity"]), \
      $(columns["owner"]), \
      $(columns["field"]), \
      $(columns["target"]), \
      $(columns["item"]), \
      $(columns["next_action"]), \
      $(columns["validation_command"]))
  }

  END {
    if (external_row_count == 0) {
      fail("external readiness actions file has no action rows")
    }

    add_action( \
      "Final Submission Guard", \
      "blocker", \
      "Release owner", \
      "APP_STORE_BUILD_NUMBER", \
      "Config/release.env", \
      "Processed App Store Connect build selected for App Review.", \
      "Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands.", \
      "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh")
    add_action( \
      "Final Submission Guard", \
      "blocker", \
      "Release owner", \
      "CONFIRM_SUBMIT_FOR_REVIEW", \
      "Config/release.env", \
      "Explicit final confirmation before Fastlane submits the selected build for review.", \
      "Set CONFIRM_SUBMIT_FOR_REVIEW=1 only for the final deliberate App Review submission.", \
      "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review")

    index_path = output_dir "/index.md"
    print "# FreePrint Studio Release Owner Action Briefs" >index_path
    print "" >>index_path
    print "- Generated At: `" generated_at "`" >>index_path
    print "- Source: `" actions_path "`" >>index_path
    print "" >>index_path
    print "## Owner Summary" >>index_path
    print "" >>index_path
    print "| Owner | File | Actions | Blockers | Warnings |" >>index_path
    print "| --- | --- | ---: | ---: | ---: |" >>index_path

    for (owner_index = 1; owner_index <= owner_order_count; owner_index += 1) {
      owner_name = owner_order[owner_index]
      file_name = owner_file(owner_name)
      printf "| %s | [%s](%s) | %s | %s | %s |\n", \
        markdown_cell(owner_name), \
        file_name, \
        file_name, \
        owner_counts[owner_name], \
        owner_blocker_counts[owner_name] + 0, \
        owner_warning_counts[owner_name] + 0 >>index_path

      owner_path = output_dir "/" file_name
      print "# " owner_name " Release Actions" >owner_path
      print "" >>owner_path
      print "- Generated At: `" generated_at "`" >>owner_path
      print "- Source: `" actions_path "`" >>owner_path
      print "- Actions: `" owner_counts[owner_name] "`" >>owner_path
      print "- Blockers: `" owner_blocker_counts[owner_name] + 0 "`" >>owner_path
      print "- Warnings: `" owner_warning_counts[owner_name] + 0 "`" >>owner_path
      print "" >>owner_path
      print "## Action Summary" >>owner_path
      print "" >>owner_path
      print "| Category | Severity | Count |" >>owner_path
      print "| --- | --- | ---: |" >>owner_path

      delete summary_counts
      delete summary_order
      summary_order_count = 0
      for (row = 1; row <= row_count; row += 1) {
        if (owner[row] != owner_name) {
          continue
        }
        summary_key = category[row] SUBSEP severity[row]
        summary_counts[summary_key] += 1
        if (!(summary_key in summary_seen)) {
          summary_seen[summary_key] = 1
          summary_order_count += 1
          summary_order[summary_order_count] = summary_key
        }
      }
      for (summary_index = 1; summary_index <= summary_order_count; summary_index += 1) {
        split(summary_order[summary_index], summary_parts, SUBSEP)
        printf "| %s | %s | %s |\n", \
          markdown_cell(summary_parts[1]), \
          markdown_cell(summary_parts[2]), \
          summary_counts[summary_order[summary_index]] >>owner_path
      }
      delete summary_seen

      print "" >>owner_path
      if (owner_private_input_setup[owner_name]) {
        print "## Private Input Setup" >>owner_path
        print "" >>owner_path
        print "Run these before editing any `Config/` target listed in this brief. The installer backs up existing private files, appends missing generated keys, and keeps filled values out of git." >>owner_path
        print "" >>owner_path
        print "```sh" >>owner_path
        print "Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config" >>owner_path
        print owner_status_command(owner_name) >>owner_path
        print "```" >>owner_path
        print "" >>owner_path
      }

      print "" >>owner_path
      print "## Action Detail" >>owner_path
      print "" >>owner_path
      print_detail_header(owner_path)
      for (row = 1; row <= row_count; row += 1) {
        if (owner[row] == owner_name) {
          print_detail_row(row, owner_path)
        }
      }

      print "" >>owner_path
      print "## Validation Commands" >>owner_path
      print "" >>owner_path
      print "```sh" >>owner_path
      delete command_seen
      for (row = 1; row <= row_count; row += 1) {
        if (owner[row] != owner_name) {
          continue
        }
        command = validation_command[row]
        if (!(command in command_seen)) {
          print command >>owner_path
          command_seen[command] = 1
        }
      }
      print "```" >>owner_path
      if (owner_selected_build_placeholder[owner_name]) {
        print "" >>owner_path
        print "Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands." >>owner_path
      }
      if (owner_team_id_placeholder[owner_name]) {
        print "" >>owner_path
        print "Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands." >>owner_path
      }
      if (owner_fastlane_apple_id_placeholder[owner_name]) {
        print "" >>owner_path
        print "Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands." >>owner_path
      }
    }
  }
' "$actions_path"

printf 'Release owner action briefs written: %s\n' "$output_dir"
