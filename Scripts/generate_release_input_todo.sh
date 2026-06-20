#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <external-readiness-actions.tsv> <release-input-todo.md>\n' "$0" >&2
  exit 2
fi

actions_path="$1"
output_path="$2"

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions file is missing or empty: %s\n' "$actions_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"

private_template_install_command="Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config"
private_template_status_command="Scripts/print_release_input_status.sh --strict"

awk -F '\t' -v output_path="$output_path" -v actions_path="$actions_path" -v generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" -v private_template_install_command="$private_template_install_command" -v private_template_status_command="$private_template_status_command" '
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

  function owner_status_command(owner_name) {
    return "Scripts/print_release_input_status.sh --strict --owner " owner_slug(owner_name)
  }

  function target_heading(target) {
    return "## " target
  }

  function is_env_target(target) {
    return target ~ /^Config\/release\.env/ || target == "Config/manual-release-verification.env"
  }

  function is_release_env_row(row) {
    return target_of[row] ~ /^Config\/release\.env/
  }

  function is_manual_evidence_row(row) {
    return target_of[row] == "Config/manual-release-verification.env"
  }

  function row_matches_env_group(row, target) {
    if (target == "Config/release.env") {
      return is_release_env_row(row)
    }
    if (target == "Config/manual-release-verification.env") {
      return is_manual_evidence_row(row)
    }
    return 0
  }

  function is_manual_evidence_file_setup_row(row) {
    return target_of[row] == "Config/manual-release-verification.env" && \
      (field[row] == "manual-release-verification.env file" || \
       field[row] == "MANUAL_RELEASE_VERIFICATION_PATH" || \
       item[row] ~ /Manual release verification evidence file/)
  }

  function display_field(row) {
    if (is_manual_evidence_file_setup_row(row)) {
      return "manual-release-verification.env file"
    }
    return field[row]
  }

  function print_table_header() {
    print "| Severity | Owner | Field | Item | Next Action | Validation Command |" >>output_path
    print "| --- | --- | --- | --- | --- | --- |" >>output_path
  }

  function print_table_row(row) {
    printf "| %s | %s | %s | %s | %s | %s |\n", \
      markdown_cell(severity[row]), \
      markdown_cell(owner[row]), \
      code_text(markdown_cell(display_field(row))), \
      markdown_cell(item[row]), \
      markdown_cell(next_action[row]), \
      code_text(markdown_cell(validation_command[row])) >>output_path
  }

  function print_final_submission_guards() {
    print "" >>output_path
    print "## Final Submission Guards" >>output_path
    print "" >>output_path
    print "Set these only after the uploaded build has processed, App Store Connect metadata is final, and manual evidence was recorded for the same build." >>output_path
    print "" >>output_path
    print "```sh" >>output_path
    print "APP_STORE_BUILD_NUMBER=" >>output_path
    print "CONFIRM_SUBMIT_FOR_REVIEW=" >>output_path
    print "```" >>output_path
    print "" >>output_path
    print "| Guard | Purpose | Validation Command |" >>output_path
    print "| --- | --- | --- |" >>output_path
    print "| `APP_STORE_BUILD_NUMBER` | Processed App Store Connect build selected for App Review. | `APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh` |" >>output_path
    print "| `CONFIRM_SUBMIT_FOR_REVIEW=1` | Explicit final confirmation before Fastlane submits the selected build for review. | `APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review` |" >>output_path
  }

  function print_placeholder_replacement_notes() {
    print "" >>output_path
    print "## Placeholder Replacement Notes" >>output_path
    print "" >>output_path
    print "Replace PROCESSED_BUILD_NUMBER with the processed App Store Connect build number before running selected-build commands." >>output_path
    if (has_team_id_placeholder) {
      print "Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands." >>output_path
    }
    if (has_fastlane_apple_id_placeholder) {
      print "Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands." >>output_path
    }
  }

  function print_owner_status_commands(   owner_index, owner_name) {
    print "" >>output_path
    print "## Owner-Scoped Status Commands" >>output_path
    print "" >>output_path
    print "Use these redacted commands when one handoff owner needs to check only their assigned release inputs." >>output_path
    print "" >>output_path
    print "| Owner | Command |" >>output_path
    print "| --- | --- |" >>output_path
    for (owner_index = 1; owner_index <= owner_order_count; owner_index += 1) {
      owner_name = owner_order[owner_index]
      printf "| %s | %s |\n", \
        code_text(markdown_cell(owner_name)), \
        code_text(markdown_cell(owner_status_command(owner_name))) >>output_path
    }
  }

  function print_env_assignments(target,   row, printed, fields_seen, parts, part_count, part_index, candidate, has_missing_manual_file_action) {
    print "Fill these values in the git-ignored " code_text(target) " file. Leave secrets out of git." >>output_path
    if (target == "Config/release.env") {
      print "If the file does not exist yet, install or sync it from the current private templates with " code_text(private_template_install_command) " before filling release values." >>output_path
      print "After installing or syncing templates, run " code_text(private_template_status_command) " before filling release values." >>output_path
    }
    if (target == "Config/manual-release-verification.env") {
      for (row = 1; row <= row_count; row += 1) {
        if (row_matches_env_group(row, target) && is_manual_evidence_file_setup_row(row)) {
          has_missing_manual_file_action = 1
        }
      }
      if (has_missing_manual_file_action) {
        print "If the file does not exist yet, install or sync it from the current private templates with " code_text(private_template_install_command) " before recording evidence." >>output_path
        print "After installing or syncing templates, run " code_text(private_template_status_command) " before recording evidence." >>output_path
      }
    }
    print "" >>output_path
    print "```sh" >>output_path
    for (row = 1; row <= row_count; row += 1) {
      if (!row_matches_env_group(row, target)) {
        continue
      }
      if (target == "Config/manual-release-verification.env" && is_manual_evidence_file_setup_row(row)) {
        continue
      }
      if (field[row] ~ /^[A-Z0-9_]+$/) {
        if (!(field[row] in fields_seen)) {
          print field[row] "=" >>output_path
          fields_seen[field[row]] = 1
          printed = 1
        }
        continue
      }
      if (field[row] ~ / or / || field[row] ~ /\//) {
        print "# Choose the App Store Connect credential option represented by:" >>output_path
        print "# " field[row] >>output_path
        part_count = split(field[row], parts, / or |\/+/)
        for (part_index = 1; part_index <= part_count; part_index += 1) {
          candidate = parts[part_index]
          gsub(/^ +| +$/, "", candidate)
          if (candidate ~ /^[A-Z0-9_]+$/ && !(candidate in fields_seen)) {
            print candidate "=" >>output_path
            fields_seen[candidate] = 1
            printed = 1
          }
        }
      } else {
        print "# " field[row] >>output_path
      }
    }
    if (!printed) {
      print "# No direct env assignments were found for this target." >>output_path
    }
    print "```" >>output_path
    print "" >>output_path
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
    row_count += 1
    category[row_count] = $(columns["category"])
    severity[row_count] = $(columns["severity"])
    owner[row_count] = $(columns["owner"])
    field[row_count] = $(columns["field"])
    target_of[row_count] = $(columns["target"])
    item[row_count] = $(columns["item"])
    next_action[row_count] = $(columns["next_action"])
    validation_command[row_count] = $(columns["validation_command"])
    placeholder_source = next_action[row_count] " " validation_command[row_count]
    if (placeholder_source ~ /YOURTEAMID/) {
      has_team_id_placeholder = 1
    }
    if (placeholder_source ~ /apple-id@example[.]com/) {
      has_fastlane_apple_id_placeholder = 1
    }
    target_counts[target_of[row_count]] += 1
    if (!(target_of[row_count] in target_seen)) {
      target_seen[target_of[row_count]] = 1
      target_order_count += 1
      target_order[target_order_count] = target_of[row_count]
    }
    owner_counts[owner[row_count]] += 1
    if (!(owner[row_count] in owner_seen)) {
      owner_seen[owner[row_count]] = 1
      owner_order_count += 1
      owner_order[owner_order_count] = owner[row_count]
    }
    if (severity[row_count] == "blocker") {
      blocker_count += 1
      owner_blocker_counts[owner[row_count]] += 1
    } else if (severity[row_count] == "warning") {
      warning_count += 1
      owner_warning_counts[owner[row_count]] += 1
    }
  }

  END {
    if (row_count == 0) {
      fail("external readiness actions file has no action rows")
    }

    final_submission_guard_actions = 2
    final_submission_guard_blockers = 2
    total_handoff_actions = row_count + final_submission_guard_actions
    total_handoff_blockers = blocker_count + final_submission_guard_blockers
    total_handoff_warnings = warning_count + 0

    final_guard_target = "Config/release.env"
    if (!(final_guard_target in target_seen)) {
      target_seen[final_guard_target] = 1
      target_order_count += 1
      target_order[target_order_count] = final_guard_target
    }
    target_counts[final_guard_target] += final_submission_guard_actions

    final_guard_owner = "Release owner"
    if (!(final_guard_owner in owner_seen)) {
      owner_seen[final_guard_owner] = 1
      owner_order_count += 1
      owner_order[owner_order_count] = final_guard_owner
    }
    owner_counts[final_guard_owner] += final_submission_guard_actions
    owner_blocker_counts[final_guard_owner] += final_submission_guard_blockers

    print "# FreePrint Studio Release Input TODO" >output_path
    print "" >>output_path
    print "- Generated At: `" generated_at "`" >>output_path
    print "- Source: `" actions_path "`" >>output_path
    print "- External Actions: `" row_count "`" >>output_path
    print "- Final Submission Guard Actions: `" final_submission_guard_actions "`" >>output_path
    print "- Total Handoff Actions: `" total_handoff_actions "`" >>output_path
    print "- Blockers: `" blocker_count + 0 "`" >>output_path
    print "- Total Handoff Blockers: `" total_handoff_blockers "`" >>output_path
    print "- Warnings: `" warning_count + 0 "`" >>output_path
    print "- Total Handoff Warnings: `" total_handoff_warnings "`" >>output_path
    print "" >>output_path
    print "## Target Summary" >>output_path
    print "" >>output_path
    print "| Target | Actions |" >>output_path
    print "| --- | ---: |" >>output_path
    for (target_index = 1; target_index <= target_order_count; target_index += 1) {
      target = target_order[target_index]
      printf "| %s | %s |\n", code_text(markdown_cell(target)), target_counts[target] >>output_path
    }

    print "" >>output_path
    print "## Owner Summary" >>output_path
    print "" >>output_path
    print "| Owner | Actions | Blockers | Warnings |" >>output_path
    print "| --- | ---: | ---: | ---: |" >>output_path
    for (owner_index = 1; owner_index <= owner_order_count; owner_index += 1) {
      owner_name = owner_order[owner_index]
      printf "| %s | %s | %s | %s |\n", \
        code_text(markdown_cell(owner_name)), \
        owner_counts[owner_name], \
        owner_blocker_counts[owner_name] + 0, \
        owner_warning_counts[owner_name] + 0 >>output_path
    }

    print_owner_status_commands()

    print_placeholder_replacement_notes()

    env_targets[1] = "Config/release.env"
    env_targets[2] = "Config/manual-release-verification.env"
    for (env_index = 1; env_index <= 2; env_index += 1) {
      target = env_targets[env_index]
      target_has_rows = 0
      for (row = 1; row <= row_count; row += 1) {
        if (row_matches_env_group(row, target)) {
          target_has_rows = 1
        }
      }
      if (!target_has_rows) {
        continue
      }
      print "" >>output_path
      print target_heading(target) >>output_path
      print "" >>output_path
      print_env_assignments(target)
      print_table_header()
      for (row = 1; row <= row_count; row += 1) {
        if (row_matches_env_group(row, target)) {
          print_table_row(row)
        }
      }
    }

    print_final_submission_guards()

    print "" >>output_path
    print "## Non-env External Actions" >>output_path
    print "" >>output_path
    print "These cannot be completed by editing env files. Finish them in Keychain, Xcode, App Store Connect, TestFlight, or the named external system, then run the listed validation command." >>output_path
    print "" >>output_path
    print_table_header()
    for (row = 1; row <= row_count; row += 1) {
      if (!is_env_target(target_of[row])) {
        print_table_row(row)
        non_env_count += 1
      }
    }
    if (non_env_count == 0) {
      print "| info | Release owner | `none` | No non-env external actions were found. | Continue with env validation. | `Scripts/check_app_store_readiness.sh` |" >>output_path
    }
  }
' "$actions_path"

printf 'Release input TODO written: %s\n' "$output_path"
