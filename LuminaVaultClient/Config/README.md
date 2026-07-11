# LuminaVaultClient Configuration

## Hybrid local execution

The execution profile and local endpoint URL/model are stored in app preferences. Optional endpoint API keys are stored in Keychain under `localEndpointAPIKey`. Do not add local endpoint credentials to xcconfig or Info.plist. Private mode must remain usable without `API_BASE_URL` reachability and must never silently fall back to cloud.

On iOS 26 and eligible Apple Intelligence devices, users can select the Apple on-device model. This uses the system Foundation Models runtime and does not require a downloaded third-party model or API key. Incrementally synchronized local memories are AES-GCM encrypted with a device-only Keychain key and protected with complete file protection.

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
| `X_REDIRECT_SCHEME` | Info.plist `CFBundleURLTypes` | Bare scheme registered for the X callback (e.g. `luminavault-debug`) |
| `X_REDIRECT_URI` | X sign-in callback | Full URI handed to X authorize; must share the scheme above and match X Developer Portal exactly |
| `LV_RC_API_KEY` | RevenueCat SDK | Public iOS SDK key |
| `POSTHOG_PROJECT_TOKEN` | PostHog SDK | Public client token |
| `POSTHOG_HOST` | PostHog SDK | Usually `https://us.i.posthog.com` |
| `SENTRY_DSN` | Sentry SDK | Public client DSN |
| `SENTRY_ENVIRONMENT` | Sentry SDK | `debug`, `beta`, or `production` |
| `KEYCHAIN_ACCESS_GROUP` | Host app and share extension | Shared access group for the auth token, normally `$(AppIdentifierPrefix)com.lumina.fernando.shared` |
| `WEBAUTHN_RP_ID` | Passkey enrollment/sign-in | Bare relying-party host; must match server `WEBAUTHN_RELYINGPARTYID` and the `webcredentials:<host>` associated-domain entitlement |
| `LV_TERMS_URL` | Settings/Billing UI | App Review legal link |
| `LV_PRIVACY_URL` | Settings/Billing UI | App Review legal link |

## Cross-repo invariants

- `GID_CLIENT_ID` must equal `LuminaVaultServer` `OAUTH_GOOGLE_CLIENTID`.
- `X_CLIENT_ID` must equal `LuminaVaultServer` `OAUTH_X_CLIENTID`.
- `X_REDIRECT_URI` must start with `$(X_REDIRECT_SCHEME)://` so the scheme registered in `CFBundleURLTypes` matches the URI sent to X.
- `APPLE_SERVICE_ID` must equal the Apple token audience accepted by `LuminaVaultServer` `OAUTH_APPLE_CLIENTID`.
- The production APNS topic must match `com.lumina.fernando`; the server must set `APNS_BUNDLE_ID=com.lumina.fernando`.
- RevenueCat webhook secret lives only on the server; the client only receives the public `LV_RC_API_KEY`.
- `KEYCHAIN_ACCESS_GROUP` must be identical in the host app and `LuminaVaultShareExtension` targets so the extension can read the signed-in user's access token.
- `WEBAUTHN_RP_ID` must exactly match `LuminaVaultServer` `WEBAUTHN_RELYINGPARTYID`; the same host must serve an `apple-app-site-association` file with a `webcredentials` block for the signed bundle ID.
- `group.com.lumina.fernando` must be present in both host app and share extension entitlements. The share extension uses it for queued captures, image sidecar files, and last-used Space preferences.
- `API_BASE_URL` must be available to both the host app and share extension. The extension uses it for direct URL, text, and image capture while the host app is not running.

## App Store service checklist

- Apple Developer App IDs have Push Notifications, Sign in with Apple, HealthKit, background delivery, App Groups, and Keychain Sharing enabled where required.
- Host app App IDs have Associated Domains enabled with `webcredentials:<WEBAUTHN_RP_ID>`.
- Share extension App IDs exist for Debug, Beta, and Release bundle IDs, with App Groups and Keychain Sharing enabled.
- App Store Connect products exist for every RevenueCat product ID.
- RevenueCat offerings map products to entitlements `pro` and `ultimate` (must match `RCEntitlement` in `Services/Billing/BillingService.swift`). See `docs/revenuecat-appstore-setup.md`.
- Google OAuth iOS client has the correct bundle ID.
- X OAuth app has the exact redirect URI from the xcconfig.
- Sentry has separate environment filtering for `beta` and `production`.
