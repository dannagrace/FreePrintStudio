#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_path="${1:-build/manual-release-evidence-form.md}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

usage() {
  cat <<'EOF'
Usage: Scripts/generate_manual_release_evidence_form.sh [output-path]

Generates a blank manual App Store release evidence form. The form is safe to
commit or package because it contains no private contact details, account
credentials, device identifiers, or signed build artifacts.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

mkdir -p "$(dirname "$output_path")"

cat >"$output_path" <<EOF
# FreePrint Studio Manual Release Evidence Form

- Generated At: $generated_at
- Fill Private Evidence In: \`Config/manual-release-verification.env\`
- Validation Command: \`APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh\`
- Status Command: \`Scripts/print_release_input_status.sh --strict\`
- Selected build placeholder: replace \`PROCESSED_BUILD_NUMBER\` with the processed App Store Connect build number before running selected-build commands; local validators intentionally reject that placeholder.

Use this form while performing the final real-device and iPad checks. Do not write phone
numbers, personal contact details, Apple credentials, UDIDs, certificate files,
private keys, screenshots containing personal data, or signed build artifacts in
this tracked form. Record final pass/fail values only in the git-ignored
\`Config/manual-release-verification.env\` file.

## Prerequisites

- [ ] \`Scripts/verify_release.sh store-ready\` passed locally for the commit selected for release.
- [ ] A signed App Store export was created with \`Scripts/archive_app_store.sh\`.
- [ ] The selected build was uploaded to TestFlight and finished processing in App Store Connect.
- [ ] \`APP_STORE_BUILD_NUMBER\` is set to the processed build selected for App Review.
- [ ] The built-in Test Ruler PDF check passed with \`Scripts/validate_test_ruler_pdf_export.sh\`.
- [ ] A physical iPad is available for TestFlight layout and print workflow validation.

## Real iPhone Evidence

Record these fields in \`Config/manual-release-verification.env\` after testing on a physical iPhone, not a Simulator:

| Evidence | Env field | Required value |
| --- | --- | --- |
| Verifier name or team | \`MANUAL_VERIFIER_NAME\` | Non-empty |
| iPhone model | \`MANUAL_REAL_IPHONE_MODEL\` | Physical device model |
| iOS version | \`MANUAL_REAL_IPHONE_IOS_VERSION\` | Numeric iOS version, e.g. \`18.5\` or \`iOS 18.5\` |
| Test date | \`MANUAL_REAL_IPHONE_TEST_DATE\` | \`YYYY-MM-DD\` |
| Photos import succeeds | \`MANUAL_REAL_IPHONE_PHOTOS_IMPORT\` | \`pass\` |
| Exact-size PDF export succeeds | \`MANUAL_REAL_IPHONE_PDF_EXPORT\` | \`pass\` |
| System print sheet opens with generated PDF | \`MANUAL_REAL_IPHONE_PRINT_SHEET\` | \`pass\` |

Manual notes:

- [ ] Import a real photo from the Photos picker.
- [ ] Set a known target size and export the generated PDF.
- [ ] Open the system print sheet from the exported PDF workflow.

## AirPrint Evidence

Record these fields after printing the built-in Test Ruler on a real printer or a production-equivalent print workflow:

| Evidence | Env field | Required value |
| --- | --- | --- |
| Test date | \`MANUAL_AIRPRINT_TEST_DATE\` | \`YYYY-MM-DD\` |
| Printer or workflow name | \`MANUAL_AIRPRINT_PRINTER\` | Non-empty |
| 0-6 inch ruler prints at exact size | \`MANUAL_AIRPRINT_EXACT_SIZE\` | \`pass\` |
| Target ruler length | \`MANUAL_AIRPRINT_RULER_TARGET_INCHES\` | \`6\` |
| Measured printed ruler length | \`MANUAL_AIRPRINT_RULER_MEASURED_INCHES\` | Decimal inches within 0.0625 of target |

Manual notes:

- [ ] Select the built-in Test Ruler.
- [ ] Print at Actual Size or 100% scale.
- [ ] Compare the printed 0-6 inch marks against a physical ruler and record the measured length in inches.

## TestFlight Evidence

Record these fields after installing the processed App Store build from TestFlight on a physical device:

| Evidence | Env field | Required value |
| --- | --- | --- |
| TestFlight build number | \`MANUAL_TESTFLIGHT_BUILD_NUMBER\` | Same as \`APP_STORE_BUILD_NUMBER\` |
| TestFlight device | \`MANUAL_TESTFLIGHT_DEVICE\` | Physical device model |
| Test date | \`MANUAL_TESTFLIGHT_TEST_DATE\` | \`YYYY-MM-DD\` |
| TestFlight install succeeds | \`MANUAL_TESTFLIGHT_INSTALL\` | \`pass\` |
| Print workflow succeeds from TestFlight build | \`MANUAL_TESTFLIGHT_PRINT_WORKFLOW\` | \`pass\` |

Manual notes:

- [ ] Install the selected build from TestFlight.
- [ ] Repeat the import, sizing, PDF export, and print sheet workflow.
- [ ] Confirm \`MANUAL_TESTFLIGHT_BUILD_NUMBER\` equals the selected \`APP_STORE_BUILD_NUMBER\`.

## iPad TestFlight Evidence

Record these fields after installing the processed App Store build from TestFlight on a physical iPad, not a Simulator:

| Evidence | Env field | Required value |
| --- | --- | --- |
| iPad TestFlight device | \`MANUAL_IPAD_TESTFLIGHT_DEVICE\` | Physical iPad model |
| Test date | \`MANUAL_IPAD_TESTFLIGHT_TEST_DATE\` | \`YYYY-MM-DD\` |
| TestFlight install succeeds on iPad | \`MANUAL_IPAD_TESTFLIGHT_INSTALL\` | \`pass\` |
| iPad layout is usable | \`MANUAL_IPAD_TESTFLIGHT_LAYOUT\` | \`pass\` |
| Print workflow succeeds from iPad TestFlight build | \`MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW\` | \`pass\` |

Manual notes:

- [ ] Install the selected build from TestFlight on a physical iPad.
- [ ] Confirm the editor layout, paper preview, sizing controls, and output actions remain usable on iPad.
- [ ] Repeat the import, sizing, PDF export, and print sheet workflow on iPad.

## Final Commands

\`\`\`sh
Scripts/bootstrap_release_inputs.sh
Scripts/print_release_input_status.sh --strict
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh
\`\`\`
EOF

printf 'Manual release evidence form generated: %s\n' "$output_path"
