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

Validate App Store text metadata limits before uploading with Fastlane:

```sh
Scripts/validate_app_store_metadata.sh
```

Validate App Privacy Details before uploading them to App Store Connect:

```sh
Scripts/validate_app_privacy_details.sh
```

Validate that the app renderer exports a PDF with the expected paper MediaBox:

```sh
Scripts/validate_pdf_export.sh
```

Validate that private release settings do not still contain copied placeholder values:

```sh
Scripts/validate_release_env.sh
```

GitHub Actions runs `Scripts/verify_release.sh` on pushes to `main` and pull requests.

Audit App Store readiness, including public URLs, screenshots, Xcode, and signing state:

```sh
Scripts/check_app_store_readiness.sh
```

This audit exits nonzero until an Apple Developer Team ID, signing identity, and provisioning profile are available.

Generate the draft App Store screenshots. The default iPhone command prefers a 6.9-inch simulator such as iPhone 17 Pro Max.

```sh
Scripts/capture_app_store_screenshots.sh
SIMULATOR_UDID=2E8A23AC-6267-44FB-94A7-49221C184C79 SCREENSHOT_PATH="$PWD/AppStore/Screenshots/ipad-main.jpg" Scripts/capture_app_store_screenshots.sh
```

Generate the Fit, Fill, and Stretch iPhone screenshot set and sync it to Fastlane:

```sh
Scripts/capture_app_store_screenshot_set.sh
```

The same script can reproduce accessibility appearance checks without permanently changing the simulator:

```sh
FREEPRINTSTUDIO_APPEARANCE=dark SCREENSHOT_PATH=/tmp/freeprintstudio-dark.jpg Scripts/capture_app_store_screenshots.sh
FREEPRINTSTUDIO_CONTENT_SIZE=accessibility-extra-extra-large SCREENSHOT_PATH=/tmp/freeprintstudio-large-text.jpg Scripts/capture_app_store_screenshots.sh
```

Release metadata, screenshot assets, and the remaining App Store Connect checklist live under `AppStore/`.

Prepare a signed App Store archive after configuring an Apple Developer Team in Xcode:

```sh
DEVELOPMENT_TEAM_ID=ABCDE12345 ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh
```

The archive script runs the local release gate first, then creates `build/FreePrintStudio.xcarchive` and exports an App Store Connect IPA under `build/AppStoreExport/`.
`Config/release.env.example` lists the signing and App Store Connect variables used by the release scripts. Its placeholder assignments are commented out so a copied file cannot accidentally satisfy readiness checks. Keep the filled file and any `AuthKey_*.p8` private key outside git.
Release scripts automatically load `Config/release.env` when it exists; set `RELEASE_ENV_PATH` to load a different private env file.

App Store Connect metadata is mirrored under `fastlane/`. Install Fastlane through the project Bundler path or Homebrew, then upload metadata and screenshots without submitting for review:

```sh
Scripts/install_release_dependencies.sh
# Or: brew install fastlane
Scripts/run_fastlane.sh ios metadata
```

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
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios upload_testflight
```

If the exported IPA lives outside the default `build/AppStoreExport/` folder, pass `IPA_PATH=/absolute/path/to/FreePrintStudio.ipa`.

After the build has processed in App Store Connect, verify the app record, version, and selected TestFlight build:

```sh
APP_STORE_BUILD_NUMBER=1 Scripts/run_fastlane.sh ios app_store_connect_state
```

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
