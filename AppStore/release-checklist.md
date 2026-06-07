# FreePrint Studio Release Checklist

## Local gates

- Run `Scripts/verify_release.sh`.
- Run `Scripts/validate_app_store_metadata.sh`.
- Run `Scripts/validate_app_privacy_details.sh`.
- Run `Scripts/validate_release_env.sh` after creating or editing `Config/release.env`.
- Run `Scripts/check_code_signing_assets.sh` after installing certificates or provisioning profiles.
- Run `Scripts/validate_app_review_contact.sh` after setting App Review contact values.
- Run `Scripts/validate_pdf_export.sh` after print/PDF rendering changes; it validates Fit, Fill, and Stretch PDF output.
- Run `Scripts/check_app_store_readiness.sh`; fix every `BLOCKED` item before archiving.
- Run `Scripts/capture_app_store_screenshots.sh` after UI changes and inspect `AppStore/Screenshots/iphone-main.jpg`.
- Run `Scripts/capture_app_store_screenshot_set.sh` after fit mode UI changes and inspect `iphone-fit.jpg`, `iphone-fill.jpg`, and `iphone-stretch.jpg`.
- Run the iPad screenshot command from `README.md` and inspect `AppStore/Screenshots/ipad-main.jpg`.
- Run the dark interface and Larger Text screenshot commands from `README.md` after visible UI changes.
- Confirm the app opens, imports a photo, changes size units, exports PDF, and opens the print sheet on a simulator.
- Confirm the same flow on a real iPhone.
- Confirm AirPrint output on a real printer or a production-equivalent print workflow.
- Enable GitHub Pages from the repository `docs` folder and verify the privacy and support URLs in `AppStore/metadata.md`.

## App Store Connect

- Create the App Store Connect app record for bundle ID `com.dannagrace.FreePrintStudio`.
- Configure signing with an Apple Developer Program team in Xcode.
- Fill local release environment values from `Config/release.env.example`; release scripts automatically load `Config/release.env` when it exists. Keep `Config/release.env` and any `AuthKey_*.p8` private key out of git.
- Set private App Review contact values before metadata upload or submission: `APP_REVIEW_CONTACT_FIRST_NAME`, `APP_REVIEW_CONTACT_LAST_NAME`, `APP_REVIEW_CONTACT_PHONE`, and `APP_REVIEW_CONTACT_EMAIL`.
- Archive with Xcode 26 or later using `DEVELOPMENT_TEAM_ID=... ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh`.
- Upload the signed archive or exported IPA to App Store Connect.
- Add app name, subtitle, description, promotional text, keywords, categories, review notes, and support contact from `AppStore/metadata.md`; the reusable Fastlane copy lives under `fastlane/metadata/en-US`.
- Optional automation: run `Scripts/install_release_dependencies.sh` or `brew install fastlane`, then `Scripts/run_fastlane.sh ios metadata` to upload App Store metadata and screenshots without submitting for review.
- App Privacy automation: verify `AppStore/app_privacy_details.json`, then run `FASTLANE_USER=... CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details`.
- Optional TestFlight automation: configure `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH`, then run `Scripts/run_fastlane.sh ios upload_testflight` to upload the exported IPA without external distribution.
- App Store Connect state preflight: after the build processes, run `APP_STORE_BUILD_NUMBER=... Scripts/run_fastlane.sh ios app_store_connect_state` to verify the app record, version, and selected build before review submission.
- Final review submission automation: after the uploaded build has processed and every listing field is final, run `APP_STORE_BUILD_NUMBER=... CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review`.
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
