# FreePrint Studio Release Checklist

## Local gates

- Run `Scripts/verify_release.sh`.
- Run `Scripts/verify_release.sh store-ready` before handing the project to App Store Connect; it runs the default release gate plus simulator workflow, real Photos import, review UI validation, accessibility screenshots, print sheet validation, and submission packet generation.
- Run `Scripts/validate_app_store_metadata.sh`.
- Run `Scripts/validate_app_privacy_details.sh`.
- Run `Scripts/validate_app_icon_set.sh`.
- Run `Scripts/validate_privacy_surface.sh`.
- Run `Scripts/verify_release.sh questionnaires`; it calls `Scripts/validate_app_store_questionnaires.sh` to validate age rating, App Privacy, accessibility label, and export compliance drafts against app declarations.
- Run `Scripts/bootstrap_release_inputs.sh` before filling private Apple signing, App Review contact, App Store Connect, and manual verification evidence files.
- Use `AppStore/release-inputs-worksheet.md` while collecting private Apple Developer signing values, App Review contact details, App Store Connect credentials, and real-device evidence.
- Run `Scripts/print_release_input_status.sh` to view redacted progress for private release inputs without printing real values.
- Run `Scripts/print_release_input_status.sh --strict` before release handoff so missing required inputs and final submission guards fail locally.
- Run `Scripts/bootstrap_release_env.sh` before filling private Apple signing, App Review contact, and App Store Connect values in `Config/release.env`.
- Run `Scripts/validate_release_env.sh` after creating or editing `Config/release.env`.
- Run `Scripts/verify_release.sh contact-report` before and after setting App Review contact fields to generate a redacted reviewer contact status report.
- Run `Scripts/verify_release.sh manual-report` before and after recording real iPhone, AirPrint, and TestFlight evidence to generate a redacted manual release status report.
- Run `Scripts/verify_release.sh signing-report` before and after installing signing assets to generate a redacted Team ID, certificate, and provisioning profile status report.
- Run `Scripts/verify_release.sh asc-report` before and after configuring App Store Connect credentials, TestFlight upload, or review submission inputs to generate a redacted account readiness report.
- Run `Scripts/verify_release.sh review-report` before final App Review preflight to generate a redacted metadata, policy, evidence, credential, and selected-build readiness report.
- Run `Scripts/check_code_signing_assets.sh` after installing certificates or provisioning profiles.
- Run `Scripts/verify_release.sh archive-preflight` before creating the signed App Store archive.
- Run `Scripts/validate_app_store_export.sh` after creating a signed archive and App Store IPA.
- Run `Scripts/validate_app_review_contact.sh` after setting App Review contact values.
- Run `Scripts/validate_pdf_export.sh` after print/PDF rendering changes; it validates Fit, Fill, and Stretch PDF output.
- Run `Scripts/verify_release.sh simulator-workflow`; it calls `Scripts/validate_simulator_workflow.sh` to launch the app in a simulator with a generated selected image, centimeter units, A4 landscape paper, a screenshot, and PDF export.
- Run `Scripts/verify_release.sh photo-import`; it calls `Scripts/validate_photo_import.sh` to seed the simulator photo library, open the real Photos picker, choose an image, verify export/print become available, and verify About screen privacy/support/version review information remains reachable.
- Run `Scripts/verify_release.sh review-ui`; it calls `Scripts/validate_review_ui.sh` to verify the App Review-facing About screen privacy policy, support URL, and app version without the full Photos picker workflow.
- Run `Scripts/check_app_store_readiness.sh`; fix every `BLOCKED` item before archiving.
- Run `Scripts/capture_app_store_screenshot_set.sh` after UI, fit mode, paper, orientation, unit, or iPad layout changes and inspect `iphone-main.jpg`, `iphone-test-ruler.jpg`, `iphone-fit.jpg`, `iphone-fill.jpg`, `iphone-stretch.jpg`, `iphone-metric-landscape.jpg`, and `ipad-main.jpg`.
- Run `Scripts/capture_app_store_screenshots.sh` only when refreshing or debugging one screenshot in isolation.
- Run the standalone iPad screenshot command from `README.md` only when refreshing or debugging the iPad screenshot in isolation.
- Run `Scripts/verify_release.sh accessibility` after visible UI changes; it calls `Scripts/validate_accessibility_screenshots.sh` for dark interface and Larger Text screenshots.
- Run `Scripts/verify_release.sh print-sheet` before submission; it calls `Scripts/validate_print_sheet.sh` to verify the simulator can open the system print sheet with a generated PDF.
- Run `Scripts/verify_release.sh submission-packet` before handing off to App Store Connect; it calls `Scripts/prepare_app_store_submission_packet.sh` to package metadata, questionnaire drafts, screenshots, PDF export validation evidence, a blank manual release evidence form, redacted App Review contact, manual release, signing, App Store Connect, and App Review submission readiness reports, checksums, readiness audit output, and next commands under `build/AppStoreSubmissionPacket/`.
- Run `Scripts/verify_release.sh submission-packet-check` before uploading or handing off the packet; it calls `Scripts/validate_app_store_submission_packet.sh` to verify required files, evidence manifests, external action tracking, and absence of local absolute paths.
- GitHub Actions uploads the generated App Store submission packet from successful Release Gates runs as the `freeprintstudio-app-store-submission-packet` artifact.
- Run `Scripts/validate_manual_release_verification.sh` after recording real iPhone, AirPrint, and TestFlight evidence in untracked `Config/manual-release-verification.env`.
- Confirm real Photos import on a simulator when changing the Photos picker; the generated-image simulator workflow above covers app launch, unit switching, screenshot rendering, and PDF export.
- Confirm the same flow on a real iPhone.
- Confirm AirPrint output on a real printer or a production-equivalent print workflow with the built-in Test Ruler.
- Enable GitHub Pages from the repository `docs` folder and verify the privacy and support URLs in `AppStore/metadata.md`.

## App Store Connect

- Create the App Store Connect app record for bundle ID `com.dannagrace.FreePrintStudio`.
- Configure signing with an Apple Developer Program team in Xcode.
- Fill local release environment values from `Config/release.env.example`; release scripts automatically load `Config/release.env` when it exists. Keep `Config/release.env` and any `AuthKey_*.p8` private key out of git.
- Set private App Review contact values before metadata upload or submission: `APP_REVIEW_CONTACT_FIRST_NAME`, `APP_REVIEW_CONTACT_LAST_NAME`, `APP_REVIEW_CONTACT_PHONE`, and `APP_REVIEW_CONTACT_EMAIL`.
- Run `Scripts/preflight_app_store_archive.sh` and fix every failed step before archiving.
- Archive with Xcode 26 or later using `DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh`.
- Confirm `Scripts/archive_app_store.sh` finishes the `Validate Export` step before uploading the IPA.
- Upload the signed archive or exported IPA to App Store Connect.
- Add app name, subtitle, description, promotional text, keywords, categories, review notes, and support contact from `AppStore/metadata.md`; the reusable Fastlane copy lives under `fastlane/metadata/en-US`.
- Optional automation: run `Scripts/install_release_dependencies.sh` or `brew install fastlane`, then `Scripts/run_fastlane.sh ios metadata` to upload App Store metadata and screenshots without submitting for review.
- App Privacy automation: verify `AppStore/app_privacy_details.json`, then run `FASTLANE_USER=... CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details`.
- TestFlight upload preflight: after creating the signed export and configuring App Store Connect API credentials, run `Scripts/preflight_testflight_upload.sh`.
- Optional TestFlight automation: configure `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH`, then run `Scripts/run_fastlane.sh ios upload_testflight` to upload the exported IPA without external distribution.
- App Store Connect state preflight: after the build processes, run `APP_STORE_BUILD_NUMBER=... Scripts/run_fastlane.sh ios app_store_connect_state` to verify the app record, version, and selected build before review submission.
- Replace any `PROCESSED_BUILD_NUMBER` placeholder in generated handoff commands with the processed App Store Connect build number before running them; the local release validators intentionally reject that placeholder.
- Commercial configuration: apply `AppStore/commercial-configuration.md` in App Store Connect before submission.
- App Review self-audit: review `AppStore/review-guideline-audit.md` and resolve every open blocker before submission.
- Manual release evidence: run `Scripts/bootstrap_release_inputs.sh` and `Scripts/verify_release.sh manual-evidence-form`, record real-device verification in `Config/manual-release-verification.env`, and use the built-in Test Ruler for `MANUAL_AIRPRINT_EXACT_SIZE`, `MANUAL_AIRPRINT_RULER_TARGET_INCHES`, and `MANUAL_AIRPRINT_RULER_MEASURED_INCHES`, then run `APP_STORE_BUILD_NUMBER=... Scripts/validate_manual_release_verification.sh` with the same APP_STORE_BUILD_NUMBER selected for App Review.
- App Review submission preflight: after every listing field is final and the selected build has processed, run `APP_STORE_BUILD_NUMBER=... Scripts/preflight_app_review_submission.sh`.
- Final review submission automation: after the uploaded build has processed and every listing field is final, run `APP_STORE_BUILD_NUMBER=... CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review`; the `submit_review` lane re-runs manual release evidence validation before contacting App Store Connect.
- Upload screenshots from `fastlane/screenshots/en-US` or through App Store Connect.
- Host a public privacy policy page and add its URL in App Store Connect.
- Enter App Privacy details as no data collected, no tracking, no third-party analytics, and no advertising SDKs.
- Complete App Privacy using `AppStore/app-privacy.md`.
- Complete age rating using `AppStore/age-rating.md`.
- Complete Accessibility Nutrition Label fields using `AppStore/accessibility-labels.md` after validating the listed device checks.
- Complete export compliance using `AppStore/export-compliance.md`; `Info.plist` declares `ITSAppUsesNonExemptEncryption` as false.
- Upload final screenshots accepted by App Store Connect for every supported device family.
- If iPad remains supported, validate the iPad UI on a real device or TestFlight and upload iPad screenshots.
- Run TestFlight on at least one real device before submitting for review.

## Current Apple references

- Submitting apps: https://developer.apple.com/app-store/submitting/
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
