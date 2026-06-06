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

Generate the draft App Store screenshots. The default iPhone command prefers a 6.9-inch simulator such as iPhone 17 Pro Max.

```sh
Scripts/capture_app_store_screenshots.sh
SIMULATOR_UDID=2E8A23AC-6267-44FB-94A7-49221C184C79 SCREENSHOT_PATH="$PWD/AppStore/Screenshots/ipad-main.jpg" Scripts/capture_app_store_screenshots.sh
```

Release metadata, screenshot assets, and the remaining App Store Connect checklist live under `AppStore/`.

Prepare a signed App Store archive after configuring an Apple Developer Team in Xcode:

```sh
DEVELOPMENT_TEAM_ID=ABCDE12345 ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh
```

The archive script runs the local release gate first, then creates `build/FreePrintStudio.xcarchive` and exports an App Store Connect IPA under `build/AppStoreExport/`.

App Store Connect metadata is mirrored under `fastlane/`. After installing and authenticating Fastlane, upload metadata and screenshots without submitting for review:

```sh
fastlane deliver --skip_binary_upload true --submit_for_review false
```

The privacy and support pages are in `docs/`. For the metadata URLs in `AppStore/metadata.md` to be public, enable GitHub Pages for this repository from the `docs` folder.
