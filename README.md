# FreePrint Studio

FreePrint Studio is a small iOS app for printing an image at an exact physical size.

## MVP

- Choose a paper preset: Letter, A4, 4 x 6, or 5 x 7.
- Switch paper orientation between portrait and landscape.
- Pick an image from Photos.
- Enter the desired printed width and height in inches, centimeters, or millimeters.
- Switch units while preserving the same physical print size.
- Choose Fit, Fill, or Stretch image placement.
- Preview the image on a paper canvas.
- Drag the image within the page.
- Export a correctly sized PDF.
- Open the system AirPrint sheet for printing.

## Development

The sizing and layout logic lives in `FreePrintStudioCore` and is covered by a lightweight Swift package check target.

```sh
swift build
swift run FreePrintStudioCoreChecks
```

Open `FreePrintStudio.xcodeproj` in Xcode to run the iOS app.

## Release Preparation

Run the local release gate before archiving:

```sh
Scripts/verify_release.sh
```

Run the full local store-ready gate before handing the project to App Store Connect. This runs the default release gate plus simulator workflow, real Photos import, accessibility screenshots, print sheet validation, and submission packet generation:

```sh
Scripts/verify_release.sh store-ready
```

Validate App Store text metadata limits before uploading with Fastlane:

```sh
Scripts/validate_app_store_metadata.sh
```

Validate App Privacy Details before uploading them to App Store Connect:

```sh
Scripts/validate_app_privacy_details.sh
```

Validate the full iPhone, iPad, and App Store marketing icon catalog:

```sh
Scripts/validate_app_icon_set.sh
```

Validate that the app source and release configuration still match the no-data-collection and no-tracking privacy disclosures:

```sh
Scripts/validate_privacy_surface.sh
```

Validate that the App Store questionnaire drafts agree with the app's plist declarations, privacy manifest, App Privacy JSON, and limited public links:

```sh
Scripts/verify_release.sh questionnaires
# Or directly:
Scripts/validate_app_store_questionnaires.sh
```

Validate that the app renderer exports PDFs with the expected paper MediaBox and embedded image output for Fit, Fill, and Stretch modes:

```sh
Scripts/validate_pdf_export.sh
```

Validate that the built-in Test Ruler exports as a 6 x 1 inch PDF target before using it for AirPrint evidence:

```sh
Scripts/validate_test_ruler_pdf_export.sh
```

Validate a simulator workflow with a generated selected image, centimeter units, landscape A4 paper, an app screenshot, and PDF export:

```sh
Scripts/verify_release.sh simulator-workflow
# Or directly:
Scripts/validate_simulator_workflow.sh
```

Validate that the real Photos picker can import an image from the simulator photo library and enable the export/print workflow:

```sh
Scripts/verify_release.sh photo-import
# Or directly:
Scripts/validate_photo_import.sh
```

Validate that private release settings do not still contain copied placeholder values:

```sh
Scripts/bootstrap_release_inputs.sh
Scripts/bootstrap_release_env.sh
Scripts/validate_release_env.sh
```

Use `AppStore/release-inputs-worksheet.md` while collecting private Apple Developer signing values, App Review contact details, App Store Connect credentials, and manual real-device evidence. Keep filled values only in the git-ignored local files created by `Scripts/bootstrap_release_inputs.sh`.

Print a redacted summary of private release input progress without exposing real values:

```sh
Scripts/print_release_input_status.sh
Scripts/print_release_input_status.sh --strict
```

Use the strict form before release handoff so missing final submission guards fail locally.

Generate a redacted App Review contact readiness report before and after setting reviewer contact fields:

```sh
Scripts/verify_release.sh contact-report
```

Generate a redacted manual release readiness report before and after recording real iPhone, AirPrint, and TestFlight evidence:

```sh
Scripts/verify_release.sh manual-report
```

Generate a redacted signing readiness report before and after installing certificates or provisioning profiles:

```sh
Scripts/verify_release.sh signing-report
```

Generate a redacted App Store Connect readiness report before and after configuring API credentials, TestFlight upload, or review submission inputs:

```sh
Scripts/verify_release.sh asc-report
```

Generate a redacted App Review submission readiness report before the final preflight:

```sh
Scripts/verify_release.sh review-report
```

Validate that installed signing assets match the release bundle, Apple team, and App Store Connect export method:

```sh
Scripts/check_code_signing_assets.sh
```

Run the full App Store archive preflight after private release values and signing assets are configured, before creating the signed archive:

```sh
Scripts/verify_release.sh archive-preflight
# Or directly:
Scripts/preflight_app_store_archive.sh
```

Validate a signed archive and exported App Store IPA before uploading to TestFlight:

```sh
Scripts/validate_app_store_export.sh
```

Validate the private App Review contact fields before metadata upload or review submission:

```sh
Scripts/validate_app_review_contact.sh
```

GitHub Actions runs `Scripts/verify_release.sh` on pushes to `main` and pull requests.

Audit App Store readiness, including public URLs, screenshots, Xcode, and signing state:

```sh
Scripts/check_app_store_readiness.sh
```

This audit exits nonzero until an Apple Developer Team ID, signing identity, and provisioning profile are available.
The signing check requires an `Apple Distribution` identity and an App Store provisioning profile for `com.dannagrace.FreePrintStudio`; development or Ad Hoc profiles are not accepted.

Generate the draft App Store screenshots. The default iPhone command prefers a 6.9-inch simulator such as iPhone 17 Pro Max, and the screenshot set command syncs the reviewed assets to Fastlane.

```sh
Scripts/capture_app_store_screenshot_set.sh
```

Capture or debug a single screenshot when needed:

```sh
Scripts/capture_app_store_screenshots.sh
SIMULATOR_UDID=2E8A23AC-6267-44FB-94A7-49221C184C79 SCREENSHOT_PATH="$PWD/AppStore/Screenshots/ipad-main.jpg" Scripts/capture_app_store_screenshots.sh
```

Validate dark mode and Larger Text screenshots without permanently changing the simulator:

```sh
Scripts/verify_release.sh accessibility
# Or directly:
Scripts/validate_accessibility_screenshots.sh
```

Validate that the simulator workflow can open the system print sheet:

```sh
Scripts/verify_release.sh print-sheet
# Or directly:
Scripts/validate_print_sheet.sh
```

Record and validate manual real-device, AirPrint, and TestFlight evidence before final App Review submission:

```sh
Scripts/bootstrap_release_inputs.sh
Scripts/verify_release.sh manual-evidence-form
APP_STORE_BUILD_NUMBER=1 Scripts/validate_manual_release_verification.sh
```

When validating the final App Review build, run the manual evidence check with the same APP_STORE_BUILD_NUMBER that will be submitted so the tested TestFlight build cannot drift from the selected App Store build.

Prepare a local App Store submission packet with metadata, questionnaire drafts, screenshots, PDF export validation evidence, the blank manual release evidence form, redacted App Review contact, manual release, signing, App Store Connect, and App Review submission readiness reports, checksums, readiness audit output, and next commands:

```sh
Scripts/verify_release.sh submission-packet
# Or directly:
Scripts/prepare_app_store_submission_packet.sh
```

GitHub Actions uploads the generated App Store submission packet from successful Release Gates runs as the `freeprintstudio-app-store-submission-packet` artifact.

Release metadata, screenshot assets, and the remaining App Store Connect checklist live under `AppStore/`.

Use `AppStore/commercial-configuration.md` for App Store Connect pricing, availability, monetization, and manual release settings. The MVP configuration is free, all App Store countries or regions, no in-app purchases, no subscriptions, no advertising, and manual release after approval.

Use `AppStore/review-guideline-audit.md` as the App Review self-audit. It maps Apple review, privacy, commerce, metadata, SDK, and final-submission expectations to local evidence and remaining blockers.

Prepare a signed App Store archive after configuring an Apple Developer Team in Xcode:

```sh
Scripts/preflight_app_store_archive.sh
DEVELOPMENT_TEAM_ID=ABCDE12345 ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh
```

The archive script runs the local release gate first, then creates `build/FreePrintStudio.xcarchive` and exports an App Store Connect IPA under `build/AppStoreExport/`.
After export it runs `Scripts/validate_app_store_export.sh`, which checks the archive metadata, signed app bundle, dSYM, IPA `Payload`, bundle ID, app version, and build number before upload.
`Config/release.env.example` lists the signing and App Store Connect variables used by the release scripts. Its placeholder assignments are commented out so a copied file cannot accidentally satisfy readiness checks. Keep the filled file and any `AuthKey_*.p8` private key outside git.
Release scripts automatically load `Config/release.env` when it exists; set `RELEASE_ENV_PATH` to load a different private env file.

App Store Connect metadata is mirrored under `fastlane/`. Install Fastlane through the project Bundler path or Homebrew, then upload metadata and screenshots without submitting for review:

```sh
Scripts/install_release_dependencies.sh
# Or: brew install fastlane
Scripts/run_fastlane.sh ios metadata
```

The Fastlane metadata, App Privacy Details, and final review-submission lanes run the local App Store questionnaire validation before uploading or submitting.

Before uploading metadata or submitting for review, set the private App Review contact values in your shell or untracked `Config/release.env`. Do not commit real personal contact details.

```sh
APP_REVIEW_CONTACT_FIRST_NAME=YOUR_FIRST_NAME
APP_REVIEW_CONTACT_LAST_NAME=YOUR_LAST_NAME
APP_REVIEW_CONTACT_PHONE=+1-555-0100
APP_REVIEW_CONTACT_EMAIL=review-contact@example.com
```

Fastlane reads the reviewer test notes from `fastlane/metadata/review_information/notes.txt` and combines them with the private contact values above.

App Privacy Details are represented by `AppStore/app_privacy_details.json`. After reviewing it against `AppStore/app-privacy.md`, upload and publish it to App Store Connect:

```sh
FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details
```

Set `APP_PRIVACY_SKIP_PUBLISH=1` to upload the App Privacy Details without publishing them.

Fastlane can also call the local gates and create the signed archive:

```sh
Scripts/run_fastlane.sh ios verify
Scripts/run_fastlane.sh ios readiness
Scripts/run_fastlane.sh ios archive
```

After the archive exports an IPA and an App Store Connect API key is configured, upload the build to TestFlight without external distribution:

```sh
Scripts/preflight_testflight_upload.sh
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight
```

If the exported IPA lives outside the default `build/AppStoreExport/` folder, pass `IPA_PATH=/absolute/path/to/FreePrintStudio.ipa`.

After the build has processed in App Store Connect, verify the app record, version, and selected TestFlight build:

```sh
APP_STORE_BUILD_NUMBER=1 Scripts/run_fastlane.sh ios app_store_connect_state
```

Before submitting for App Review, run the final preflight without triggering submission:

```sh
APP_STORE_BUILD_NUMBER=1 Scripts/preflight_app_review_submission.sh
```

The preflight requires `MANUAL_TESTFLIGHT_BUILD_NUMBER` in `Config/manual-release-verification.env` to match the same APP_STORE_BUILD_NUMBER.

After the uploaded build is processed in App Store Connect and the store listing, privacy details, age rating, screenshots, and review contact details are final, submit the selected build for App Review:

```sh
APP_STORE_BUILD_NUMBER=1 CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review
```

`submit_review` uses manual release (`automatic_release: false`) and submits only the explicit `APP_STORE_BUILD_NUMBER`.

App Store Connect questionnaire drafts are stored in:

- `AppStore/app-privacy.md`
- `AppStore/age-rating.md`
- `AppStore/accessibility-labels.md`
- `AppStore/export-compliance.md`

The privacy and support pages are in `docs/`. For the metadata URLs in `AppStore/metadata.md` to be public, enable GitHub Pages for this repository from the `docs` folder.
