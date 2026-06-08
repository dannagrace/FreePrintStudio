# FreePrint Studio App Review Guideline Self-Audit

Source snapshot date: 2026-06-08

Official Apple references:

- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Submitting apps to the App Store: https://developer.apple.com/app-store/submitting/

This self-audit maps FreePrint Studio's release evidence to the App Store review areas most relevant to the MVP. It does not replace App Review, App Store Connect account checks, or real-device testing. Every open blocker must still be resolved before final submission.

## Current Release Posture

- Local automated release gate: `Scripts/verify_release.sh store-ready`
- Local readiness audit: `Scripts/check_app_store_readiness.sh`
- Submission packet: `Scripts/verify_release.sh submission-packet`
- Private input status: `Scripts/print_release_input_status.sh`
- Remaining blocker class: private Apple account, signing, App Store Connect credentials, and real-device evidence.

## 2.1 App Completeness

Expectation: the submitted build, metadata, screenshots, support links, and review information should be complete and testable.

Evidence already in the repository:

- `Scripts/verify_release.sh store-ready` validates the default release gate, simulator workflow, Photos import, accessibility screenshots, print sheet workflow, and submission packet generation.
- `Scripts/check_app_store_readiness.sh` audits bundle identity, screenshots, public privacy and support URLs, metadata, privacy declarations, tooling, signing, and App Store Connect state.
- `AppStore/metadata.md` and `fastlane/metadata/en-US/*` contain the listing copy.
- `fastlane/metadata/review_information/notes.txt` explains that the app does not require an account or network service and gives reviewer test steps.
- `docs/privacy-policy.html` and `docs/support.html` are public GitHub Pages sources.

Open release blockers:

- App Review contact values must be filled in `Config/release.env`.
- Real-device evidence must be recorded in `Config/manual-release-verification.env`.
- A processed App Store Connect build must be selected with `APP_STORE_BUILD_NUMBER`.

## 5.1 Privacy

Expectation: privacy disclosures, permission reasons, tracking status, and data collection claims must match the app's behavior.

Evidence already in the repository:

- `FreePrintStudio/Resources/PrivacyInfo.xcprivacy` declares the app privacy manifest.
- `AppStore/app-privacy.md` documents no data collection and no tracking.
- `AppStore/app_privacy_details.json` prepares the App Privacy Details payload.
- `Scripts/validate_privacy_surface.sh` checks that the local privacy policy, app privacy draft, privacy manifest, and support surface remain consistent.
- `Scripts/validate_app_privacy_details.sh` validates the App Privacy Details JSON before upload.
- `FreePrintStudio/Resources/Info.plist` includes `NSPhotoLibraryUsageDescription` explaining local selected-image use.

Open release blockers:

- `FASTLANE_USER` is needed only if App Privacy Details are uploaded through Fastlane's Apple ID flow. Manual entry in App Store Connect is also acceptable if the same values are used.

## 3.1 Payments

Expectation: apps using digital goods, subscriptions, payments, or external purchase flows must match App Store commerce rules and metadata.

MVP decision:

- Price: Free
- In-App Purchases: None
- Subscriptions: None
- Advertising: None
- Third-party payment links: None

Evidence already in the repository:

- `AppStore/commercial-configuration.md` defines the MVP commercial setup.
- `AppStore/metadata.md` does not describe paid features, subscriptions, advertising, or external purchase flows.
- The app code does not include a purchase, subscription, ad, account, or payment workflow.

Open release blockers:

- Apply the manual App Store Connect fields from `AppStore/commercial-configuration.md` before submission.

## 4.2 Minimum Functionality

Expectation: the app should provide a complete, useful experience and not be a placeholder, wrapper, or unfinished demo.

Evidence already in the repository:

- The app supports selecting an image, choosing paper size and orientation, entering exact print dimensions, choosing Fit/Fill/Stretch, previewing on a paper canvas, exporting a PDF, and opening the system print sheet.
- `Scripts/validate_pdf_export.sh` verifies exact PDF layout behavior for inches, centimeters, millimeters, portrait, landscape, Fit, Fill, and Stretch.
- `Scripts/validate_photo_import.sh` verifies the real Photos picker path in the simulator.
- `Scripts/validate_print_sheet.sh` verifies the system print sheet can be presented.
- `Scripts/validate_simulator_workflow.sh` exercises the main workflow with a generated image and PDF output.

Open release blockers:

- Confirm the same workflow on a real iPhone.
- Confirm AirPrint or production-equivalent exact-size output.
- Confirm TestFlight install and print workflow on the selected App Store build.

## Metadata And Store Listing

Expectation: store listing text, URLs, screenshots, categories, and release notes should be accurate and within App Store limits.

Evidence already in the repository:

- `Scripts/validate_app_store_metadata.sh` validates Fastlane metadata limits and consistency with `AppStore/metadata.md`.
- `Scripts/validate_screenshot_sync.sh` validates screenshots and Fastlane screenshot sync.
- `AppStore/Screenshots/*` and `fastlane/screenshots/en-US/*` contain accepted iPhone and iPad image dimensions.
- `fastlane/Deliverfile` sets the bundle identifier, app version, categories, metadata path, screenshots path, and non-submitting default upload behavior.

Open release blockers:

- App Store Connect app record and selected build state require private account credentials.

## SDK And Submission Readiness

Expectation: App Store submissions should be built with a current supported Apple SDK and should pass release build validation.

Evidence already in the repository:

- Current local tooling reports Xcode 26.5 in `Scripts/check_app_store_readiness.sh`.
- `Scripts/verify_release.sh store-ready` performs a Release iOS build with `CODE_SIGNING_ALLOWED=NO`.
- `.github/workflows/release.yml` runs Release Gates on GitHub with static checks, core checks, plist lint, PDF export validation, Release iOS build, and screenshot asset checks.

Open release blockers:

- A signed archive still requires `DEVELOPMENT_TEAM_ID`, an `Apple Distribution` identity, and an App Store Connect provisioning profile.

## Final Submission Evidence Required

Before submitting for review, all of the following must be true:

- `Scripts/print_release_input_status.sh --strict` exits successfully.
- `Scripts/check_app_store_readiness.sh` has zero `BLOCKED` lines.
- `Scripts/preflight_app_store_archive.sh` passes.
- `DEVELOPMENT_TEAM_ID=... ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh` creates and validates the signed archive and exported IPA.
- `Scripts/preflight_testflight_upload.sh` passes.
- The selected build is uploaded, processed, and confirmed through `APP_STORE_BUILD_NUMBER=... Scripts/run_fastlane.sh ios app_store_connect_state`.
- `APP_STORE_BUILD_NUMBER=... Scripts/validate_manual_release_verification.sh` passes with evidence from the same build.
- `APP_STORE_BUILD_NUMBER=... Scripts/preflight_app_review_submission.sh` passes.
- The commercial settings from `AppStore/commercial-configuration.md` are applied in App Store Connect.
- Final submission uses `APP_STORE_BUILD_NUMBER=... CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review`.
