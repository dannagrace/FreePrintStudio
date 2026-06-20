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

Run the full local store-ready gate before handing the project to App Store Connect. This runs the default release gate plus simulator workflow, real Photos import, review UI validation, accessibility screenshots, print sheet validation, strict public privacy/support page validation, and submission packet generation and validation:

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

Validate that the real Photos picker can import an image from the simulator photo library, enable the export/print workflow, and keep About screen review/support information reachable:

```sh
Scripts/verify_release.sh photo-import
# Or directly:
Scripts/validate_photo_import.sh
```

Validate that the App Review-facing About screen exposes the privacy policy, support URL, and app version without running the full Photos picker workflow:

```sh
Scripts/verify_release.sh review-ui
# Or directly:
Scripts/validate_review_ui.sh
```

Install generated private release input templates, then validate that private release settings do not still contain copied placeholder values:

```sh
Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config
Scripts/validate_private_release_artifact_ignores.sh
Scripts/validate_release_env.sh
```

Use `AppStore/release-inputs-worksheet.md` while collecting private Apple Developer signing values, App Review contact details, App Store Connect credentials, and manual real-device evidence. Keep filled values only in the git-ignored local files installed by `Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config`.
`Scripts/validate_private_release_artifact_ignores.sh` verifies private release inputs, backups, credentials, signing assets, provisioning profiles, IPA files, and archives are ignored, untracked, and restricted to owner-only permissions.

Print a redacted summary of private release input progress without exposing real values:

```sh
Scripts/print_release_input_status.sh
Scripts/print_release_input_status.sh --strict
Scripts/print_release_input_status.sh --strict --owner qa-release-owner
```

Use the strict form before release handoff so missing final submission guards fail locally. Use `--owner release-owner`, `--owner qa-release-owner`, `--owner apple-developer-account-holder`, or `--owner app-store-connect-account-holder` when a handoff owner needs a redacted checklist limited to their assigned release inputs.

Generate a redacted App Review contact readiness report before and after setting reviewer contact fields:

```sh
Scripts/verify_release.sh contact-report
```

Generate a redacted manual release readiness report before and after recording real iPhone, AirPrint, iPad, and TestFlight evidence:

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

Generate a redacted App Store Connect state report after selecting a processed TestFlight build, or before handoff to show which selected-build check is still blocked:

```sh
Scripts/verify_release.sh asc-state-report
```

Generate a redacted App Review submission readiness report before the final preflight:

```sh
Scripts/verify_release.sh review-report
```

Generate a public privacy/support page readiness report before release handoff:

```sh
Scripts/verify_release.sh public-pages-report
```

Strictly validate that the deployed privacy policy and support pages are reachable before metadata upload or review submission:

```sh
Scripts/verify_release.sh public-pages
# Or directly:
Scripts/validate_public_pages.sh
```

Validate that installed signing assets match the release bundle, Apple team, and App Store Connect export method:

```sh
Scripts/check_code_signing_assets.sh
```

Run the App Store archive preflight after private release values and signing assets are configured, before creating the signed archive. This preflight starts with `Scripts/print_release_input_status.sh --strict --scope app-store-archive` so archive-required release inputs are shown as field-level action items, then runs `Scripts/verify_release.sh store-ready`, the private release environment, and code signing asset checks without requiring later App Review contact, App Store Connect credentials, App Privacy confirmation, TestFlight evidence, or final submission guards:

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

GitHub Actions runs the release gates on pushes to `main` and pull requests, including `Scripts/verify_release.sh review-ui` for App Review-facing UI information.

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

Validate the reviewed and Fastlane screenshot copies before upload, including size, sync, blank-content, alpha, and privacy metadata checks:

```sh
Scripts/verify_release.sh screenshots
# Or only the metadata privacy check:
Scripts/validate_screenshot_privacy.sh
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

Record and validate manual real-device, AirPrint, iPad, and TestFlight evidence before final App Review submission:

```sh
Scripts/install_private_release_input_templates.sh --source-dir build/private-release-input-templates --target-dir Config
Scripts/verify_release.sh manual-evidence-form
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh
```

`PROCESSED_BUILD_NUMBER` is a placeholder; replace it with the processed build number selected in App Store Connect before running these commands. The release environment validator intentionally rejects this placeholder so it cannot be submitted accidentally.

When validating the final App Review build, run the manual evidence check with the same APP_STORE_BUILD_NUMBER that will be submitted so the tested TestFlight build cannot drift from the selected App Store build. Because the app targets iPhone and iPad, also record physical iPad TestFlight install, layout, and print workflow evidence in `MANUAL_IPAD_TESTFLIGHT_*`.

Prepare a local App Store submission packet with metadata, questionnaire drafts, screenshots, PDF export validation evidence, the blank manual release evidence form, redacted App Review contact, manual release, signing, App Store Connect readiness, App Store Connect state, App Review submission readiness, public pages readiness reports, per-owner `owner-action-briefs/`, blank `private-release-input-templates/`, checksums, readiness audit output, and next commands:

```sh
Scripts/verify_release.sh submission-packet
# Or directly:
Scripts/prepare_app_store_submission_packet.sh
```

Validate the generated submission packet before handoff or artifact upload:

```sh
Scripts/verify_release.sh submission-packet-check
# Or directly:
Scripts/validate_app_store_submission_packet.sh
```

GitHub Actions uploads the generated App Store submission packet from successful Release Gates runs as the `freeprintstudio-app-store-submission-packet` artifact.
Download and validate the latest successful CI-generated packet before release handoff:

```sh
Scripts/download_latest_submission_packet.sh
```

The helper uses the GitHub artifact API download path by default because `gh run download` can stall during handoff. Tune `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_ATTEMPTS` and `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_TIMEOUT_SECONDS` if GitHub artifact downloads are slow or hang; each download attempt is bounded before retrying. To explicitly select the default API path, run `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_METHOD=api Scripts/download_latest_submission_packet.sh`. To try `gh run download` first and keep the GitHub artifact API fallback, run `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_METHOD=auto Scripts/download_latest_submission_packet.sh`; to force only `gh run download`, use `FREEPRINTSTUDIO_ARTIFACT_DOWNLOAD_METHOD=gh`.

Run the full release handoff preflight before giving the packet to the App Store Connect account owner. It requires a clean local worktree, downloads the latest successful CI packet, verifies the packet provenance matches local `HEAD`, then runs the readiness audit:

```sh
Scripts/preflight_release_handoff.sh
```

The handoff preflight writes `build/release-handoff-summary.tsv` with the local commit, CI packet run URL, packet commit, CI readiness log path, CI readiness blocker count, CI readiness warning count, CI `external-readiness-actions.tsv` path, external action blocker count, external action warning count, local readiness status, local blocker count, local warning count, CI/local readiness delta, local readiness log path, `build/release-handoff-input-status.txt`, the release input missing check count, the release input missing field/action count, release phase plan total action count, release phase plan total blocker count, release phase plan total warning count, final submission guard action count, `build/release-input-todo.md`, `build/release-phase-plan.md`, `build/release-owner-actions/`, `build/release-owner-input-status/`, and `build/private-release-input-templates/`. It also writes `build/release-handoff-brief.md` as the human-readable release owner brief with readiness counts, redacted release input status, release phase plan status counts, CI/local readiness delta, external action categories, handoff brief Owner Summary, Owner-Scoped Status Commands, Owner-Scoped Status Reports from `build/release-owner-input-status/`, Total Handoff Owner Summary that adds final submission guard blockers to Release owner, owner-scoped external action details, primary action files, and next commands. `build/release-input-todo.md` is generated from the CI external readiness actions, records both external action counts and total handoff counts including final submission guard actions, includes an Owner Summary for assigning remaining actions, then groups fillable `Config/release.env` and `Config/manual-release-verification.env` fields separately from Keychain, Xcode, and App Store Connect actions. `build/release-phase-plan.md` is generated from the CI external readiness actions, adds final submission guard actions, and orders the remaining work by release phase with validation gates. `build/release-owner-actions/` mirrors the packet `owner-action-briefs/` directory with one focused file per action owner, adds final submission guard actions to the Release owner file, and uses owner-scoped `Scripts/print_release_input_status.sh --strict --owner ...` commands so each owner can validate their own release inputs without being blocked by another owner's pending items. `build/release-owner-input-status/` contains an `index.tsv` and one redacted status report per handoff owner, so each owner can review current missing inputs before re-running their owner-scoped command. `build/private-release-input-templates/` mirrors the packet `private-release-input-templates/` directory with blank `release.env` and `manual-release-verification.env` starters generated from the current external actions. Run `Scripts/install_private_release_input_templates.sh` after handoff preflight to install those starters into git-ignored `Config/release.env` and `Config/manual-release-verification.env`; existing private values are backed up and preserved while missing keys are appended.
Run `Scripts/validate_release_handoff_summary.sh build/release-handoff-summary.tsv` to re-check that the handoff summary counts still match the referenced CI readiness log, local readiness log, release input status report, and external action manifest. Run `Scripts/validate_release_handoff_brief.sh build/CISubmissionPacket/external-readiness-actions.tsv build/release-handoff-brief.md build/CISubmissionPacket/readiness.txt build/release-handoff-readiness.txt` to re-check that the human-readable brief still matches the external action manifest, release input status section, and the CI/local readiness delta details.

Release metadata, screenshot assets, and the remaining App Store Connect checklist live under `AppStore/`.

Use `AppStore/commercial-configuration.md` for App Store Connect pricing, availability, monetization, and manual release settings. The MVP configuration is free, all App Store countries or regions, no in-app purchases, no subscriptions, no advertising, and manual release after approval.
After applying those settings in App Store Connect, confirm them locally with `APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_commercial_configuration_connect_entry.sh`.

Use `AppStore/review-guideline-audit.md` as the App Review self-audit. It maps Apple review, privacy, commerce, metadata, SDK, and final-submission expectations to local evidence and remaining blockers.

Prepare a signed App Store archive after configuring an Apple Developer Team in Xcode:

```sh
Scripts/preflight_app_store_archive.sh
DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh
```

Replace YOURTEAMID with the Apple Developer Team ID before running signing or archive commands.

The archive script runs the local release gate first, then creates `build/FreePrintStudio.xcarchive` and exports an App Store Connect IPA under `build/AppStoreExport/`.
After export it runs `Scripts/validate_app_store_export.sh`, which checks the archive metadata, signed app bundle, dSYM, IPA `Payload`, bundle ID, app version, and build number before upload.
`Config/release.env.example` lists the signing and App Store Connect variables used by the release scripts. Its placeholder assignments are commented out so a copied file cannot accidentally satisfy readiness checks. Keep the filled file and any `AuthKey_*.p8` private key outside git.
Release scripts automatically load `Config/release.env` when it exists; set `RELEASE_ENV_PATH` to load a different private env file.

App Store Connect metadata is mirrored under `fastlane/`. Install Fastlane through the project Bundler path or Homebrew, then upload metadata and screenshots without submitting for review:

```sh
Scripts/install_release_dependencies.sh
# Or: brew install fastlane
Scripts/preflight_metadata_upload.sh
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios metadata
```

The metadata preflight starts with `Scripts/print_release_input_status.sh --strict --scope metadata-upload`, so metadata-required release inputs are shown as field-level action items before metadata, screenshot, public page, App Review contact, and App Store Connect credential checks without blocking on later TestFlight evidence or final submission guards.
The Fastlane metadata, App Privacy Details, and final review-submission lanes run the local App Store questionnaire validation before uploading or submitting.
The metadata lane uses App Store Connect API credentials so it fails before `deliver` can fall back to an interactive Apple ID session.

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
FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh
FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details
```

Replace apple-id@example.com with the App Store Connect Apple ID before running Fastlane Apple ID commands.

The App Privacy upload preflight starts with `Scripts/print_release_input_status.sh --strict --scope app-privacy-upload`, so privacy-upload inputs are checked without blocking on later metadata, signing, TestFlight evidence, or final submission guards.
Set `APP_PRIVACY_SKIP_PUBLISH=1` to upload the App Privacy Details without publishing them.
After Fastlane upload or manual App Store Connect entry, confirm the live App Privacy Details match `AppStore/app_privacy_details.json`:

```sh
APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh
```

After applying Pricing, Availability, monetization, release option, and phased release from `AppStore/commercial-configuration.md`, confirm the live App Store Connect commercial settings:

```sh
APP_STORE_COMMERCIAL_CONFIG_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_commercial_configuration_connect_entry.sh
```

Fastlane can also call the local gates and create the signed archive:

```sh
Scripts/run_fastlane.sh ios verify
Scripts/run_fastlane.sh ios readiness
Scripts/run_fastlane.sh ios archive
```

After the archive exports an IPA and an App Store Connect API key is configured, upload the build to TestFlight without external distribution:

```sh
Scripts/preflight_testflight_upload_dependencies.sh
Scripts/preflight_testflight_upload.sh
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight
```

Both TestFlight preflights start with `Scripts/print_release_input_status.sh --strict --scope testflight-upload`, so TestFlight-upload release inputs are listed before archive fallback or IPA upload checks continue without blocking on later App Review contact, App Privacy confirmation, manual device evidence, or final submission guards.
If the exported IPA lives outside the default `build/AppStoreExport/` folder, pass `IPA_PATH=/absolute/path/to/FreePrintStudio.ipa`.

After the build has processed in App Store Connect, verify the app record, version, and selected TestFlight build:

```sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state
```

Before submitting for App Review, run the final preflight without triggering submission:

```sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh
```

The preflight starts with `Scripts/print_release_input_status.sh --strict --scope app-review-submission`, so it prints final-submission field-level missing release inputs before the individual submission gates run without requiring local signing assets after the uploaded build has processed. It requires commercial configuration confirmation, `MANUAL_TESTFLIGHT_BUILD_NUMBER` in `Config/manual-release-verification.env` to match the same APP_STORE_BUILD_NUMBER, and physical iPad TestFlight evidence for the supported iPad build.

After the uploaded build is processed in App Store Connect and the store listing, privacy details, age rating, screenshots, and review contact details are final, submit the selected build for App Review:

```sh
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review
```

Replace `PROCESSED_BUILD_NUMBER` before running the App Store Connect state, App Review preflight, or final submission commands; leaving it in place is expected to fail locally.

`submit_review` uses manual release (`automatic_release: false`) and submits only the explicit `APP_STORE_BUILD_NUMBER`. The `submit_review` lane re-runs screenshot privacy metadata validation and re-runs manual release evidence validation before calling App Store Connect, so the screenshots and recorded TestFlight evidence must still match the selected build at final submission time.

App Store Connect questionnaire drafts are stored in:

- `AppStore/app-privacy.md`
- `AppStore/age-rating.md`
- `AppStore/accessibility-labels.md`
- `AppStore/export-compliance.md`

The privacy and support pages are in `docs/`. For the metadata URLs in `AppStore/metadata.md` to be public, set GitHub Pages source to GitHub Actions and use `.github/workflows/pages.yml` to publish the `docs` directory. Verify the repository setting with:

```sh
Scripts/check_github_pages_source.sh
```
