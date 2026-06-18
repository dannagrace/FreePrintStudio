# FreePrint Studio Release Checklist

## Local gates

- Run `Scripts/verify_release.sh`.
- Run `Scripts/verify_release.sh store-ready` before handing the project to App Store Connect; it runs the default release gate plus simulator workflow, real Photos import, review UI validation, accessibility screenshots, print sheet validation, strict public privacy/support page validation, and submission packet generation and validation.
- Run `Scripts/validate_app_store_metadata.sh`.
- Run `Scripts/validate_app_privacy_details.sh`.
- Run `Scripts/validate_app_icon_set.sh`.
- Run `Scripts/validate_privacy_surface.sh`.
- Run `Scripts/verify_release.sh questionnaires`; it calls `Scripts/validate_app_store_questionnaires.sh` to validate age rating, App Privacy, accessibility label, and export compliance drafts against app declarations.
- Run `Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config` before filling private Apple signing, App Review contact, App Store Connect, and manual verification evidence files from generated handoff templates.
- Use `AppStore/release-inputs-worksheet.md` while collecting private Apple Developer signing values, App Review contact details, App Store Connect credentials, and real-device evidence.
- Run `Scripts/validate_private_release_artifact_ignores.sh` before filling private values and before release handoff; it verifies private release inputs, backups, App Store Connect keys, signing files, provisioning profiles, IPA files, and Xcode archives stay ignored, untracked, and restricted to owner-only permissions.
- Run `Scripts/print_release_input_status.sh` to view redacted progress for private release inputs without printing real values.
- Run `Scripts/print_release_input_status.sh --strict` before release handoff so missing required inputs and final submission guards fail locally.
- Run `Scripts/validate_release_env.sh` after creating or editing `Config/release.env`.
- Run `Scripts/verify_release.sh contact-report` before and after setting App Review contact fields to generate a redacted reviewer contact status report.
- Run `Scripts/verify_release.sh manual-report` before and after recording real iPhone, AirPrint, iPad, and TestFlight evidence to generate a redacted manual release status report.
- Run `Scripts/verify_release.sh signing-report` before and after installing signing assets to generate a redacted Team ID, certificate, and provisioning profile status report.
- Run `Scripts/verify_release.sh asc-report` before and after configuring App Store Connect credentials, TestFlight upload, or review submission inputs to generate a redacted account readiness report.
- Run `Scripts/verify_release.sh asc-state-report` after selecting a processed TestFlight build, or before handoff to show the redacted selected-build App Store Connect state check output and exit code.
- Run `Scripts/verify_release.sh review-report` before final App Review preflight to generate a redacted metadata, policy, evidence, credential, and selected-build readiness report.
- Run `Scripts/verify_release.sh public-pages-report` before release handoff to generate a public privacy/support page status report.
- Run `Scripts/verify_release.sh public-pages` before metadata upload or review submission to strictly validate deployed privacy/support page reachability.
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
- Run `Scripts/verify_release.sh screenshots` before screenshot upload; it validates dimensions, blank-content, alpha, reviewed-to-Fastlane sync, and screenshot privacy metadata.
- Run `Scripts/capture_app_store_screenshots.sh` only when refreshing or debugging one screenshot in isolation.
- Run the standalone iPad screenshot command from `README.md` only when refreshing or debugging the iPad screenshot in isolation.
- Run `Scripts/verify_release.sh accessibility` after visible UI changes; it calls `Scripts/validate_accessibility_screenshots.sh` for dark interface and Larger Text screenshots.
- Run `Scripts/verify_release.sh print-sheet` before submission; it calls `Scripts/validate_print_sheet.sh` to verify the simulator can open the system print sheet with a generated PDF.
- Run `Scripts/verify_release.sh submission-packet` before handing off to App Store Connect; it calls `Scripts/prepare_app_store_submission_packet.sh` to package metadata, questionnaire drafts, screenshots, PDF export validation evidence, a blank manual release evidence form, redacted App Review contact, manual release, signing, App Store Connect readiness, App Store Connect state, App Review submission readiness, public pages readiness reports, per-owner `owner-action-briefs/`, blank `private-release-input-templates/`, checksums, readiness audit output, and next commands under `build/AppStoreSubmissionPacket/`.
- Run `Scripts/verify_release.sh submission-packet-check` before uploading or handing off the packet; it calls `Scripts/validate_app_store_submission_packet.sh` to verify required files, evidence manifests, external action tracking, and absence of local absolute paths.
- GitHub Actions uploads the generated App Store submission packet from successful Release Gates runs as the `freeprintstudio-app-store-submission-packet` artifact.
- Run `Scripts/download_latest_submission_packet.sh` to download and validate the latest successful CI-generated submission packet before release handoff. It uses the GitHub artifact API download path by default because `gh run download` can stall during handoff. Tune `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_ATTEMPTS` and `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_TIMEOUT_SECONDS` if GitHub artifact downloads are slow or hang. To explicitly select the default API path, run `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_METHOD=api Scripts/download_latest_submission_packet.sh`; to try `gh run download` first and keep the GitHub artifact API fallback, run `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_METHOD=auto Scripts/download_latest_submission_packet.sh`; to force only `gh run download`, use `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_METHOD=gh`.
- Run `Scripts/preflight_release_handoff.sh` before release handoff; it requires a clean local worktree, downloads the latest successful CI packet, verifies packet provenance against local `HEAD`, validates `external-readiness-actions.tsv`, runs the local readiness audit, writes `build/release-handoff-summary.tsv` with the CI readiness blocker count, local readiness blocker count, CI/local readiness delta, external action blocker count, `build/release-input-todo.md` path, `build/release-phase-plan.md` path, `build/release-owner-actions/` path, and `build/private-release-input-templates/` path, writes `build/release-handoff-brief.md` with CI/local readiness delta, handoff brief Owner Summary, and owner-scoped external action details for the release owner, writes `build/release-input-todo.md` with an Owner Summary plus fillable private release input fields grouped by target file, writes `build/release-phase-plan.md` with phase-ordered release work and validation gates from the same external action manifest, writes per-owner action files under `build/release-owner-actions/` from the packet `owner-action-briefs/` workflow, and writes blank private env starters under `build/private-release-input-templates/` from the packet `private-release-input-templates/` workflow.
- Run `Scripts/install_private_release_input_templates.sh` after handoff preflight to install the generated blank starters into git-ignored `Config/release.env` and `Config/manual-release-verification.env`; existing private values are backed up and preserved while missing keys are appended.
- Run `Scripts/validate_release_handoff_summary.sh build/release-handoff-summary.tsv` if the generated handoff files are moved or reviewed later; it verifies that summary counts still match the referenced readiness logs and external action manifest.
- Run `Scripts/validate_release_handoff_brief.sh build/CISubmissionPacket/external-readiness-actions.tsv build/release-handoff-brief.md build/CISubmissionPacket/readiness.txt build/release-handoff-readiness.txt` if the generated handoff files are moved or reviewed later; it verifies that the human-readable brief still matches the external action manifest and the CI/local readiness delta details.
- Run `Scripts/validate_manual_release_verification.sh` after recording real iPhone, AirPrint, iPad, and TestFlight evidence in untracked `Config/manual-release-verification.env`.
- Confirm real Photos import on a simulator when changing the Photos picker; the generated-image simulator workflow above covers app launch, unit switching, screenshot rendering, and PDF export.
- Confirm the same flow on a real iPhone.
- Confirm AirPrint output on a real printer or a production-equivalent print workflow with the built-in Test Ruler.
- Set GitHub Pages source to GitHub Actions, run `.github/workflows/pages.yml`, and verify both `Scripts/check_github_pages_source.sh` and the privacy/support URLs in `AppStore/metadata.md`.

## App Store Connect

- Create the App Store Connect app record for bundle ID `com.dannagrace.FreePrintStudio`.
- Configure signing with an Apple Developer Program team in Xcode.
- Fill local release environment values in the git-ignored `Config/release.env` installed from generated handoff templates; release scripts automatically load `Config/release.env` when it exists. Keep `Config/release.env` and any `AuthKey_*.p8` private key out of git.
- Set private App Review contact values before metadata upload or submission: `APP_REVIEW_CONTACT_FIRST_NAME`, `APP_REVIEW_CONTACT_LAST_NAME`, `APP_REVIEW_CONTACT_PHONE`, and `APP_REVIEW_CONTACT_EMAIL`.
- Run `Scripts/preflight_app_store_archive.sh` and fix every failed step before archiving; it starts with `Scripts/print_release_input_status.sh --strict --scope app-store-archive`, then runs `Scripts/verify_release.sh store-ready`, private release inputs, and signing asset checks without requiring later App Review contact, App Store Connect credentials, App Privacy confirmation, TestFlight evidence, or final submission guards.
- Archive with Xcode 26 or later using `DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh`.
- Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands.
- Confirm `Scripts/archive_app_store.sh` finishes the `Validate Export` step before uploading the IPA.
- Upload the signed archive or exported IPA to App Store Connect.
- Add app name, subtitle, description, promotional text, keywords, categories, review notes, and support contact from `AppStore/metadata.md`; the reusable Fastlane copy lives under `fastlane/metadata/en-US`.
- Metadata upload preflight: after configuring App Store Connect API credentials and App Review contact fields, run `Scripts/preflight_metadata_upload.sh`; it starts with `Scripts/print_release_input_status.sh --strict --scope metadata-upload` before metadata and credential checks, without requiring later TestFlight evidence or final submission guards.
- Optional automation: run `Scripts/install_release_dependencies.sh` or `brew install fastlane`, configure App Store Connect API credentials, then run `Scripts/run_fastlane.sh ios metadata` to upload App Store metadata and screenshots without submitting for review.
- App Privacy upload preflight: verify `AppStore/app_privacy_details.json`, then run `FASTLANE_USER=... CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh`; it starts with `Scripts/print_release_input_status.sh --strict --scope app-privacy-upload` before the upload confirmation and privacy checks, without requiring later metadata, signing, TestFlight evidence, or final submission guards.
- App Privacy automation: verify `AppStore/app_privacy_details.json`, then run `FASTLANE_USER=... CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details`.
- Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.
- App Privacy App Store Connect confirmation: after Fastlane upload or manual entry, set `APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1` and run `Scripts/validate_app_privacy_connect_entry.sh`.
- Commercial configuration confirmation: after applying `AppStore/commercial-configuration.md` in App Store Connect, set `APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1` and run `Scripts/validate_commercial_configuration_connect_entry.sh`.
- TestFlight upload dependency preflight: before creating or uploading a TestFlight archive, run `Scripts/preflight_testflight_upload_dependencies.sh` to verify private release inputs, App Store Connect API credentials, and the app/version record; it starts with `Scripts/print_release_input_status.sh --strict --scope testflight-upload`.
- TestFlight upload preflight: after creating the signed export and configuring App Store Connect API credentials, run `Scripts/preflight_testflight_upload.sh`; it starts with `Scripts/print_release_input_status.sh --strict --scope testflight-upload` before IPA and upload checks, without requiring later App Review contact, App Privacy confirmation, manual evidence, or final submission guards.
- Optional TestFlight automation: configure `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH`, then run `Scripts/run_fastlane.sh ios upload_testflight` to upload the exported IPA without external distribution.
- App Store Connect state preflight: after the build processes, run `APP_STORE_BUILD_NUMBER=... Scripts/run_fastlane.sh ios app_store_connect_state` to verify the app record, version, and selected build before review submission.
- Replace any `PROCESSED_BUILD_NUMBER` placeholder in generated handoff commands with the processed App Store Connect build number before running them; the local release validators intentionally reject that placeholder.
- Commercial configuration: apply `AppStore/commercial-configuration.md` in App Store Connect before submission, then confirm it with `APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1`.
- App Review self-audit: review `AppStore/review-guideline-audit.md` and resolve every open blocker before submission.
- Manual release evidence: run `Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config` and `Scripts/verify_release.sh manual-evidence-form`, record real-device verification in `Config/manual-release-verification.env`, include physical iPad TestFlight layout and print workflow evidence, and use the built-in Test Ruler for `MANUAL_AIRPRINT_EXACT_SIZE`, `MANUAL_AIRPRINT_RULER_TARGET_INCHES`, and `MANUAL_AIRPRINT_RULER_MEASURED_INCHES`, then run `APP_STORE_BUILD_NUMBER=... Scripts/validate_manual_release_verification.sh` with the same APP_STORE_BUILD_NUMBER selected for App Review.
- App Review submission preflight: after every listing field is final and the selected build has processed, run `APP_STORE_BUILD_NUMBER=... Scripts/preflight_app_review_submission.sh`; it starts with `Scripts/print_release_input_status.sh --strict --scope app-review-submission` so final-submission private release inputs are shown as field-level action items without requiring local signing assets after upload.
- Final review submission automation: after the uploaded build has processed and every listing field is final, run `APP_STORE_BUILD_NUMBER=... CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review`; the `submit_review` lane re-runs screenshot privacy metadata validation and re-runs manual release evidence validation before contacting App Store Connect.
- Upload screenshots from `fastlane/screenshots/en-US` or through App Store Connect.
- Host a public privacy policy page and add its URL in App Store Connect.
- Enter App Privacy details as no data collected, no tracking, no third-party analytics, and no advertising SDKs.
- Complete App Privacy using `AppStore/app-privacy.md`.
- Complete age rating using `AppStore/age-rating.md`.
- Complete Accessibility Nutrition Label fields using `AppStore/accessibility-labels.md` after validating the listed device checks.
- Complete export compliance using `AppStore/export-compliance.md`; `Info.plist` declares `ITSAppUsesNonExemptEncryption` as false.
- Upload final screenshots accepted by App Store Connect for every supported device family.
- Because iPad remains supported, validate the iPad UI on a physical iPad through TestFlight, record `MANUAL_IPAD_TESTFLIGHT_*` evidence, and upload iPad screenshots.
- Run TestFlight on at least one real device before submitting for review.

## Current Apple references

- Submitting apps: https://developer.apple.com/app-store/submitting/
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
