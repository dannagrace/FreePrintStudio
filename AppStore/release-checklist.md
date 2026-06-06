# FreePrint Studio Release Checklist

## Local gates

- Run `Scripts/verify_release.sh`.
- Run `Scripts/check_app_store_readiness.sh`; fix every `BLOCKED` item before archiving.
- Run `Scripts/capture_app_store_screenshots.sh` after UI changes and inspect `AppStore/Screenshots/iphone-main.jpg`.
- Run the iPad screenshot command from `README.md` and inspect `AppStore/Screenshots/ipad-main.jpg`.
- Confirm the app opens, imports a photo, changes size units, exports PDF, and opens the print sheet on a simulator.
- Confirm the same flow on a real iPhone.
- Confirm AirPrint output on a real printer or a production-equivalent print workflow.
- Enable GitHub Pages from the repository `docs` folder and verify the privacy and support URLs in `AppStore/metadata.md`.

## App Store Connect

- Create the App Store Connect app record for bundle ID `com.dannagrace.FreePrintStudio`.
- Configure signing with an Apple Developer Program team in Xcode.
- Archive with Xcode 26 or later using `DEVELOPMENT_TEAM_ID=... ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh`.
- Upload the signed archive or exported IPA to App Store Connect.
- Add app name, subtitle, description, promotional text, keywords, categories, review notes, and support contact from `AppStore/metadata.md`; the reusable Fastlane copy lives under `fastlane/metadata/en-US`.
- Optional automation: run `bundle install` and `bundle exec fastlane ios metadata` to upload App Store metadata and screenshots without submitting for review.
- Upload screenshots from `fastlane/screenshots/en-US` or through App Store Connect.
- Host a public privacy policy page and add its URL in App Store Connect.
- Enter App Privacy details as no data collected, no tracking, no third-party analytics, and no advertising SDKs.
- Complete App Privacy using `AppStore/app-privacy.md`.
- Complete age rating using `AppStore/age-rating.md`.
- Complete Accessibility Nutrition Label fields using `AppStore/accessibility-labels.md` after validating the listed device checks.
- Upload final screenshots accepted by App Store Connect for every supported device family.
- If iPad remains supported, validate the iPad UI on a real device or TestFlight and upload iPad screenshots.
- Run TestFlight on at least one real device before submitting for review.

## Current Apple references

- Submitting apps: https://developer.apple.com/app-store/submitting/
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
