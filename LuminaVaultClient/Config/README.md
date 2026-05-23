# LuminaVaultClient Configuration

This directory contains the client-side build configuration contract for OAuth, RevenueCat, analytics, Sentry, legal URLs, and hosted backend selection.

## Files

| File | Committed? | Purpose |
| --- | --- | --- |
| `Config.Debug.xcconfig.sample` | yes | Debug/local template |
| `Config.Beta.xcconfig.sample` | yes | TestFlight template |
| `Config.Release.xcconfig.sample` | yes | App Store template |
| `Config.Debug.xcconfig` | no | Real Debug values |
| `Config.Beta.xcconfig` | no | Real Beta values |
| `Config.Release.xcconfig` | no | Real Release values |
| `GoogleAuth.xcconfig.sample` | yes | Legacy Google-only template |
| `Info.plist` | yes | File-based plist with build-setting substitutions |

Real `.xcconfig` files are gitignored. Do not commit secrets, signing material, private keys, or provisioning profiles.

## One-time local setup

```sh
cp LuminaVaultClient/Config/Config.Debug.xcconfig.sample \
   LuminaVaultClient/Config/Config.Debug.xcconfig
cp LuminaVaultClient/Config/Config.Beta.xcconfig.sample \
   LuminaVaultClient/Config/Config.Beta.xcconfig
cp LuminaVaultClient/Config/Config.Release.xcconfig.sample \
   LuminaVaultClient/Config/Config.Release.xcconfig
```

Fill the real values from Apple Developer, Google Cloud, X Developer Portal, RevenueCat, PostHog, and Sentry.

## Xcode wiring

For each project configuration, set the matching config file:

| Xcode configuration | Config file |
| --- | --- |
| Debug | `LuminaVaultClient/Config/Config.Debug.xcconfig` |
| Beta | `LuminaVaultClient/Config/Config.Beta.xcconfig` |
| Release | `LuminaVaultClient/Config/Config.Release.xcconfig` |

Then select the `LuminaVaultClient` app target and set:

- `Info.plist File`: `LuminaVaultClient/Config/Info.plist`
- `Generate Info.plist File`: `No`

The file-based plist is required for `CFBundleURLTypes`, which Google Sign-In needs for OAuth callbacks.

## Required values

| Key | Used by | Notes |
| --- | --- | --- |
| `API_BASE_URL` | `Config.hostedAPIBaseURL` | Hosted API URL, normally `https://api.luminavault.com` |
| `APPLE_SERVICE_ID` | `Config.appleServiceID` | Must match server `OAUTH_APPLE_CLIENTID` audience |
| `GID_CLIENT_ID` | Google Sign-In | Must match server `OAUTH_GOOGLE_CLIENTID` |
| `REVERSED_CLIENT_ID` | Info.plist URL scheme | `com.googleusercontent.apps.<id>` |
| `X_CLIENT_ID` | X sign-in | Must match server `OAUTH_X_CLIENTID` |
| `X_REDIRECT_URI` | X sign-in callback | Must match X Developer Portal exactly |
| `LV_RC_API_KEY` | RevenueCat SDK | Public iOS SDK key |
| `POSTHOG_PROJECT_TOKEN` | PostHog SDK | Public client token |
| `POSTHOG_HOST` | PostHog SDK | Usually `https://us.i.posthog.com` |
| `SENTRY_DSN` | Sentry SDK | Public client DSN |
| `SENTRY_ENVIRONMENT` | Sentry SDK | `debug`, `beta`, or `production` |
| `LV_TERMS_URL` | Settings/Billing UI | App Review legal link |
| `LV_PRIVACY_URL` | Settings/Billing UI | App Review legal link |

## Cross-repo invariants

- `GID_CLIENT_ID` must equal `LuminaVaultServer` `OAUTH_GOOGLE_CLIENTID`.
- `X_CLIENT_ID` must equal `LuminaVaultServer` `OAUTH_X_CLIENTID`.
- `APPLE_SERVICE_ID` must equal the Apple token audience accepted by `LuminaVaultServer` `OAUTH_APPLE_CLIENTID`.
- The production APNS topic must match `com.lumina.fernando`; the server must set `APNS_BUNDLE_ID=com.lumina.fernando`.
- RevenueCat webhook secret lives only on the server; the client only receives the public `LV_RC_API_KEY`.

## App Store service checklist

- Apple Developer App IDs have Push Notifications, Sign in with Apple, HealthKit, background delivery, and App Groups enabled.
- App Store Connect products exist for every RevenueCat product ID.
- RevenueCat offerings map products to entitlements such as `plus` and `pro`.
- Google OAuth iOS client has the correct bundle ID.
- X OAuth app has the exact redirect URI from the xcconfig.
- Sentry has separate environment filtering for `beta` and `production`.
