# FreePrint Studio Accessibility Nutrition Label Draft

Use this file when completing App Accessibility in App Store Connect.

## Devices

- iPhone: Indicate support
- iPad: Indicate support

## Supported Features

- VoiceOver: Supported
- Larger Text: Supported
- Dark Interface: Supported
- Sufficient Contrast: Supported
- Differentiate Without Color Alone: Supported
- Reduced Motion: Supported

## Not Indicated

- Captions: Not applicable; the app has no video or spoken media content.
- Audio Descriptions: Not applicable; the app has no video content.

## Validation Notes

- Main controls use native SwiftUI buttons, pickers, text fields, links, and system sheets.
- The About button has an explicit accessibility label.
- The app supports system dark mode through native semantic colors.
- The primary workflow does not require color alone to identify actions.
- No custom animation is required to complete the workflow.

## Device Testing Required Before Publishing Labels

- Verify VoiceOver can reach Choose Image, Center, paper selection, orientation selection, unit selection, fit mode selection, width and height fields, Export PDF, Print, About, Privacy Policy, and Support.
- Verify Larger Text on iPhone and iPad does not make controls unusable.
- Verify exported PDF and AirPrint workflows on a real device.
