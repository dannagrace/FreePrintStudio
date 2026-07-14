# FreePrint Studio Release Inputs Worksheet

Use this worksheet when collecting the private Apple account, signing, and real-device evidence required before App Store submission. Do not paste secrets, certificates, private keys, phone numbers, or personal contact details into this tracked file. Fill those values only in the git-ignored local files created by:

```sh
Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config
Scripts/print_release_input_status.sh --strict
```

## Private File Rules

- Fill Apple signing, App Review contact, App Store Connect, and submission guard values in `Config/release.env`.
- Fill real iPhone, AirPrint, iPad, and TestFlight evidence in `Config/manual-release-verification.env`.
- Keep `Config/release.env`, `Config/manual-release-verification.env`, `AuthKey_*.p8`, `*.p12`, `*.mobileprovision`, `*.ipa`, and `*.xcarchive` out of git.
- Run `Scripts/print_release_input_status.sh --strict` after installing templates and after every private value update. The output is redacted and shows missing fields without exposing values.
- Run `git status --short --ignored Config/release.env Config/manual-release-verification.env` and confirm both files appear as ignored before adding any release values.

## App Review Contact

Fill these values in `Config/release.env`, then run `Scripts/validate_app_review_contact.sh`:

- `APP_REVIEW_CONTACT_FIRST_NAME`
- `APP_REVIEW_CONTACT_LAST_NAME`
- `APP_REVIEW_CONTACT_PHONE`
- `APP_REVIEW_CONTACT_EMAIL`

Use the person or team Apple can contact during review. The email and phone must be reachable during the review window.

## Apple Developer Signing

Fill or install these assets before creating the App Store archive:

- `DEVELOPMENT_TEAM_ID`: Apple Developer Program Team ID for the App Store Connect account.
- `Apple Distribution` certificate: installed in the login keychain and trusted by Xcode.
- App Store Connect provisioning profile: installed under `~/Library/MobileDevice/Provisioning Profiles` and matching `com.dannagrace.FreePrintStudio`.
- `ALLOW_PROVISIONING_UPDATES=1`: enable only when Xcode should manage provisioning for the configured team.

Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands.

Validate signing before archiving:

```sh
Scripts/check_code_signing_assets.sh
Scripts/preflight_app_store_archive.sh
```

## App Store Connect Credentials

API credentials are optional when the app is uploaded and submitted through the signed-in App Store Connect web interface. Choose one credential path only when Fastlane automation is required, and keep the key file private.

Option A, Fastlane API JSON in `Config/release.env`:

- `APP_STORE_CONNECT_API_KEY_JSON=/absolute/path/to/fastlane-api-key.json`

Option B, API key triplet in `Config/release.env`:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_PATH=/absolute/path/AuthKey_XXXXXXXXXX.p8`

Optional Apple ID flow for App Privacy Details upload:

- `FASTLANE_USER`
- `FASTLANE_ITC_TEAM_ID` or `FASTLANE_ITC_TEAM_NAME`, if the Apple ID belongs to more than one team.
- `CONFIRM_UPLOAD_APP_PRIVACY=1` only when the App Privacy Details JSON has been reviewed.
- `APP_PRIVACY_SKIP_PUBLISH=1` only for App Privacy Details dry-run validation when you need to verify the Fastlane flow without publishing answers.

Final App Privacy Details confirmation:

- `APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1` after Fastlane upload or manual App Store Connect entry matches `AppStore/app_privacy_details.json`.
- Validate with `Scripts/validate_app_privacy_connect_entry.sh`.

Final commercial configuration confirmation:

- `APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1` after App Store Connect Pricing, Availability, monetization, release option, and phased release match `AppStore/commercial-configuration.md`.
- Validate with `Scripts/validate_commercial_configuration_connect_entry.sh`.

Validate credentials before automated TestFlight upload or API-mode review submission:

```sh
Scripts/check_app_store_connect_credentials.sh
Scripts/preflight_testflight_upload.sh
```

Upload metadata and screenshots after App Review contact values and App Store Connect API credentials are configured:

```sh
Scripts/preflight_metadata_upload.sh
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios metadata
```

Upload App Privacy Details after reviewing `AppStore/app_privacy_details.json` against the App Store Connect answers:

```sh
FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh
FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details
APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh
APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_commercial_configuration_connect_entry.sh
```

Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.

## TestFlight Upload Inputs

Fill these optional upload overrides in `Config/release.env` only when the defaults do not match the signed artifact or release notes:

- `IPA_PATH=/absolute/path/to/FreePrintStudio.ipa`: signed App Store IPA to upload when not using the default export path.
- `TESTFLIGHT_CHANGELOG`: build notes shown to TestFlight testers.

Validate the upload inputs before uploading the signed build:

```sh
Scripts/preflight_testflight_upload.sh
Scripts/run_fastlane.sh ios upload_testflight
```

## Manual Release Verification

Record real-device evidence in `Config/manual-release-verification.env`. Result fields must use lowercase `pass`.

Real iPhone evidence:

- `MANUAL_VERIFIER_NAME`
- `MANUAL_REAL_IPHONE_MODEL`
- `MANUAL_REAL_IPHONE_IOS_VERSION`
- `MANUAL_REAL_IPHONE_TEST_DATE`
- `MANUAL_REAL_IPHONE_PHOTOS_IMPORT=pass`
- `MANUAL_REAL_IPHONE_PDF_EXPORT=pass`
- `MANUAL_REAL_IPHONE_PRINT_SHEET=pass`

AirPrint or production-equivalent print evidence:

- `MANUAL_AIRPRINT_TEST_DATE`
- `MANUAL_AIRPRINT_PRINTER`
- `MANUAL_AIRPRINT_EXACT_SIZE=pass`: print the built-in Test Ruler at Actual Size (100%) and compare the 0-6 inch marks.
- `MANUAL_AIRPRINT_RULER_TARGET_INCHES=6`
- `MANUAL_AIRPRINT_RULER_MEASURED_INCHES`: record the physical ruler measurement in decimal inches; the validator allows at most 0.0625 inch difference from the target.

Before recording AirPrint evidence, run the local Test Ruler PDF check to confirm the app-generated calibration guide exports at exactly 6 x 1 inch:

```sh
Scripts/validate_test_ruler_pdf_export.sh
```

TestFlight evidence:

- `MANUAL_TESTFLIGHT_BUILD_NUMBER`
- `MANUAL_TESTFLIGHT_DEVICE`
- `MANUAL_TESTFLIGHT_TEST_DATE`
- `MANUAL_TESTFLIGHT_INSTALL=pass`
- `MANUAL_TESTFLIGHT_PRINT_WORKFLOW=pass`

The TestFlight evidence must be for the same APP_STORE_BUILD_NUMBER selected for App Review. Validate with:

```sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh
```

Replace `PROCESSED_BUILD_NUMBER` with the processed build selected in App Store Connect.

iPad TestFlight evidence is required because the app targets iPhone and iPad:

- `MANUAL_IPAD_TESTFLIGHT_DEVICE`: physical iPad model, not a Simulator.
- `MANUAL_IPAD_TESTFLIGHT_TEST_DATE`
- `MANUAL_IPAD_TESTFLIGHT_INSTALL=pass`
- `MANUAL_IPAD_TESTFLIGHT_LAYOUT=pass`: editor layout, preview, sizing controls, and output actions remain usable on iPad.
- `MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW=pass`

## Final Submission Guards

Set these only after the signed build is uploaded, processed, and selected for App Review:

- `APP_STORE_BUILD_NUMBER`: the processed App Store Connect build to submit.
- `APP_STORE_CONNECT_SUBMISSION_MODE=manual`: select the signed-in web submission path; use `api` only for Fastlane submission.
- `APP_STORE_CONNECT_MANUAL_STATE_CONFIRMED=1`: set after checking the App Store version page.
- `APP_STORE_CONNECT_MANUAL_STATE_BUILD_NUMBER`: must match `APP_STORE_BUILD_NUMBER`.
- `APP_STORE_CONNECT_MANUAL_STATE_VERIFIED_DATE`: browser verification date in `YYYY-MM-DD`; refresh it immediately before submission.
- `CONFIRM_SUBMIT_FOR_REVIEW=1`: Fastlane-only final guard for `Scripts/run_fastlane.sh ios submit_review`.

Before final submission, confirm metadata upload, screenshot upload, App Privacy Details, `APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1`, and `APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1` are complete in App Store Connect.

Run the final preflight before submission:

```sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh
```

For manual mode, obtain explicit action-time approval and click **Add for Review** on the signed-in App Store Connect version page. For API mode, submit only after the preflight passes:

```sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review
```

## Readiness Audit

After filling any private release value or installing signing assets, rerun:

```sh
Scripts/validate_release_env.sh
Scripts/check_app_store_readiness.sh
```

Every `BLOCKED` item must be resolved before the App Store archive and final submission flow.
