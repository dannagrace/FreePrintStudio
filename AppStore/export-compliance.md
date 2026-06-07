# FreePrint Studio Export Compliance Draft

Use this file when completing Export Compliance in App Store Connect.

## Declaration

- Uses non-exempt encryption: No
- Info.plist key: `ITSAppUsesNonExemptEncryption`
- Info.plist value: `false`

## Rationale

FreePrint Studio is a local image sizing, PDF export, and AirPrint workflow. The app does not create accounts, connect to a backend service, upload selected images, implement custom cryptography, provide VPN/security features, or expose encrypted communication features.

The app links only to public privacy and support pages from the About screen. Those links are handled by system components and are not app-provided encryption functionality.

## App Store Connect Answer

When asked whether the app uses encryption, select the answer that corresponds to no use of non-exempt encryption. Re-evaluate this file before submission if the app later adds cloud sync, accounts, network upload, analytics SDKs, payment flows, messaging, VPN/security features, or custom encryption.
