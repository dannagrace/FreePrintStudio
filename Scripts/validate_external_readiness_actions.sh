#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <readiness.txt> <external-readiness-actions.tsv>\n' "$0" >&2
  exit 2
fi

readiness_path="$1"
actions_path="$2"

if [[ ! -s "$readiness_path" ]]; then
  printf 'FAIL: readiness summary input is missing or empty: %s\n' "$readiness_path"
  exit 1
fi

if [[ ! -s "$actions_path" ]]; then
  printf 'FAIL: external readiness actions input is missing or empty: %s\n' "$actions_path"
  exit 1
fi

summary_line="$(grep -E '^Summary: [0-9]+ blocker\(s\), [0-9]+ warning\(s\)\.$' "$readiness_path" | tail -n 1 || true)"
if [[ -z "$summary_line" ]]; then
  printf 'FAIL: readiness summary is missing or has an unexpected format in %s\n' "$readiness_path"
  exit 1
fi

expected_blockers="$(printf '%s\n' "$summary_line" | sed -E 's/^Summary: ([0-9]+) blocker\(s\), ([0-9]+) warning\(s\)\.$/\1/')"
expected_warnings="$(printf '%s\n' "$summary_line" | sed -E 's/^Summary: ([0-9]+) blocker\(s\), ([0-9]+) warning\(s\)\.$/\2/')"

actual_blockers="$(awk -F '\t' 'NR > 1 && $2 == "blocker" { count += 1 } END { print count + 0 }' "$actions_path")"
actual_warnings="$(awk -F '\t' 'NR > 1 && $2 == "warning" { count += 1 } END { print count + 0 }' "$actions_path")"

failures=0

if [[ "$actual_blockers" != "$expected_blockers" ]]; then
  printf 'FAIL: External readiness action count mismatch for blocker (readiness Summary: %s; external-readiness-actions.tsv: %s)\n' \
    "$expected_blockers" "$actual_blockers"
  failures=$((failures + 1))
fi

if [[ "$actual_warnings" != "$expected_warnings" ]]; then
  printf 'FAIL: External readiness action count mismatch for warning (readiness Summary: %s; external-readiness-actions.tsv: %s)\n' \
    "$expected_warnings" "$actual_warnings"
  failures=$((failures + 1))
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
expected_pairs="$temp_dir/expected.tsv"
actual_pairs="$temp_dir/actual.tsv"

awk '
  /^BLOCKED: / {
    item = $0
    sub(/^BLOCKED: /, "", item)
    print "blocker\t" item
  }
  /^WARN: / {
    item = $0
    sub(/^WARN: /, "", item)
    print "warning\t" item
  }
' "$readiness_path" | LC_ALL=C sort -u >"$expected_pairs"

awk -F '\t' '
  NR > 1 && ($2 == "blocker" || $2 == "warning") {
    print $2 "\t" $6
  }
' "$actions_path" | LC_ALL=C sort -u >"$actual_pairs"

while IFS=$'\t' read -r severity item; do
  [[ -z "${severity:-}" ]] && continue
  printf 'FAIL: Missing external readiness action for %s: %s\n' "$severity" "$item"
  failures=$((failures + 1))
done < <(comm -23 "$expected_pairs" "$actual_pairs")

while IFS=$'\t' read -r severity item; do
  [[ -z "${severity:-}" ]] && continue
  printf 'FAIL: Unexpected external readiness action for %s: %s\n' "$severity" "$item"
  failures=$((failures + 1))
done < <(comm -13 "$expected_pairs" "$actual_pairs")

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

printf 'External readiness actions match readiness summary.\n'
