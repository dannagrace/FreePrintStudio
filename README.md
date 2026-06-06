# FreePrint Studio

FreePrint Studio is a small iOS app for printing an image at an exact physical size.

## MVP

- Choose a paper preset: Letter, A4, 4 x 6, or 5 x 7.
- Pick an image from Photos.
- Enter the desired printed width and height in inches, centimeters, or millimeters.
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
