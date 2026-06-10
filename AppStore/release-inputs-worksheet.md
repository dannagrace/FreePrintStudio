# FreePrint Studio Release Inputs Worksheet

Use this worksheet when collecting the private Apple account, signing, and real-device evidence required before App Store submission. Do not paste secrets, certificates, private keys, phone numbers, or personal contact details into this tracked file. Fill those values only in the git-ignored local files created by:

```sh
Scripts/bootstrap_release_inputs.sh
```

## Private File Rules

- Fill Apple signing, App Review contact, App Store Connect, and submission guard values in `Config/release.env`.
- Fill real iPhone, AirPrint, and TestFlight evidence in `Config/manual-release-verification.env`.
- Keep `Config/release.env`, `Config/manual-release-verification.env`, `AuthKey_*.p8`, `*.p12`, `*.mobileprovision`, `*.ipa`, and `*.xcarchive` out of git.
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

Validate signing before archiving:

```sh
Scripts/check_code_signing_assets.sh
Scripts/preflight_app_store_archive.sh
```

## App Store Connect Credentials

Choose one credential path for automation and keep the key file private.

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

Validate credentials before TestFlight upload or final review submission:

```sh
Scripts/check_app_store_connect_credentials.sh
Scripts/preflight_testflight_upload.sh
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
APP_STORE_BUILD_NUMBER=<processed-build> Scripts/validate_manual_release_verification.sh
```

Replace `<processed-build>` with the processed build selected in App Store Connect.

## Final Submission Guards

Set these only after the signed build is uploaded, processed, and selected for App Review:

- `APP_STORE_BUILD_NUMBER`: the processed App Store Connect build to submit.
- `CONFIRM_SUBMIT_FOR_REVIEW=1`: final guard for `Scripts/run_fastlane.sh ios submit_review`.

Run the final preflight before submission:

```sh
APP_STORE_BUILD_NUMBER=<processed-build> Scripts/preflight_app_review_submission.sh
```

Submit only after the preflight passes:

```sh
APP_STORE_BUILD_NUMBER=<processed-build> CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review
```

## Readiness Audit

After filling any private release value or installing signing assets, rerun:

```sh
Scripts/validate_release_env.sh
Scripts/check_app_store_readiness.sh
```

Every `BLOCKED` item must be resolved before the App Store archive and final submission flow.
