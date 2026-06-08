# FreePrint Studio Commercial Configuration

Use this draft when filling App Store Connect Pricing and Availability for the MVP release.

## Pricing

Price: Free

Rationale: the MVP has no paid features, server cost, account system, or commerce workflow. Keeping the first release free reduces review and support complexity while validating demand for exact-size image printing.

## Availability

Availability: All App Store countries or regions

Rationale: the app is fully local, does not depend on region-specific services, does not collect data, and uses standard iOS PDF export and AirPrint workflows.

## Monetization

In-App Purchases: None

Subscriptions: None

Advertising: None

Third-party payment links: None

The app must not show paywalls, purchase prompts, ad placements, external payment links, or subscription copy unless the commercial configuration and App Store metadata are updated together.

## Distribution

Release type: Manual release after App Review approval

Phased release: Off for the MVP unless a later rollout plan is created.

TestFlight external testing: Not required for the MVP submission, but TestFlight install and print workflow must still be verified on a real device before review submission.

## Manual App Store Connect Fields

Manual App Store Connect fields are not automated by the local release scripts.

Set these fields manually in App Store Connect before submitting for review:

- Pricing: Free
- Availability: All App Store countries or regions
- In-App Purchases: None
- Subscriptions: None
- Advertising: None
- Release option: Manually release this version after App Review approval
- Phased release: Off

After changing any of these values, rerun:

```sh
Scripts/check_app_store_readiness.sh
Scripts/verify_release.sh submission-packet
```
